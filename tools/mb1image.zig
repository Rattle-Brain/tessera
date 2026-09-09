//! Repack the ELF64 kernel as an ELF32 image with the same PT_LOAD segments.
//!
//! QEMU's `-kernel` Multiboot loader only accepts ELFCLASS32 files ("Cannot
//! load x86-64 image, give a 32bit one"), even though the Multiboot handoff
//! itself is 32-bit protected mode regardless of what the kernel does next. Real
//! bootloaders (GRUB) have no such restriction.
//!
//! Only the container changes: segment contents, load addresses and the entry
//! point are copied verbatim, and `_start` is 32-bit code anyway. Written as a
//! host-side Zig tool so `zig build run` needs nothing but Zig and QEMU — no
//! objcopy (Zig's own does not do ELF class conversion) and no GRUB.

const std = @import("std");
const elf = std.elf;
const Io = std.Io;

const Segment = struct {
    flags: u32,
    file_offset: u64,
    vaddr: u64,
    paddr: u64,
    filesz: u64,
    memsz: u64,
    alignment: u64,
};

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(arena);

    if (args.len != 3) std.process.fatal("usage: {s} <elf64-in> <elf32-out>", .{args[0]});
    const in_path = args[1];
    const out_path = args[2];

    const image = Io.Dir.cwd().readFileAlloc(io, in_path, arena, .unlimited) catch |err|
        std.process.fatal("failed to read {s}: {t}", .{ in_path, err });

    if (image.len < @sizeOf(elf.Elf64_Ehdr)) std.process.fatal("{s}: too short to be an ELF", .{in_path});
    const ehdr: *align(1) const elf.Elf64_Ehdr = @ptrCast(image.ptr);
    if (!std.mem.eql(u8, ehdr.e_ident[0..4], elf.MAGIC)) std.process.fatal("{s}: not an ELF file", .{in_path});
    if (ehdr.e_ident[elf.EI_CLASS] != elf.ELFCLASS64) std.process.fatal("{s}: expected ELFCLASS64", .{in_path});
    if (ehdr.e_entry >= 1 << 32) std.process.fatal("{s}: entry point 0x{x} does not fit in 32 bits", .{ in_path, ehdr.e_entry });

    var segments: std.ArrayList(Segment) = .empty;
    for (0..ehdr.e_phnum) |i| {
        const off = ehdr.e_phoff + i * ehdr.e_phentsize;
        if (off + @sizeOf(elf.Elf64_Phdr) > image.len) std.process.fatal("{s}: truncated program header table", .{in_path});
        const phdr: *align(1) const elf.Elf64_Phdr = @ptrCast(image.ptr + off);
        if (phdr.p_type != elf.PT_LOAD or phdr.p_memsz == 0) continue;
        if (phdr.p_vaddr >= 1 << 32 or phdr.p_paddr + phdr.p_memsz > 1 << 32) {
            std.process.fatal("{s}: segment at 0x{x} lies above 4 GiB", .{ in_path, phdr.p_vaddr });
        }
        try segments.append(arena, .{
            .flags = phdr.p_flags,
            .file_offset = phdr.p_offset,
            .vaddr = phdr.p_vaddr,
            .paddr = phdr.p_paddr,
            .filesz = phdr.p_filesz,
            .memsz = phdr.p_memsz,
            .alignment = phdr.p_align,
        });
    }
    if (segments.items.len == 0) std.process.fatal("{s}: no loadable segments", .{in_path});

    const ehdr32_size = @sizeOf(elf.Elf32_Ehdr);
    const phdr32_size = @sizeOf(elf.Elf32_Phdr);
    // Segment data starts right after the headers, so the Multiboot header —
    // which lives in the first loadable segment — stays well inside the first
    // 8 KiB of the file where QEMU looks for it.
    const data_start = std.mem.alignForward(usize, ehdr32_size + phdr32_size * segments.items.len, 16);

    var out: std.ArrayList(u8) = .empty;
    var blob: std.ArrayList(u8) = .empty;
    var phdrs: std.ArrayList(u8) = .empty;

    for (segments.items) |seg| {
        const seg_off = data_start + blob.items.len;
        try blob.appendSlice(arena, image[@intCast(seg.file_offset)..][0..@intCast(seg.filesz)]);
        // Keep each segment's file offset 4-byte aligned for tidiness.
        try blob.appendNTimes(arena, 0, std.mem.alignForward(usize, blob.items.len, 4) - blob.items.len);

        const phdr: elf.Elf32_Phdr = .{
            .p_type = elf.PT_LOAD,
            .p_offset = @intCast(seg_off),
            .p_vaddr = @intCast(seg.vaddr),
            .p_paddr = @intCast(seg.paddr),
            .p_filesz = @intCast(seg.filesz),
            .p_memsz = @intCast(seg.memsz),
            .p_flags = seg.flags,
            .p_align = @intCast(@min(seg.alignment, 4096)),
        };
        try phdrs.appendSlice(arena, std.mem.asBytes(&phdr));
    }

    var ident: [elf.EI_NIDENT]u8 = @splat(0);
    @memcpy(ident[0..4], elf.MAGIC);
    ident[elf.EI_CLASS] = elf.ELFCLASS32;
    ident[elf.EI_DATA] = elf.ELFDATA2LSB;
    ident[elf.EI_VERSION] = 1;

    const out_ehdr: elf.Elf32_Ehdr = .{
        .e_ident = ident,
        .e_type = elf.ET.EXEC,
        .e_machine = .@"386",
        .e_version = 1,
        .e_entry = @intCast(ehdr.e_entry),
        .e_phoff = ehdr32_size,
        .e_shoff = 0,
        .e_flags = 0,
        .e_ehsize = ehdr32_size,
        .e_phentsize = phdr32_size,
        .e_phnum = @intCast(segments.items.len),
        .e_shentsize = @sizeOf(elf.Elf32_Shdr),
        .e_shnum = 0,
        .e_shstrndx = 0,
    };

    try out.appendSlice(arena, std.mem.asBytes(&out_ehdr));
    try out.appendSlice(arena, phdrs.items);
    try out.appendNTimes(arena, 0, data_start - out.items.len);
    try out.appendSlice(arena, blob.items);

    Io.Dir.cwd().writeFile(io, .{ .sub_path = out_path, .data = out.items }) catch |err|
        std.process.fatal("failed to write {s}: {t}", .{ out_path, err });
}
