//! Global Descriptor Table for long mode.
//!
//! boot.S installs a throwaway GDT to get into 64-bit mode; this replaces it
//! with the permanent one, which additionally carries a TSS (needed later for
//! ring transitions and for interrupt stack tables).
//!
//! Long mode ignores base/limit on code and data descriptors, but the encoding
//! still has to be well formed, so the fields are filled in as if they mattered.

const tss = @import("tss.zig");

pub const KERNEL_CODE: u16 = 0x08;
pub const KERNEL_DATA: u16 = 0x10;
pub const USER_DATA: u16 = 0x18;
pub const USER_CODE: u16 = 0x20;
pub const TSS_SELECTOR: u16 = 0x28;

const Entry = packed struct(u64) {
    limit_low: u16,
    base_low: u16,
    base_middle: u8,
    access: u8,
    granularity: u8,
    base_high: u8,
};

/// A 64-bit TSS descriptor is 16 bytes and therefore occupies two GDT slots.
const TssDescriptor = packed struct(u128) {
    limit_low: u16,
    base_low: u16,
    base_middle: u8,
    access: u8,
    granularity: u8,
    base_high: u8,
    base_upper: u32,
    reserved: u32,
};

const Pointer = packed struct(u80) {
    limit: u16,
    base: u64,
};

comptime {
    // `lgdt` and the CPU's descriptor walk both depend on these exact sizes.
    if (@bitSizeOf(Entry) != 64) @compileError("GDT entry must be 8 bytes");
    if (@bitSizeOf(TssDescriptor) != 128) @compileError("TSS descriptor must be 16 bytes");
    if (@bitSizeOf(Pointer) != 80) @compileError("GDTR must be 10 bytes");
}

/// 5 segment descriptors + 2 slots for the 16-byte TSS descriptor.
const ENTRY_COUNT = 7;
const TSS_INDEX = 5;

var gdt: [ENTRY_COUNT]Entry align(16) = undefined;
var gdt_ptr: Pointer align(16) = undefined;

pub fn init() void {
    gdt[0] = makeEntry(0, 0, 0, 0); // null descriptor
    gdt[1] = makeEntry(0, 0xFFFFF, 0x9A, 0xA); // ring 0 code, L=1
    gdt[2] = makeEntry(0, 0xFFFFF, 0x92, 0xC); // ring 0 data
    gdt[3] = makeEntry(0, 0xFFFFF, 0xF2, 0xC); // ring 3 data
    gdt[4] = makeEntry(0, 0xFFFFF, 0xFA, 0xA); // ring 3 code, L=1

    // 0x89 = present, ring 0, type 9 (available 64-bit TSS).
    const desc = makeTssEntry(@intFromPtr(tss.getTss()), tss.SIZE - 1, 0x89, 0x0);
    const words: [2]u64 = .{
        @truncate(@as(u128, @bitCast(desc))),
        @truncate(@as(u128, @bitCast(desc)) >> 64),
    };
    gdt[TSS_INDEX] = @bitCast(words[0]);
    gdt[TSS_INDEX + 1] = @bitCast(words[1]);

    gdt_ptr = .{
        .limit = @sizeOf(@TypeOf(gdt)) - 1,
        .base = @intFromPtr(&gdt),
    };

    load();
    loadTss();
}

fn makeEntry(base: u32, limit: u32, access: u8, flags: u8) Entry {
    return .{
        .limit_low = @truncate(limit),
        .base_low = @truncate(base),
        .base_middle = @truncate(base >> 16),
        .access = access,
        .granularity = @as(u8, @truncate((limit >> 16) & 0x0F)) | (flags << 4),
        .base_high = @truncate(base >> 24),
    };
}

fn makeTssEntry(base: u64, limit: u32, access: u8, flags: u8) TssDescriptor {
    return .{
        .limit_low = @truncate(limit),
        .base_low = @truncate(base),
        .base_middle = @truncate(base >> 16),
        .access = access,
        .granularity = @as(u8, @truncate((limit >> 16) & 0x0F)) | (flags << 4),
        .base_high = @truncate(base >> 24),
        .base_upper = @truncate(base >> 32),
        .reserved = 0,
    };
}

fn load() void {
    // CS cannot be loaded with a plain `mov`, so the new selector is installed
    // with a far return: push the target CS and RIP, then `lretq`.
    //
    // This used to use `retq`, which is a *near* return — it popped RIP, left
    // the pushed selector stranded on the stack (leaking 8 bytes per call) and
    // never actually reloaded CS.
    // Zig's inline assembler does not accept `(%[name])` memory operands, so the
    // GDTR pointer is pinned into a specific register and dereferenced by name.
    asm volatile (
        \\lgdt (%%rcx)
        \\pushq %[code_sel]
        \\leaq 1f(%%rip), %%rax
        \\pushq %%rax
        \\lretq
        \\1:
        \\movw %[data_sel], %%ax
        \\movw %%ax, %%ds
        \\movw %%ax, %%es
        \\movw %%ax, %%fs
        \\movw %%ax, %%gs
        \\movw %%ax, %%ss
        :
        : [ptr] "{rcx}" (&gdt_ptr),
          [code_sel] "i" (@as(u64, KERNEL_CODE)),
          [data_sel] "i" (KERNEL_DATA),
        : .{ .rax = true, .rcx = true, .memory = true }
    );
}

fn loadTss() void {
    asm volatile ("ltr %[sel]"
        :
        : [sel] "r" (TSS_SELECTOR),
        : .{ .memory = true }
    );
}
