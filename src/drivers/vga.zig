//! VGA text mode driver (80x25, colour attribute per cell).

const port = @import("../arch/x86_64/port.zig");

pub const WIDTH: usize = 80;
pub const HEIGHT: usize = 25;

const VGA_MEMORY: usize = 0xB8000;
const CRTC_INDEX: u16 = 0x3D4;
const CRTC_DATA: u16 = 0x3D5;

pub const Color = enum(u8) {
    black = 0,
    blue = 1,
    green = 2,
    cyan = 3,
    red = 4,
    magenta = 5,
    brown = 6,
    light_grey = 7,
    dark_grey = 8,
    light_blue = 9,
    light_green = 10,
    light_cyan = 11,
    light_red = 12,
    light_magenta = 13,
    yellow = 14,
    white = 15,
};

pub fn attr(fg: Color, bg: Color) u8 {
    return @intFromEnum(fg) | (@as(u8, @intFromEnum(bg)) << 4);
}

/// The framebuffer address is fixed, so this is `const` — it used to be a `var`,
/// which forced a writable relocation into .data for no reason.
const buffer: [*]volatile u16 = @ptrFromInt(VGA_MEMORY);

var cursor_x: usize = 0;
var cursor_y: usize = 0;
var color: u8 = 0x0F; // white on black

pub fn init() void {
    cursor_x = 0;
    cursor_y = 0;
    color = 0x0F;
    clear();
}

pub fn clear() void {
    const blank = cell(' ');
    var i: usize = 0;
    while (i < WIDTH * HEIGHT) : (i += 1) buffer[i] = blank;
    cursor_x = 0;
    cursor_y = 0;
    updateHardwareCursor();
}

pub fn setColor(new_color: u8) void {
    color = new_color;
}

inline fn cell(c: u8) u16 {
    return (@as(u16, color) << 8) | c;
}

pub fn putChar(c: u8) void {
    switch (c) {
        '\n' => {
            cursor_x = 0;
            cursor_y += 1;
        },
        '\r' => cursor_x = 0,
        '\t' => cursor_x = (cursor_x + 8) & ~@as(usize, 7),
        8 => { // backspace
            if (cursor_x > 0) {
                cursor_x -= 1;
            } else if (cursor_y > 0) {
                cursor_y -= 1;
                cursor_x = WIDTH - 1;
            }
            buffer[cursor_y * WIDTH + cursor_x] = cell(' ');
        },
        else => {
            buffer[cursor_y * WIDTH + cursor_x] = cell(c);
            cursor_x += 1;
        },
    }

    if (cursor_x >= WIDTH) {
        cursor_x = 0;
        cursor_y += 1;
    }
    while (cursor_y >= HEIGHT) {
        scroll();
        cursor_y -= 1;
    }
    updateHardwareCursor();
}

pub fn writeString(str: []const u8) void {
    for (str) |c| putChar(c);
}

fn scroll() void {
    var i: usize = 0;
    while (i < (HEIGHT - 1) * WIDTH) : (i += 1) buffer[i] = buffer[i + WIDTH];

    const blank = cell(' ');
    while (i < HEIGHT * WIDTH) : (i += 1) buffer[i] = blank;
}

/// Keep the blinking hardware cursor in step with where we are writing.
fn updateHardwareCursor() void {
    const pos: u16 = @intCast(cursor_y * WIDTH + cursor_x);
    port.outb(CRTC_INDEX, 0x0F);
    port.outb(CRTC_DATA, @truncate(pos));
    port.outb(CRTC_INDEX, 0x0E);
    port.outb(CRTC_DATA, @truncate(pos >> 8));
}
