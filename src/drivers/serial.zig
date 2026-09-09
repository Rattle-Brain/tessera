//! 16550 UART driver on COM1, used as the kernel's debug console.

const port = @import("../arch/x86_64/port.zig");

const COM1: u16 = 0x3F8;

// Register offsets (DLAB=0 unless noted).
const REG_DATA = 0; // also divisor low when DLAB=1
const REG_IER = 1; // also divisor high when DLAB=1
const REG_FCR = 2;
const REG_LCR = 3;
const REG_MCR = 4;
const REG_LSR = 5;

const LSR_THRE: u8 = 0x20; // transmit holding register empty
const LSR_DATA_READY: u8 = 0x01;

var initialized: bool = false;

pub fn init() void {
    initialized = false;

    port.outb(COM1 + REG_IER, 0x00); // no interrupts
    port.outb(COM1 + REG_LCR, 0x80); // enable DLAB
    port.outb(COM1 + REG_DATA, 0x03); // divisor 3 -> 38400 baud
    port.outb(COM1 + REG_IER, 0x00);
    port.outb(COM1 + REG_LCR, 0x03); // 8 bits, no parity, 1 stop
    port.outb(COM1 + REG_FCR, 0xC7); // FIFO on, cleared, 14-byte threshold
    port.outb(COM1 + REG_MCR, 0x0B); // DTR + RTS + OUT2

    // Loopback self-test: write a byte and check it comes straight back.
    port.outb(COM1 + REG_MCR, 0x1E);
    port.outb(COM1 + REG_DATA, 0xAE);
    if (port.inb(COM1 + REG_DATA) != 0xAE) return; // stays uninitialized

    port.outb(COM1 + REG_MCR, 0x0F); // back to normal operation
    initialized = true;
}

fn transmitEmpty() bool {
    return port.inb(COM1 + REG_LSR) & LSR_THRE != 0;
}

fn putRaw(c: u8) void {
    while (!transmitEmpty()) {}
    port.outb(COM1 + REG_DATA, c);
}

pub fn putChar(c: u8) void {
    if (!initialized) return;
    // Terminals expect CRLF; the kernel emits bare LF.
    if (c == '\n') putRaw('\r');
    putRaw(c);
}

pub fn writeString(str: []const u8) void {
    if (!initialized) return;
    for (str) |c| putChar(c);
}

pub fn dataAvailable() bool {
    return initialized and port.inb(COM1 + REG_LSR) & LSR_DATA_READY != 0;
}

pub fn readChar() ?u8 {
    if (!dataAvailable()) return null;
    return port.inb(COM1 + REG_DATA);
}

pub fn isInitialized() bool {
    return initialized;
}
