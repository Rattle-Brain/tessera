// Interrupt Descriptor Table for x86_64

const isr = @import("isr.zig");
const pic = @import("pic.zig");

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

// Number of ISR stubs we have defined in isr.S
const ISR_COUNT = 48;

pub fn init() void {
    // First, remap the PIC so IRQs 0-15 map to vectors 32-47
    // This MUST happen before we enable interrupts!
    pic.init();

    // Initialize the first 48 IDT entries with our handlers
    for (0..ISR_COUNT) |i| {
        const handler = isr.getHandler(i);
        setGate(&idt[i], handler, 0x08, 0x8E);
    }

    // Set remaining entries as "not present" (type_attr = 0)
    for (ISR_COUNT..256) |i| {
        setGate(&idt[i], 0, 0x08, 0x00);
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
    const ptr_addr = @intFromPtr(&idt_ptr);
    asm volatile ("lidtq (%%rax)"
        :
        : [_] "{rax}" (ptr_addr),
        : .{ .rax = true }
    );
    asm volatile ("sti"); // Enable interrupts
}
