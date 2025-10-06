const pmm = @import("pmm.zig");

// Kernel Heap Allocator
// Simple bump allocator for now

const HEAP_START: usize = 0x100000; // 1MB
const HEAP_SIZE: usize = 0x100000;  // 1MB heap

var heap_current: usize = HEAP_START;
var heap_end: usize = HEAP_START + HEAP_SIZE;

pub fn init() void {
    heap_current = HEAP_START;
}

pub fn alloc(size: usize) ?[*]u8 {
    const aligned_size = (size + 15) & ~@as(usize, 15); // 16-byte alignment
    
    if (heap_current + aligned_size > heap_end) {
        return null;
    }

    const ptr: [*]u8 = @ptrFromInt(heap_current);
    heap_current += aligned_size;
    return ptr;
}

pub fn free(ptr: [*]u8) void {
    _ = ptr;
    // TODO: Implement proper free (for now, bump allocator doesn't free)
}

pub fn getUsed() usize {
    return heap_current - HEAP_START;
}

pub fn getFree() usize {
    return heap_end - heap_current;
}
