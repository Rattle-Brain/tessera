// Interrupt Service Routines
const vga = @import("../../drivers/vga.zig");
const port = @import("port.zig");
const std = @import("std");

// This struct MUST perfectly match the order of registers we push onto the
// stack in isr.S and the frame the CPU pushes.
// It's packed to ensure no padding is added by the compiler.
pub const InterruptFrame = extern struct {
    // Registers pushed by our common stub
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

    // Pushed by our ISR stub
    interrupt_number: u64,
    error_code: u64,

    // Pushed by the CPU automatically on interrupt
    rip: u64,
    cs: u64,
    rflags: u64,
    rsp: u64,
    ss: u64,
};

// This is the single, high-level interrupt handler called from isr_common_stub.
// It's `export` so the assembly can see it.
export fn interruptHandler(frame: *const InterruptFrame) void {
    switch (frame.interrupt_number) {
        // CPU Exceptions 0-31
        0 => vga.writeString("Divide by zero error!"),
        8 => vga.writeString("Double Fault! Error"),
        13 => vga.writeString("General Protection Fault! Error"),
        14 => vga.writeString("Page Fault! Error"),
        15...31 => {
            // Handle other exceptions
            vga.writeString("Unhandled CPU Exception");
        },

        // Hardware IRQs 32-47
        32 => {
            // Timer interrupt, do nothing for now
        },
        33 => {
            vga.writeString("K"); // Keyboard press!
        },
        34...47 => {
            // Handle other hardware interrupts
            // vga.writeString("IRQ: {}\n", .{frame.interrupt_number});
        },

        else => {
            // Should not happen
            vga.writeString("Unknown Interrupt");
        },
    }

    // If the interrupt was an IRQ (32-47), we must send an End-Of-Interrupt (EOI)
    // signal to the PICs.
    if (frame.interrupt_number >= 32 and frame.interrupt_number < 48) {
        // If the IRQ came from the slave PIC (IRQ 8-15, which are vectors 40-47),
        // we need to send an EOI to the slave controller.
        if (frame.interrupt_number >= 40) {
            port.outb(0xA0, 0x20); // EOI to slave
        }
        // Always send an EOI to the master controller.
        port.outb(0x20, 0x20); // EOI to master
    }
}

// We need a way to get the addresses of our assembly stubs to load into the IDT.
// We'll create an array of them in assembly and import it here.
extern const isr_stub_table: [256]u64;

// This function can now be used by your IDT setup code.
pub fn getHandler(interrupt: usize) u64 {
    // The table is defined in the linker script or assembly.
    // It's an array of pointers to isr0, isr1, isr2, etc.
    return isr_stub_table[interrupt];
}
