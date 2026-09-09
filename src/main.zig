//! Tessera kernel entry point.

const multiboot = @import("boot/multiboot.zig");
const vga = @import("drivers/vga.zig");
const serial = @import("drivers/serial.zig");
const log = @import("kernel/log.zig");
const panic_handler = @import("kernel/panic.zig");
const gdt = @import("arch/x86_64/gdt.zig");
const idt = @import("arch/x86_64/idt.zig");
const isr = @import("arch/x86_64/isr.zig");
const tss = @import("arch/x86_64/tss.zig");
const pic = @import("arch/x86_64/pic.zig");
const pmm = @import("memory/pmm.zig");
const heap = @import("memory/heap.zig");
const vmm = @import("memory/vmm.zig");

/// The root `panic` declaration must be a *namespace* of handler functions.
/// See kernel/panic.zig for why we don't use `std.debug.FullPanic`.
pub const panic = panic_handler;

const VERSION = "0.1.0";

/// Dedicated stack for the double fault handler, reached via TSS IST1.
var df_stack: [16 * 1024]u8 align(16) = undefined;

/// Called from boot.S with the values the bootloader left in EAX/EBX.
export fn kmain(magic: u32, mb_info_addr: usize) callconv(.c) noreturn {
    // Consoles first, so everything after this point is debuggable.
    serial.init();
    vga.init();
    vga.setColor(vga.attr(.light_cyan, .black));
    log.line("Tessera " ++ VERSION);
    vga.setColor(vga.attr(.light_grey, .black));

    const boot_info = multiboot.parse(magic, mb_info_addr);
    log.str("boot: ");
    log.str(boot_info.protocol.name());
    log.str(", info at ");
    log.hexWidth(mb_info_addr, 8);
    log.nl();

    if (boot_info.protocol == .unknown) {
        // boot.S already rejects a bad magic, so reaching here means the value
        // was mangled between there and now.
        @panic("unrecognised Multiboot magic");
    }

    log.line("cpu: installing GDT/TSS");
    tss.init();
    gdt.init();

    log.line("cpu: installing IDT and remapping PIC");
    idt.init();

    // A double fault usually means the kernel stack is gone, so handling it on
    // that same stack just escalates to a triple fault (silent reboot). IST1
    // gives #DF a stack of its own so we get a diagnostic instead.
    tss.setInterruptStack(1, @intFromPtr(&df_stack) + df_stack.len);
    idt.setIst(8, 1);

    log.line("mem: physical memory map");
    pmm.dumpMemoryMap(boot_info);
    pmm.init(boot_info);

    const s = pmm.stats();
    log.str("mem: ");
    log.bytes(s.totalBytes());
    log.str(" usable, ");
    log.bytes(s.freeBytes());
    log.line(" free");

    heap.init();
    vmm.init();

    selfTest();

    // Only now is it safe to take interrupts. Just the PIT for the moment: the
    // i8042 keeps IRQ1 asserted until its output buffer is read, so unmasking
    // the keyboard before there is a driver to drain port 0x60 would wedge it.
    pic.unmaskIRQ(0); // PIT
    idt.enableInterrupts();

    vga.setColor(vga.attr(.light_green, .black));
    log.line("boot: initialisation complete");
    vga.setColor(vga.attr(.light_grey, .black));

    idle();
}

/// A few cheap assertions that the memory subsystems actually work. Any failure
/// here means something below us is wrong, and it is much easier to find now
/// than after the first real allocation.
fn selfTest() void {
    const a = pmm.allocPage() orelse @panic("pmm: no free frames");
    const b = pmm.allocPage() orelse @panic("pmm: no second frame");
    if (a == b) @panic("pmm: handed out the same frame twice");
    if (a < 0x100000 or b < 0x100000) @panic("pmm: handed out reserved low memory");
    pmm.freePage(a);
    pmm.freePage(b);

    const buf = heap.alloc(64) catch @panic("heap: allocation failed");
    buf[0] = 0x5A;
    buf[63] = 0xA5;
    if (buf[0] != 0x5A or buf[63] != 0xA5) @panic("heap: memory is not writable");

    // Map a frame just past the 4 GiB window boot.S identity-maps, which
    // exercises the page table walker end to end (it has to allocate a fresh
    // PDPT entry, PD and PT along the way).
    const probe_virt: usize = 0x1_0000_0000;
    if (vmm.isMapped(probe_virt)) @panic("vmm: probe address unexpectedly mapped");
    const frame = pmm.allocPage() orelse @panic("vmm: no frame for probe");
    vmm.mapPage(probe_virt, frame, vmm.kernel_flags) catch @panic("vmm: mapPage failed");
    if (vmm.getPhysicalAddress(probe_virt) != frame) @panic("vmm: translation mismatch");
    const probe: *volatile u64 = @ptrFromInt(probe_virt);
    probe.* = 0xCAFEF00D_DEADBEEF;
    if (probe.* != 0xCAFEF00D_DEADBEEF) @panic("vmm: mapped page is not writable");
    vmm.unmapPage(probe_virt) catch @panic("vmm: unmapPage failed");
    if (vmm.isMapped(probe_virt)) @panic("vmm: page still mapped after unmap");
    pmm.freePage(frame);

    log.line("self-test: pmm, heap and vmm OK");
}

fn idle() noreturn {
    while (true) asm volatile ("hlt");
}
