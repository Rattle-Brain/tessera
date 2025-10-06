const vga = @import("../drivers/vga.zig");
const serial = @import("../drivers/serial.zig");

pub fn panic(msg: []const u8) noreturn {
    vga.setColor(0x4F); // Red background, white text
    vga.writeString("\n\n!!! KERNEL PANIC !!!\n");
    vga.writeString(msg);
    vga.writeString("\n\nSystem halted.");

    serial.writeString("\n!!! KERNEL PANIC !!!\n");
    serial.writeString(msg);
    serial.writeString("\nSystem halted.\n");

    // Disable interrupts and halt
    while (true) {
        asm volatile ("cli; hlt");
    }
}
