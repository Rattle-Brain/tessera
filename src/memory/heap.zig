//! Kernel heap: a bump allocator over frames obtained from the PMM.
//!
//! The old version bump-allocated straight out of a fixed [1 MiB, 2 MiB) window
//! — which is the kernel's own load address, so the first allocation overwrote
//! kernel code. Frames now come from the physical allocator, which knows what is
//! actually free.

const pmm = @import("pmm.zig");

/// Frames grabbed per refill. 64 KiB keeps PMM traffic low without reserving
/// much up front.
const CHUNK_FRAMES: usize = 16;

var cursor: usize = 0;
var limit: usize = 0;
var used: usize = 0;
var reserved: usize = 0;
var initialized: bool = false;

pub const Error = error{OutOfMemory};

pub fn init() void {
    cursor = 0;
    limit = 0;
    used = 0;
    reserved = 0;
    initialized = true;
}

/// Allocate `size` bytes with at least `alignment` (a power of two) alignment.
pub fn allocAligned(size: usize, alignment: usize) Error![*]u8 {
    if (!initialized) return error.OutOfMemory;
    if (size == 0) return error.OutOfMemory;

    const aligned = alignUp(cursor, alignment);
    if (aligned + size > limit) {
        try refill(alignUp(size, alignment) + alignment);
        return allocAligned(size, alignment);
    }

    cursor = aligned + size;
    used += size;
    return @ptrFromInt(aligned);
}

pub fn alloc(size: usize) Error![*]u8 {
    return allocAligned(size, 16);
}

/// Typed convenience wrapper.
pub fn create(comptime T: type) Error!*T {
    const raw = try allocAligned(@sizeOf(T), @alignOf(T));
    return @ptrCast(@alignCast(raw));
}

pub fn allocSlice(comptime T: type, n: usize) Error![]T {
    const raw = try allocAligned(@sizeOf(T) * n, @alignOf(T));
    const ptr: [*]T = @ptrCast(@alignCast(raw));
    return ptr[0..n];
}

/// A bump allocator cannot reclaim individual objects. Kept so callers have an
/// explicit place to point at once a real allocator lands.
pub fn free(ptr: [*]u8) void {
    _ = ptr;
}

fn refill(min_bytes: usize) Error!void {
    var frames = (min_bytes + pmm.PAGE_SIZE - 1) / pmm.PAGE_SIZE;
    if (frames < CHUNK_FRAMES) frames = CHUNK_FRAMES;

    // Try for one contiguous run; if the new run happens to abut the current
    // one, the existing window just grows.
    const base = pmm.allocPages(frames) orelse return error.OutOfMemory;
    if (base != limit) cursor = base;
    limit = base + frames * pmm.PAGE_SIZE;
    reserved += frames * pmm.PAGE_SIZE;
}

fn alignUp(value: usize, alignment: usize) usize {
    return (value + alignment - 1) & ~(alignment - 1);
}

pub fn getUsed() usize {
    return used;
}

pub fn getReserved() usize {
    return reserved;
}

pub fn getFree() usize {
    return limit - cursor;
}
