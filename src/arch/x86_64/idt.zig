//! Interrupt Descriptor Table for x86_64.

const isr = @import("isr.zig");
const pic = @import("pic.zig");
const gdt = @import("gdt.zig");

const Entry = packed struct(u128) {
    offset_low: u16,
    selector: u16,
    /// Interrupt Stack Table index (0 = keep the current stack).
    ist: u8,
    type_attr: u8,
    offset_mid: u16,
    offset_high: u32,
    reserved: u32,
};

const Pointer = packed struct(u80) {
    limit: u16,
    base: u64,
};

comptime {
    if (@bitSizeOf(Entry) != 128) @compileError("IDT entry must be 16 bytes");
    if (@bitSizeOf(Pointer) != 80) @compileError("IDTR must be 10 bytes");
}

/// present | ring 0 | 64-bit interrupt gate. An *interrupt* gate (0xE) clears
/// IF on entry; a trap gate (0xF) would not, and would let an IRQ re-enter the
/// handler on its own stack.
const GATE_INTERRUPT: u8 = 0x8E;

pub const VECTOR_COUNT = 256;

var idt: [VECTOR_COUNT]Entry align(16) = undefined;
var idt_ptr: Pointer align(16) = undefined;

pub fn init() void {
    // Remap the PIC before anything can fire: out of reset, IRQ 0-7 are mapped
    // onto vectors 8-15, which collide with the CPU's own exception vectors.
    pic.init();

    for (0..VECTOR_COUNT) |i| {
        if (i < isr.STUB_COUNT) {
            setGate(i, isr.getHandler(i), GATE_INTERRUPT, 0);
        } else {
            // Not present: taking one of these raises #GP (13) instead of
            // jumping through a garbage descriptor.
            setGate(i, 0, 0x00, 0);
        }
    }

    idt_ptr = .{
        .limit = @sizeOf(@TypeOf(idt)) - 1,
        .base = @intFromPtr(&idt),
    };

    load();
}

fn setGate(vector: usize, handler: u64, type_attr: u8, ist: u3) void {
    idt[vector] = .{
        .offset_low = @truncate(handler),
        .selector = gdt.KERNEL_CODE,
        .ist = ist,
        .type_attr = type_attr,
        .offset_mid = @truncate(handler >> 16),
        .offset_high = @truncate(handler >> 32),
        .reserved = 0,
    };
}

/// Route a vector onto one of the TSS interrupt stacks. Pair with
/// `tss.setInterruptStack`.
pub fn setIst(vector: usize, ist: u3) void {
    idt[vector].ist = ist;
}

fn load() void {
    asm volatile ("lidt (%%rax)"
        :
        : [ptr] "{rax}" (&idt_ptr),
        : .{ .rax = true, .memory = true }
    );
}

/// Interrupts stay masked until the caller explicitly asks for them. `init`
/// used to end with `sti`, which enabled IRQs from inside the IDT setup — before
/// the rest of the kernel had finished initialising.
pub fn enableInterrupts() void {
    asm volatile ("sti" ::: .{ .memory = true });
}

pub fn disableInterrupts() void {
    asm volatile ("cli" ::: .{ .memory = true });
}
