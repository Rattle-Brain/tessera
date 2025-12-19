// 8259 PIC (Programmable Interrupt Controller) driver
// Handles remapping of hardware IRQs to avoid conflicts with CPU exceptions

const port = @import("port.zig");

// PIC I/O ports
const PIC1_COMMAND: u16 = 0x20;
const PIC1_DATA: u16 = 0x21;
const PIC2_COMMAND: u16 = 0xA0;
const PIC2_DATA: u16 = 0xA1;

// ICW1 (Initialization Command Word 1)
const ICW1_ICW4: u8 = 0x01; // ICW4 needed
const ICW1_INIT: u8 = 0x10; // Initialization

// ICW4 (Initialization Command Word 4)
const ICW4_8086: u8 = 0x01; // 8086/88 mode

// End of Interrupt command
const PIC_EOI: u8 = 0x20;

// Remap the PIC to use interrupt vectors 32-47
// By default, IRQ 0-7 map to vectors 8-15 (conflicts with CPU exceptions!)
// We remap them to vectors 32-47
pub fn init() void {
    // Save current masks
    const mask1 = port.inb(PIC1_DATA);
    const mask2 = port.inb(PIC2_DATA);

    // Start initialization sequence (ICW1)
    port.outb(PIC1_COMMAND, ICW1_INIT | ICW1_ICW4);
    port.io_wait();
    port.outb(PIC2_COMMAND, ICW1_INIT | ICW1_ICW4);
    port.io_wait();

    // ICW2: Set vector offsets
    // Master PIC: IRQ 0-7 -> vectors 32-39
    port.outb(PIC1_DATA, 32);
    port.io_wait();
    // Slave PIC: IRQ 8-15 -> vectors 40-47
    port.outb(PIC2_DATA, 40);
    port.io_wait();

    // ICW3: Tell Master PIC there is a slave at IRQ2 (0000 0100)
    port.outb(PIC1_DATA, 0x04);
    port.io_wait();
    // ICW3: Tell Slave PIC its cascade identity (0000 0010)
    port.outb(PIC2_DATA, 0x02);
    port.io_wait();

    // ICW4: Set 8086 mode
    port.outb(PIC1_DATA, ICW4_8086);
    port.io_wait();
    port.outb(PIC2_DATA, ICW4_8086);
    port.io_wait();

    // Restore saved masks (or set new ones)
    // For now, mask all interrupts except timer (IRQ0) and keyboard (IRQ1)
    _ = mask1;
    _ = mask2;
    port.outb(PIC1_DATA, 0xFC); // 1111 1100 - only IRQ0 and IRQ1 enabled
    port.outb(PIC2_DATA, 0xFF); // 1111 1111 - all slave IRQs masked
}

// Send End of Interrupt signal
pub fn sendEOI(irq: u8) void {
    if (irq >= 8) {
        // IRQ came from slave PIC, send EOI to slave first
        port.outb(PIC2_COMMAND, PIC_EOI);
    }
    // Always send EOI to master
    port.outb(PIC1_COMMAND, PIC_EOI);
}

// Mask (disable) a specific IRQ
pub fn maskIRQ(irq: u8) void {
    var io_port: u16 = undefined;
    var irq_line: u8 = irq;

    if (irq < 8) {
        io_port = PIC1_DATA;
    } else {
        io_port = PIC2_DATA;
        irq_line -= 8;
    }

    const mask = port.inb(io_port) | (@as(u8, 1) << @intCast(irq_line));
    port.outb(io_port, mask);
}

// Unmask (enable) a specific IRQ
pub fn unmaskIRQ(irq: u8) void {
    var io_port: u16 = undefined;
    var irq_line: u8 = irq;

    if (irq < 8) {
        io_port = PIC1_DATA;
    } else {
        io_port = PIC2_DATA;
        irq_line -= 8;
    }

    const mask = port.inb(io_port) & ~(@as(u8, 1) << @intCast(irq_line));
    port.outb(io_port, mask);
}
