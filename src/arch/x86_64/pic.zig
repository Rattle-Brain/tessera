//! 8259A PIC driver.
//!
//! Out of reset the master PIC maps IRQ 0-7 onto vectors 8-15, which collide
//! with the CPU's own exception vectors (#DF, #GP, #PF...). Remapping to 32-47
//! is the first thing that has to happen before interrupts are ever enabled.

const port = @import("port.zig");

const PIC1_COMMAND: u16 = 0x20;
const PIC1_DATA: u16 = 0x21;
const PIC2_COMMAND: u16 = 0xA0;
const PIC2_DATA: u16 = 0xA1;

const ICW1_ICW4: u8 = 0x01;
const ICW1_INIT: u8 = 0x10;
const ICW4_8086: u8 = 0x01;

const PIC_EOI: u8 = 0x20;

pub const VECTOR_BASE: u8 = 32;

/// Remap both PICs and leave every line masked. Callers unmask what they are
/// actually ready to handle (see `unmaskIRQ`); the previous version unmasked the
/// timer and keyboard here, so IRQs could arrive mid-initialisation.
pub fn init() void {
    port.outb(PIC1_COMMAND, ICW1_INIT | ICW1_ICW4);
    port.io_wait();
    port.outb(PIC2_COMMAND, ICW1_INIT | ICW1_ICW4);
    port.io_wait();

    // ICW2: vector offsets.
    port.outb(PIC1_DATA, VECTOR_BASE); // IRQ 0-7  -> 32-39
    port.io_wait();
    port.outb(PIC2_DATA, VECTOR_BASE + 8); // IRQ 8-15 -> 40-47
    port.io_wait();

    // ICW3: cascade wiring (slave on the master's IRQ2).
    port.outb(PIC1_DATA, 0x04);
    port.io_wait();
    port.outb(PIC2_DATA, 0x02);
    port.io_wait();

    // ICW4: 8086/88 mode.
    port.outb(PIC1_DATA, ICW4_8086);
    port.io_wait();
    port.outb(PIC2_DATA, ICW4_8086);
    port.io_wait();

    port.outb(PIC1_DATA, 0xFF);
    port.outb(PIC2_DATA, 0xFF);
}

/// Mask every line. Use before switching to the APIC.
pub fn disable() void {
    port.outb(PIC1_DATA, 0xFF);
    port.outb(PIC2_DATA, 0xFF);
}

pub fn sendEOI(irq: u8) void {
    // A line on the slave has to be acknowledged on both chips, slave first.
    if (irq >= 8) port.outb(PIC2_COMMAND, PIC_EOI);
    port.outb(PIC1_COMMAND, PIC_EOI);
}

pub fn maskIRQ(irq: u8) void {
    if (irq >= 16) return;
    const io_port: u16 = if (irq < 8) PIC1_DATA else PIC2_DATA;
    const bit: u3 = @intCast(irq % 8);
    port.outb(io_port, port.inb(io_port) | (@as(u8, 1) << bit));
}

pub fn unmaskIRQ(irq: u8) void {
    if (irq >= 16) return;
    const io_port: u16 = if (irq < 8) PIC1_DATA else PIC2_DATA;
    const bit: u3 = @intCast(irq % 8);
    port.outb(io_port, port.inb(io_port) & ~(@as(u8, 1) << bit));

    // Anything on the slave is invisible until the cascade line itself is open.
    if (irq >= 8) {
        port.outb(PIC1_DATA, port.inb(PIC1_DATA) & ~@as(u8, 1 << 2));
    }
}

pub fn getMask() u16 {
    return @as(u16, port.inb(PIC1_DATA)) | (@as(u16, port.inb(PIC2_DATA)) << 8);
}
