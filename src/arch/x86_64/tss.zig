//! Task State Segment for x86_64.
//! See https://wiki.osdev.org/Task_State_Segment
//!
//! Long mode does not use the TSS for task switching; it only holds the stack
//! pointers the CPU switches to on a privilege change (rsp0..rsp2) and the
//! Interrupt Stack Table.

pub const Tss = packed struct {
    reserved1: u32 = 0,
    rsp0: u64 = 0, // stack used when entering ring 0 from a lower ring
    rsp1: u64 = 0,
    rsp2: u64 = 0,
    reserved2: u64 = 0,
    ist1: u64 = 0,
    ist2: u64 = 0,
    ist3: u64 = 0,
    ist4: u64 = 0,
    ist5: u64 = 0,
    ist6: u64 = 0,
    ist7: u64 = 0,
    reserved3: u64 = 0,
    reserved4: u16 = 0,
    /// I/O permission bitmap offset. Any value past the segment limit disables
    /// the bitmap, which is what we want.
    iopb: u16 = SIZE,
};

/// Architectural TSS size. Derived from `@bitSizeOf` rather than `@sizeOf`
/// because `@sizeOf` on a packed struct rounds up to the backing integer's
/// alignment, which would put a bogus limit in the GDT descriptor.
pub const SIZE: u16 = @bitSizeOf(Tss) / 8;

comptime {
    if (SIZE != 104) @compileError("x86_64 TSS must be 104 bytes");
}

var tss: Tss align(16) = .{};

pub fn init() void {
    tss = .{};
}

/// Stack the CPU switches to on a ring 3 -> ring 0 transition.
pub fn setKernelStack(rsp: u64) void {
    tss.rsp0 = rsp;
}

/// Install a dedicated stack for an IST slot (1-7). Vector entries in the IDT
/// referencing that slot will switch to this stack unconditionally, which is how
/// a double fault handler survives a blown kernel stack.
pub fn setInterruptStack(slot: u3, rsp: u64) void {
    switch (slot) {
        1 => tss.ist1 = rsp,
        2 => tss.ist2 = rsp,
        3 => tss.ist3 = rsp,
        4 => tss.ist4 = rsp,
        5 => tss.ist5 = rsp,
        6 => tss.ist6 = rsp,
        7 => tss.ist7 = rsp,
        0 => {},
    }
}

pub fn getTss() *Tss {
    return &tss;
}
