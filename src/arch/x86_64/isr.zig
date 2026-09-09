//! Interrupt Service Routines.
//!
//! The assembly stubs in isr.S push a uniform frame and call `interruptHandler`.

const log = @import("../../kernel/log.zig");
const panic = @import("../../kernel/panic.zig");
const pic = @import("pic.zig");

/// Layout must match exactly what isr.S pushes, bottom of the stack first.
/// `extern struct` (C layout, no reordering, no padding for these all-u64
/// fields) is what makes that guarantee.
pub const InterruptFrame = extern struct {
    // Pushed by isr_common_stub, in reverse push order.
    r15: u64,
    r14: u64,
    r13: u64,
    r12: u64,
    r11: u64,
    r10: u64,
    r9: u64,
    r8: u64,
    rbp: u64,
    rdi: u64,
    rsi: u64,
    rdx: u64,
    rcx: u64,
    rbx: u64,
    rax: u64,

    // Pushed by the per-vector stub (the error code is either the CPU's or a
    // zero placeholder, so the layout is identical for every vector).
    interrupt_number: u64,
    error_code: u64,

    // Pushed by the CPU.
    rip: u64,
    cs: u64,
    rflags: u64,
    rsp: u64,
    ss: u64,
};

comptime {
    if (@sizeOf(InterruptFrame) != 22 * 8) @compileError("InterruptFrame must be 22 qwords");
}

pub const IRQ_BASE = 32;
pub const IRQ_COUNT = 16;
/// Number of stubs isr.S actually defines: 32 CPU exceptions + 16 PIC IRQs.
pub const STUB_COUNT = IRQ_BASE + IRQ_COUNT;

extern const isr_stub_table: [STUB_COUNT]u64;

pub fn getHandler(vector: usize) u64 {
    return isr_stub_table[vector];
}

const exception_names = [32][]const u8{
    "divide by zero (#DE)",
    "debug (#DB)",
    "non-maskable interrupt",
    "breakpoint (#BP)",
    "overflow (#OF)",
    "bound range exceeded (#BR)",
    "invalid opcode (#UD)",
    "device not available (#NM)",
    "double fault (#DF)",
    "coprocessor segment overrun",
    "invalid TSS (#TS)",
    "segment not present (#NP)",
    "stack-segment fault (#SS)",
    "general protection fault (#GP)",
    "page fault (#PF)",
    "reserved (15)",
    "x87 floating-point (#MF)",
    "alignment check (#AC)",
    "machine check (#MC)",
    "SIMD floating-point (#XM)",
    "virtualisation (#VE)",
    "control protection (#CP)",
    "reserved (22)",
    "reserved (23)",
    "reserved (24)",
    "reserved (25)",
    "reserved (26)",
    "reserved (27)",
    "hypervisor injection (#HV)",
    "VMM communication (#VC)",
    "security exception (#SX)",
    "reserved (31)",
};

/// Vectors we can return from. Everything else is a bug in the kernel and gets
/// reported rather than silently retried.
fn isRecoverable(vector: u64) bool {
    return switch (vector) {
        1, 3 => true, // #DB, #BP: debug traps
        else => false,
    };
}

/// Per-IRQ hooks. `null` means "acknowledge and ignore".
var irq_handlers: [IRQ_COUNT]?*const fn (*const InterruptFrame) void = @splat(null);

pub fn setIrqHandler(irq: u8, handler: ?*const fn (*const InterruptFrame) void) void {
    if (irq < IRQ_COUNT) irq_handlers[irq] = handler;
}

export fn interruptHandler(frame: *const InterruptFrame) callconv(.c) void {
    const vector = frame.interrupt_number;

    if (vector >= IRQ_BASE and vector < IRQ_BASE + IRQ_COUNT) {
        const irq: u8 = @intCast(vector - IRQ_BASE);
        if (irq_handlers[irq]) |handler| handler(frame);
        // Unhandled lines still have to be acknowledged, or the PIC never
        // delivers this IRQ again. (A handler that panics never gets here, but
        // panicking halts for good, so the PIC state no longer matters.)
        pic.sendEOI(irq);
        return;
    }

    if (vector < 32) {
        reportException(frame);
        // Returning from a fault re-executes the faulting instruction, which
        // just faults again forever. Stop instead.
        if (!isRecoverable(vector)) panic.call(exception_names[@intCast(vector)], frame.rip);
        return;
    }

    reportException(frame);
    panic.call("unexpected interrupt vector", frame.rip);
}

fn reportException(frame: *const InterruptFrame) void {
    const vector = frame.interrupt_number;

    log.nl();
    log.str("EXCEPTION ");
    log.dec(vector);
    log.str(": ");
    log.line(if (vector < 32) exception_names[@intCast(vector)] else "unknown");

    log.str("  rip=");
    log.hex(frame.rip);
    log.str(" cs=");
    log.hexWidth(frame.cs, 4);
    log.str(" rflags=");
    log.hexWidth(frame.rflags, 8);
    log.nl();

    log.str("  rsp=");
    log.hex(frame.rsp);
    log.str(" ss=");
    log.hexWidth(frame.ss, 4);
    log.str(" err=");
    log.hexWidth(frame.error_code, 8);
    log.nl();

    if (vector == 14) {
        log.str("  cr2=");
        log.hex(readCr2());
        log.str(" (");
        // Page fault error code bits: P W/R U/S RSVD I/D
        log.str(if (frame.error_code & 1 != 0) "protection" else "not-present");
        log.str(if (frame.error_code & 2 != 0) ", write" else ", read");
        log.str(if (frame.error_code & 4 != 0) ", user" else ", kernel");
        if (frame.error_code & 16 != 0) log.str(", instruction fetch");
        log.line(")");
    }
}

fn readCr2() u64 {
    return asm volatile ("movq %%cr2, %[out]"
        : [out] "=r" (-> u64),
    );
}
