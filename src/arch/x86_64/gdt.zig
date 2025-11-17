// Global Descriptor Table for x86_64

const GdtEntry = packed struct {
    limit_low: u16,
    base_low: u16,
    base_middle: u8,
    access: u8,
    granularity: u8,
    base_high: u8,
};

const GdtPointer = packed struct {
    limit: u16,
    base: u64,
};

var gdt: [5]GdtEntry align(16) = undefined;
var gdt_ptr: GdtPointer = undefined;

pub fn init() void {
    // Null descriptor
    gdt[0] = makeEntry(0, 0, 0, 0);

    // Kernel code segment
    gdt[1] = makeEntry(0, 0xFFFFF, 0x9A, 0xA0);

    // Kernel data segment
    gdt[2] = makeEntry(0, 0xFFFFF, 0x92, 0xC0);

    // User code segment
    gdt[3] = makeEntry(0, 0xFFFFF, 0xFA, 0xA0);

    // User data segment
    gdt[4] = makeEntry(0, 0xFFFFF, 0xF2, 0xC0);

    gdt_ptr.limit = @sizeOf(@TypeOf(gdt)) - 1;
    gdt_ptr.base = @intFromPtr(&gdt);

    load();
}

fn makeEntry(base: u32, limit: u32, access: u8, gran: u8) GdtEntry {
    return GdtEntry{
        .limit_low = @truncate(limit & 0xFFFF),
        .base_low = @truncate(base & 0xFFFF),
        .base_middle = @truncate((base >> 16) & 0xFF),
        .access = access,
        .granularity = @truncate(((limit >> 16) & 0x0F) | (gran & 0xF0)),
        .base_high = @truncate((base >> 24) & 0xFF),
    };
}

fn load() void {
    const ptr_addr = @intFromPtr(&gdt_ptr);
    asm volatile (
        \\lgdtq (%%rbx)
        \\movw $0x10, %%ax
        \\movw %%ax, %%ds
        \\movw %%ax, %%es
        \\movw %%ax, %%fs
        \\movw %%ax, %%gs
        \\movw %%ax, %%ss
        :
        : [_] "{rbx}" (ptr_addr),
        : .{ .rax = true, .rbx = true }
    );
}
