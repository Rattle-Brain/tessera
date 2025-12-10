// Task State Segment for x86_64
// See: https://wiki.osdev.org/Task_State_Segment

pub const Tss = packed struct {
    reserved1: u32 = 0,
    rsp0: u64 = 0, // Stack pointer for privilege level 0
    rsp1: u64 = 0, // Stack pointer for privilege level 1
    rsp2: u64 = 0, // Stack pointer for privilege level 2
    reserved2: u64 = 0,
    ist1: u64 = 0, // Interrupt Stack Table 1
    ist2: u64 = 0, // Interrupt Stack Table 2
    ist3: u64 = 0, // Interrupt Stack Table 3
    ist4: u64 = 0, // Interrupt Stack Table 4
    ist5: u64 = 0, // Interrupt Stack Table 5
    ist6: u64 = 0, // Interrupt Stack Table 6
    ist7: u64 = 0, // Interrupt Stack Table 7
    reserved3: u64 = 0,
    reserved4: u16 = 0,
    iopb: u16 = @sizeOf(Tss), // I/O permission bitmap offset (set to sizeof(TSS) when unused)
};

var tss: Tss align(16) = .{};

pub fn init() void {
    // TSS initialization will be done here
    // RSP0 and IST entries can be set later when we have proper kernel stacks
}

pub fn getTss() *Tss {
    return &tss;
}
