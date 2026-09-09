//! Physical memory manager: a bitmap allocator over 4 KiB frames.
//!
//! Previously this file assumed a flat 128 MiB of RAM and marked everything
//! above 1 MiB as free — which is exactly where the kernel image lives, so the
//! first allocation handed out kernel code. It now drives off the Multiboot
//! memory map and reserves the kernel image explicitly.

const multiboot = @import("../boot/multiboot.zig");
const log = @import("../kernel/log.zig");

pub const PAGE_SIZE: usize = 4096;

/// Highest physical address we track. boot.S identity-maps the low 4 GiB, so
/// anything above that is unreachable without a real VMM.
const MAX_PHYS: u64 = 4 * 1024 * 1024 * 1024;
const MAX_FRAMES: usize = MAX_PHYS / PAGE_SIZE; // 1 Mi frames
const BITMAP_BYTES: usize = MAX_FRAMES / 8; // 128 KiB

/// 1 = in use or nonexistent, 0 = free. `init` fills it with 0xFF so that any
/// frame the memory map never mentions stays untouchable. Left `undefined` so it
/// lands in .bss instead of baking 128 KiB of 0xFF into the kernel image.
var bitmap: [BITMAP_BYTES]u8 align(64) = undefined;

var total_frames: usize = 0;
var free_frames: usize = 0;
var initialized: bool = false;
/// Rotating search hint so allocation does not rescan the low frames every time.
var next_hint: usize = 0;

/// Provided by the linker script: first page-aligned address past the kernel.
extern const kernel_end: anyopaque;

pub const Stats = struct {
    total_frames: usize,
    free_frames: usize,

    pub fn totalBytes(self: Stats) u64 {
        return @as(u64, self.total_frames) * PAGE_SIZE;
    }
    pub fn freeBytes(self: Stats) u64 {
        return @as(u64, self.free_frames) * PAGE_SIZE;
    }
};

pub fn init(boot_info: multiboot.BootInfo) void {
    total_frames = 0;
    free_frames = 0;
    next_hint = 0;
    @memset(&bitmap, 0xFF);

    var it = boot_info.memoryMap();
    var saw_map = false;
    while (it.next()) |region| {
        saw_map = true;
        if (region.kind != .usable) continue;
        release(region.base, region.len);
    }

    if (!saw_map) {
        // No memory map: fall back to the "basic meminfo" upper limit, which
        // counts KiB above the 1 MiB mark.
        const upper = @as(u64, boot_info.mem_upper_kb) * 1024;
        log.line("pmm: no memory map, falling back to basic meminfo");
        release(0x100000, upper);
    }

    // Everything below 1 MiB is BIOS/EBDA/VGA territory. Never hand it out.
    reserve(0, 0x100000);

    // The kernel image itself, from its 1 MiB load address to `kernel_end`.
    const kend = @intFromPtr(&kernel_end);
    reserve(0x100000, kend - 0x100000);

    initialized = true;
}

/// Mark [base, base+len) as allocatable. Only whole frames fully inside the
/// range are released, so a region that starts mid-frame cannot leak the
/// preceding bytes.
fn release(base: u64, len: u64) void {
    if (len == 0) return;
    var frame = (base + PAGE_SIZE - 1) / PAGE_SIZE;
    const last = (base + len) / PAGE_SIZE; // exclusive
    while (frame < last and frame < MAX_FRAMES) : (frame += 1) {
        if (!testFrame(@intCast(frame))) continue; // already free
        clearFrame(@intCast(frame));
        total_frames += 1;
        free_frames += 1;
    }
}

/// Mark [base, base+len) as unavailable, rounding *outwards* so a partially
/// covered frame is never left allocatable.
pub fn reserve(base: u64, len: u64) void {
    if (len == 0) return;
    var frame = base / PAGE_SIZE;
    const last = (base + len + PAGE_SIZE - 1) / PAGE_SIZE; // exclusive
    while (frame < last and frame < MAX_FRAMES) : (frame += 1) {
        if (testFrame(@intCast(frame))) continue; // already reserved
        setFrame(@intCast(frame));
        free_frames -= 1;
    }
}

/// Allocate one frame. Returns its physical address.
pub fn allocPage() ?usize {
    if (!initialized or free_frames == 0) return null;

    // Two passes: from the hint to the end, then from the start to the hint.
    const start_byte = next_hint / 8;
    if (scanFrom(start_byte, BITMAP_BYTES)) |addr| return addr;
    if (scanFrom(0, start_byte)) |addr| return addr;
    return null;
}

fn scanFrom(from_byte: usize, to_byte: usize) ?usize {
    var byte = from_byte;
    while (byte < to_byte) : (byte += 1) {
        if (bitmap[byte] == 0xFF) continue;
        // @ctz on the complement gives the first zero bit directly, instead of
        // the old bit-by-bit loop (which also overflowed its u3 counter).
        const bit: u3 = @intCast(@ctz(~bitmap[byte]));
        bitmap[byte] |= @as(u8, 1) << bit;
        free_frames -= 1;
        const frame = byte * 8 + bit;
        next_hint = frame + 1;
        return frame * PAGE_SIZE;
    }
    return null;
}

/// Allocate `count` physically contiguous frames.
pub fn allocPages(count: usize) ?usize {
    if (!initialized or count == 0) return null;
    if (count == 1) return allocPage();

    var frame: usize = 0;
    while (frame + count <= MAX_FRAMES) {
        var i: usize = 0;
        while (i < count and !testFrame(frame + i)) : (i += 1) {}
        if (i == count) {
            var j: usize = 0;
            while (j < count) : (j += 1) setFrame(frame + j);
            free_frames -= count;
            return frame * PAGE_SIZE;
        }
        // `frame + i` is taken, so no run can start at or before it.
        frame += i + 1;
    }
    return null;
}

pub fn freePage(addr: usize) void {
    freePages(addr, 1);
}

pub fn freePages(addr: usize, count: usize) void {
    if (!initialized) return;
    const first = addr / PAGE_SIZE;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const frame = first + i;
        if (frame >= MAX_FRAMES or !testFrame(frame)) continue;
        clearFrame(frame);
        free_frames += 1;
    }
}

inline fn testFrame(frame: usize) bool {
    return bitmap[frame / 8] & (@as(u8, 1) << @intCast(frame % 8)) != 0;
}

inline fn setFrame(frame: usize) void {
    bitmap[frame / 8] |= @as(u8, 1) << @intCast(frame % 8);
}

inline fn clearFrame(frame: usize) void {
    bitmap[frame / 8] &= ~(@as(u8, 1) << @intCast(frame % 8));
}

pub fn stats() Stats {
    return .{ .total_frames = total_frames, .free_frames = free_frames };
}

/// Print the memory map as the bootloader reported it. Useful early diagnostic.
pub fn dumpMemoryMap(boot_info: multiboot.BootInfo) void {
    var it = boot_info.memoryMap();
    while (it.next()) |region| {
        log.str("  ");
        log.hexWidth(region.base, 12);
        log.str(" - ");
        log.hexWidth(region.end(), 12);
        log.str("  ");
        log.str(switch (region.kind) {
            .usable => "usable",
            .reserved => "reserved",
            .acpi_reclaimable => "ACPI reclaimable",
            .acpi_nvs => "ACPI NVS",
            .bad => "bad",
        });
        log.nl();
    }
}
