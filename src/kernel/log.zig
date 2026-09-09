//! Tiny kernel console: tees to VGA text mode and COM1.
//!
//! This deliberately does not use `std.fmt`. Pulling std's formatting into a
//! freestanding kernel drags in the whole Io/Writer stack and inflated the
//! image by hundreds of kilobytes for the sake of printing a few integers.

const vga = @import("../drivers/vga.zig");
const serial = @import("../drivers/serial.zig");

pub fn str(s: []const u8) void {
    vga.writeString(s);
    serial.writeString(s);
}

pub fn ch(c: u8) void {
    vga.putChar(c);
    serial.putChar(c);
}

pub fn nl() void {
    str("\n");
}

pub fn line(s: []const u8) void {
    str(s);
    nl();
}

/// Unsigned decimal. 20 digits is enough for any u64.
pub fn dec(value: u64) void {
    var buf: [20]u8 = undefined;
    var i: usize = buf.len;
    var v = value;
    while (true) {
        i -= 1;
        buf[i] = '0' + @as(u8, @intCast(v % 10));
        v /= 10;
        if (v == 0) break;
    }
    str(buf[i..]);
}

/// Zero-padded hex, `digits` wide, prefixed with "0x".
pub fn hexWidth(value: u64, digits: usize) void {
    const table = "0123456789ABCDEF";
    str("0x");
    var shift: usize = digits * 4;
    while (shift > 0) {
        shift -= 4;
        ch(table[@as(usize, @intCast((value >> @intCast(shift)) & 0xF))]);
    }
}

pub fn hex(value: u64) void {
    hexWidth(value, 16);
}

/// Human-readable byte count, rounded down.
pub fn bytes(n: u64) void {
    const KiB = 1024;
    const MiB = 1024 * KiB;
    const GiB = 1024 * MiB;
    if (n >= GiB) {
        dec(n / GiB);
        str(" GiB");
    } else if (n >= MiB) {
        dec(n / MiB);
        str(" MiB");
    } else if (n >= KiB) {
        dec(n / KiB);
        str(" KiB");
    } else {
        dec(n);
        str(" B");
    }
}
