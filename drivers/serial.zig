// Serial Port Driver for debugging

const port = @import("../arch/x86_64/port.zig");

const COM1: u16 = 0x3F8;

var initialized: bool = false;

pub fn init() void {
    // Disable interrupts
    port.outb(COM1 + 1, 0x00);

    // Enable DLAB (set baud rate divisor)
    port.outb(COM1 + 3, 0x80);

    // Set divisor to 3 (lo byte) 38400 baud
    port.outb(COM1 + 0, 0x03);
    port.outb(COM1 + 1, 0x00);

    // 8 bits, no parity, one stop bit
    port.outb(COM1 + 3, 0x03);

    // Enable FIFO, clear them, with 14-byte threshold
    port.outb(COM1 + 2, 0xC7);

    // IRQs enabled, RTS/DSR set
    port.outb(COM1 + 4, 0x0B);

    // Set in loopback mode, test the serial chip
    port.outb(COM1 + 4, 0x1E);

    // Test serial chip (send byte 0xAE and check if serial returns same byte)
    port.outb(COM1 + 0, 0xAE);

    // Check if serial is faulty (i.e: not same byte as sent)
    if (port.inb(COM1 + 0) != 0xAE) {
        initialized = false;
        return;
    }

    // If serial is not faulty set it in normal operation mode
    port.outb(COM1 + 4, 0x0F);
    initialized = true;
}

fn isTransmitEmpty() bool {
    return (port.inb(COM1 + 5) & 0x20) != 0;
}

pub fn putChar(c: u8) void {
    if (!initialized) return;

    while (!isTransmitEmpty()) {}
    port.outb(COM1, c);
}

pub fn writeString(str: []const u8) void {
    for (str) |c| {
        putChar(c);
    }
}

pub fn isInitialized() bool {
    return initialized;
}
