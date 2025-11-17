const multiboot = @import("boot/multiboot.zig");
const vga = @import("drivers/vga.zig");
const serial = @import("drivers/serial.zig");
const panic_handler = @import("kernel/panic.zig");
const gdt = @import("arch/x86_64/gdt.zig");
const idt = @import("arch/x86_64/idt.zig");
const pmm = @import("memory/pmm.zig");

export fn kmain() noreturn {
    // Initialize VGA text mode
    vga.init();
    vga.clear();
    vga.writeString("Tessera Kernel v0.1.0\n");

    // Initialize serial output for debugging
    serial.init();
    serial.writeString("Kernel initialized\n");

    // Initialize GDT
    vga.writeString("Initializing GDT...\n");
    gdt.init();
    vga.writeString("GDT initialized\n");

    // Initialize IDT
    vga.writeString("Initializing IDT...\n");
    idt.init();
    vga.writeString("IDT initialized\n");

    // Initialize physical memory manager
    vga.writeString("Initializing PMM...\n");
    pmm.init();
    vga.writeString("PMM initialized\n");

    vga.writeString("\nKernel initialization complete!\n");

    // Halt
    while (true) {
        asm volatile ("hlt");
    }
}

pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    panic_handler.panic(msg);
}

const std = @import("std");
