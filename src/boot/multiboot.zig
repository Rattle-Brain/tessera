// Multiboot2 compatibility
const std = @import("std");

// Multiboot2 constants
const MULTIBOOT2_MAGIC: u32 = 0xE85250D6;
const MULTIBOOT2_ARCHITECTURE_I386: u32 = 0;

// Tag types
const MULTIBOOT_TAG_TYPE_END: u16 = 0;

// Tag structure (all tags start with this)
const MultibootTag = extern struct {
    type: u16,
    flags: u16,
    size: u32,
};

// The end tag (type 0, flags 0, size 8)
const MultibootTagEnd = extern struct {
    type: u16 = MULTIBOOT_TAG_TYPE_END,
    flags: u16 = 0,
    size: u32 = 8,
};

// Complete Multiboot2 header with end tag
const MultibootHeader = extern struct {
    magic: u32,
    architecture: u32,
    header_length: u32,
    checksum: u32,
    // Tags follow immediately
    end_tag: MultibootTagEnd,
};

// Calculate the header
const header_length = @sizeOf(MultibootHeader);
const checksum = ~(MULTIBOOT2_MAGIC +% MULTIBOOT2_ARCHITECTURE_I386 +% header_length) +% 1;

export const multiboot_header align(8) linksection(".multiboot") = MultibootHeader{
    .magic = MULTIBOOT2_MAGIC,
    .architecture = MULTIBOOT2_ARCHITECTURE_I386,
    .header_length = header_length,
    .checksum = checksum,
    .end_tag = .{}, // Uses default values from MultibootTagEnd
};
