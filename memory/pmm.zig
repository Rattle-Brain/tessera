const vga = @import("../drivers/vga.zig");

// Physical Memory Manager
// Manages physical memory pages (4KB each)

const PAGE_SIZE: usize = 4096;
const BITMAP_SIZE: usize = 32768; // Support up to 128MB

var bitmap: [BITMAP_SIZE]u8 = undefined;
var total_pages: usize = 0;
var free_pages: usize = 0;
var initialized: bool = false;

pub fn init() void {
    // Initialize all pages as used
    for (&bitmap) |*byte| {
        byte.* = 0xFF;
    }

    // Mark first 1MB as used (BIOS, video memory, kernel)
    const kernel_pages = 256; // 1MB / 4KB
    
    // Assume 128MB of RAM for now
    total_pages = 32768;
    free_pages = total_pages - kernel_pages;

    // Mark pages after 1MB as free
    var i: usize = kernel_pages;
    while (i < total_pages) : (i += 1) {
        markFree(i);
    }

    initialized = true;
}

pub fn allocPage() ?usize {
    if (!initialized) return null;

    var i: usize = 0;
    while (i < BITMAP_SIZE) : (i += 1) {
        if (bitmap[i] != 0xFF) {
            var bit: u3 = 0;
            while (bit < 8) : (bit += 1) {
                if ((bitmap[i] & (@as(u8, 1) << bit)) == 0) {
                    bitmap[i] |= (@as(u8, 1) << bit);
                    free_pages -= 1;
                    return (i * 8 + bit) * PAGE_SIZE;
                }
            }
        }
    }
    return null;
}

pub fn freePage(addr: usize) void {
    if (!initialized) return;
    
    const page = addr / PAGE_SIZE;
    markFree(page);
    free_pages += 1;
}

fn markFree(page: usize) void {
    const byte = page / 8;
    const bit: u3 = @intCast(page % 8);
    bitmap[byte] &= ~(@as(u8, 1) << bit);
}

pub fn getFreePages() usize {
    return free_pages;
}

pub fn getTotalPages() usize {
    return total_pages;
}
