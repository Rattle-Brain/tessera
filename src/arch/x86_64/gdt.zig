// Global Descriptor Table for x86_64

const tss = @import("tss.zig");

const GdtEntry = packed struct {
    limit_low: u16,
    base_low: u16,
    base_middle: u8,
    access: u8,
    granularity: u8,
    base_high: u8,
};

// TSS descriptor in x86_64 is 16 bytes (2 GDT entries)
const TssDescriptor = packed struct {
    limit_low: u16,
    base_low: u16,
    base_middle: u8,
    access: u8,
    granularity: u8,
    base_high: u8,
    base_upper: u32,
    reserved: u32,
};

const GdtPointer = packed struct {
    limit: u16,
    base: u64,
};

var gdt: [7]GdtEntry align(16) = undefined;
var gdt_ptr: GdtPointer = undefined;


// Initialize the GDT with 5 GDT entries + TSS, according to https://wiki.osdev.org/GDT_Tutorial
// TODO: Analyze the case of the GDT, x86-64 does not use segmentation. This is mostly a linux thing
// and perhaps I can do away without it
pub fn init() void {
    // Null descriptor
    gdt[0] = makeEntry(0, 0, 0, 0);

    // Kernel code segment
    gdt[1] = makeEntry(0, 0xFFFFF, 0x9A, 0xA);

    // Kernel data segment
    gdt[2] = makeEntry(0, 0xFFFFF, 0x92, 0xC);

    // User data segment
    gdt[3] = makeEntry(0, 0xFFFFF, 0xF2, 0xC);

    // User code segment
    gdt[4] = makeEntry(0, 0xFFFFF, 0xFA, 0xA);

    // TSS descriptor (16 bytes, occupies entries 5 and 6)
    const tss_addr = @intFromPtr(tss.getTss());
    const tss_limit = @sizeOf(tss.Tss) - 1;
    const tss_descriptor = makeTssEntry(tss_addr, tss_limit, 0x89, 0x0);

    // Copy TSS descriptor into GDT (it takes 2 entries worth of space)
    @memcpy(@as([*]u8, @ptrCast(&gdt[5]))[0..16], @as([*]const u8, @ptrCast(&tss_descriptor))[0..16]);

    gdt_ptr.limit = @sizeOf(@TypeOf(gdt)) - 1;
    gdt_ptr.base = @intFromPtr(&gdt);

    load();
    loadTss();
}

fn makeEntry(base: u32, limit: u32, access: u8, flags: u8) GdtEntry {
    return GdtEntry{
        .limit_low = @truncate(limit & 0xFFFF),
        .base_low = @truncate(base & 0xFFFF),
        .base_middle = @truncate((base >> 16) & 0xFF),
        .access = access,
        .granularity = @truncate(((limit >> 16) & 0x0F) | (flags << 4)),
        .base_high = @truncate((base >> 24) & 0xFF),
    };
}

fn makeTssEntry(base: u64, limit: u32, access: u8, flags: u8) TssDescriptor {
    return TssDescriptor{
        .limit_low = @truncate(limit & 0xFFFF),
        .base_low = @truncate(base & 0xFFFF),
        .base_middle = @truncate((base >> 16) & 0xFF),
        .access = access,
        .granularity = @truncate(((limit >> 16) & 0x0F) | (flags << 4)),
        .base_high = @truncate((base >> 24) & 0xFF),
        .base_upper = @truncate((base >> 32) & 0xFFFFFFFF),
        .reserved = 0,
    };
}

fn load() void {
    const ptr_addr = @intFromPtr(&gdt_ptr);
    asm volatile (
        \\lgdtq (%%rbx)
        \\pushq $0x08
        \\leaq 1f(%%rip), %%rax
        \\pushq %%rax
        \\retq
        \\1:
        \\movw $0x10, %%ax
        \\movw %%ax, %%ds
        \\movw %%ax, %%es
        \\movw %%ax, %%fs
        \\movw %%ax, %%gs
        \\movw %%ax, %%ss
        :
        : [_] "{rbx}" (ptr_addr),
        : .{ .rax = true, .rbx = true }
    );
}

fn loadTss() void {
    // TSS is at index 5 in GDT (0x28 = 5 * 8)
    asm volatile (
        \\movw $0x28, %%ax
        \\ltr %%ax
        :
        :
        : .{.rax = true}
    );
}
