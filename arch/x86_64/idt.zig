// Interrupt Descriptor Table for x86_64

const isr = @import("isr.zig");

const IdtEntry = packed struct {
    offset_low: u16,
    selector: u16,
    ist: u8,
    type_attr: u8,
    offset_mid: u16,
    offset_high: u32,
    reserved: u32,
};

const IdtPointer = packed struct {
    limit: u16,
    base: u64,
};

var idt: [256]IdtEntry align(16) = undefined;
var idt_ptr: IdtPointer = undefined;

pub fn init() void {
    // Initialize all IDT entries
    for (&idt, 0..) |*entry, i| {
        const handler = isr.getHandler(i);
        setGate(entry, handler, 0x08, 0x8E);
    }

    idt_ptr.limit = @sizeOf(@TypeOf(idt)) - 1;
    idt_ptr.base = @intFromPtr(&idt);

    load();
}

fn setGate(entry: *IdtEntry, handler: u64, selector: u16, type_attr: u8) void {
    entry.offset_low = @truncate(handler & 0xFFFF);
    entry.selector = selector;
    entry.ist = 0;
    entry.type_attr = type_attr;
    entry.offset_mid = @truncate((handler >> 16) & 0xFFFF);
    entry.offset_high = @truncate((handler >> 32) & 0xFFFFFFFF);
    entry.reserved = 0;
}

fn load() void {
    asm volatile ("lidt (%[idt_ptr])"
        :
        : [idt_ptr] "r" (&idt_ptr),
    );
    asm volatile ("sti"); // Enable interrupts
}
