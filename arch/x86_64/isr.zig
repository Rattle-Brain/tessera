// Interrupt Service Routines

const vga = @import("../../drivers/vga.zig");
const port = @import("port.zig");

pub fn getHandler(interrupt: usize) u64 {
    return switch (interrupt) {
        0...31 => @intFromPtr(&defaultHandler),
        32...47 => @intFromPtr(&irqHandler),
        else => @intFromPtr(&defaultHandler),
    };
}

export fn defaultHandler() callconv(.Naked) void {
    asm volatile (
        \\cli
        \\push %%rax
        \\push %%rbx
        \\push %%rcx
        \\push %%rdx
        \\push %%rsi
        \\push %%rdi
        \\push %%rbp
        \\push %%r8
        \\push %%r9
        \\push %%r10
        \\push %%r11
        \\push %%r12
        \\push %%r13
        \\push %%r14
        \\push %%r15
        \\call handleInterrupt
        \\pop %%r15
        \\pop %%r14
        \\pop %%r13
        \\pop %%r12
        \\pop %%r11
        \\pop %%r10
        \\pop %%r9
        \\pop %%r8
        \\pop %%rbp
        \\pop %%rdi
        \\pop %%rsi
        \\pop %%rdx
        \\pop %%rcx
        \\pop %%rbx
        \\pop %%rax
        \\sti
        \\iretq
    );
}

export fn irqHandler() callconv(.Naked) void {
    asm volatile (
        \\cli
        \\push %%rax
        \\push %%rbx
        \\push %%rcx
        \\push %%rdx
        \\push %%rsi
        \\push %%rdi
        \\push %%rbp
        \\push %%r8
        \\push %%r9
        \\push %%r10
        \\push %%r11
        \\push %%r12
        \\push %%r13
        \\push %%r14
        \\push %%r15
        \\call handleIrq
        \\pop %%r15
        \\pop %%r14
        \\pop %%r13
        \\pop %%r12
        \\pop %%r11
        \\pop %%r10
        \\pop %%r9
        \\pop %%r8
        \\pop %%rbp
        \\pop %%rdi
        \\pop %%rsi
        \\pop %%rdx
        \\pop %%rcx
        \\pop %%rbx
        \\pop %%rax
        \\sti
        \\iretq
    );
}

export fn handleInterrupt() void {
    // Handle CPU exceptions
    vga.writeString("!");
}

export fn handleIrq() void {
    // Handle hardware interrupts
    // Send EOI to PIC
    port.outb(0x20, 0x20);
}
