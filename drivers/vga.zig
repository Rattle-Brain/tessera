// VGA Text Mode Driver

const VGA_WIDTH: usize = 80;
const VGA_HEIGHT: usize = 25;
const VGA_MEMORY: usize = 0xB8000;

var vga_buffer: [*]volatile u16 = @ptrFromInt(VGA_MEMORY);
var cursor_x: usize = 0;
var cursor_y: usize = 0;
var color: u8 = 0x0F; // White on black

pub fn init() void {
    cursor_x = 0;
    cursor_y = 0;
    color = 0x0F;
}

pub fn clear() void {
    const blank: u16 = @as(u16, color) << 8 | ' ';
    var i: usize = 0;
    while (i < VGA_WIDTH * VGA_HEIGHT) : (i += 1) {
        vga_buffer[i] = blank;
    }
    cursor_x = 0;
    cursor_y = 0;
}

pub fn setColor(new_color: u8) void {
    color = new_color;
}

pub fn putChar(c: u8) void {
    if (c == '\n') {
        cursor_x = 0;
        cursor_y += 1;
    } else if (c == '\r') {
        cursor_x = 0;
    } else if (c == '\t') {
        cursor_x = (cursor_x + 8) & ~@as(usize, 7);
    } else {
        const index = cursor_y * VGA_WIDTH + cursor_x;
        vga_buffer[index] = @as(u16, color) << 8 | c;
        cursor_x += 1;
    }

    if (cursor_x >= VGA_WIDTH) {
        cursor_x = 0;
        cursor_y += 1;
    }

    if (cursor_y >= VGA_HEIGHT) {
        scroll();
        cursor_y = VGA_HEIGHT - 1;
    }
}

pub fn writeString(str: []const u8) void {
    for (str) |c| {
        putChar(c);
    }
}

fn scroll() void {
    const blank: u16 = @as(u16, color) << 8 | ' ';
    
    // Move all rows up by one
    var i: usize = 0;
    while (i < (VGA_HEIGHT - 1) * VGA_WIDTH) : (i += 1) {
        vga_buffer[i] = vga_buffer[i + VGA_WIDTH];
    }

    // Clear the last row
    i = (VGA_HEIGHT - 1) * VGA_WIDTH;
    while (i < VGA_HEIGHT * VGA_WIDTH) : (i += 1) {
        vga_buffer[i] = blank;
    }
}
