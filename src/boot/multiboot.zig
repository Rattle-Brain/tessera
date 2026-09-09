//! Multiboot handoff parsing.
//!
//! The headers themselves live in `boot/boot.S` (they have to be emitted by the
//! assembler so they land in an `SHF_ALLOC` section inside the first 32 KiB of
//! the image). This module only interprets the *info structure* the bootloader
//! passes in, and normalises Multiboot 1 and Multiboot 2 behind one interface so
//! the rest of the kernel does not care which one booted it.

/// Value the bootloader leaves in EAX. Also our tag for which layout `info_addr`
/// points at.
pub const BootProtocol = enum {
    multiboot1,
    multiboot2,
    unknown,

    pub fn fromMagic(magic: u32) BootProtocol {
        return switch (magic) {
            0x2BADB002 => .multiboot1,
            0x36D76289 => .multiboot2,
            else => .unknown,
        };
    }

    pub fn name(self: BootProtocol) []const u8 {
        return switch (self) {
            .multiboot1 => "Multiboot 1",
            .multiboot2 => "Multiboot 2",
            .unknown => "unknown",
        };
    }
};

/// A normalised memory map entry. Addresses are physical.
pub const MemoryRegion = struct {
    base: u64,
    len: u64,
    kind: Kind,

    pub const Kind = enum { usable, reserved, acpi_reclaimable, acpi_nvs, bad };

    pub fn end(self: MemoryRegion) u64 {
        return self.base + self.len;
    }
};

fn kindFromType(t: u32) MemoryRegion.Kind {
    // Both Multiboot revisions use the same E820-derived numbering.
    return switch (t) {
        1 => .usable,
        3 => .acpi_reclaimable,
        4 => .acpi_nvs,
        5 => .bad,
        else => .reserved,
    };
}

// ---------------------------------------------------------------------------
// Multiboot 2
// ---------------------------------------------------------------------------

/// Multiboot 2 *info* tags are `u32 type, u32 size` — not the `u16 type,
/// u16 flags, u32 size` layout used by *header* tags. Mixing the two up
/// silently walks the tag list off into nowhere.
const Mb2Tag = extern struct {
    type: u32,
    size: u32,
};

const MB2_TAG_END: u32 = 0;
const MB2_TAG_BASIC_MEMINFO: u32 = 4;
const MB2_TAG_MMAP: u32 = 6;

const Mb2MmapTag = extern struct {
    type: u32,
    size: u32,
    entry_size: u32,
    entry_version: u32,
    // entries follow
};

const Mb2MmapEntry = extern struct {
    base: u64,
    len: u64,
    type: u32,
    reserved: u32,
};

// ---------------------------------------------------------------------------
// Multiboot 1
// ---------------------------------------------------------------------------

const MB1_FLAG_MEMINFO: u32 = 1 << 0;
const MB1_FLAG_MMAP: u32 = 1 << 6;

const Mb1Info = extern struct {
    flags: u32,
    mem_lower: u32,
    mem_upper: u32,
    boot_device: u32,
    cmdline: u32,
    mods_count: u32,
    mods_addr: u32,
    syms: [4]u32,
    mmap_length: u32,
    mmap_addr: u32,
};

/// Multiboot 1 map entries are prefixed by their own size and the 64-bit fields
/// are only 4-byte aligned, hence the `align(1)` reads.
const Mb1MmapEntry = extern struct {
    size: u32,
    base: u64 align(4),
    len: u64 align(4),
    type: u32,
};

// ---------------------------------------------------------------------------
// Public interface
// ---------------------------------------------------------------------------

pub const BootInfo = struct {
    protocol: BootProtocol,
    info_addr: usize,
    /// Set from the "basic meminfo" tag when a real memory map is unavailable.
    mem_upper_kb: u32 = 0,

    pub fn memoryMap(self: BootInfo) MemoryMapIterator {
        return switch (self.protocol) {
            .multiboot2 => .{ .mb2 = Mb2MmapIterator.init(self.info_addr) },
            .multiboot1 => .{ .mb1 = Mb1MmapIterator.init(self.info_addr) },
            .unknown => .{ .none = {} },
        };
    }
};

pub fn parse(magic: u32, info_addr: usize) BootInfo {
    var info: BootInfo = .{
        .protocol = BootProtocol.fromMagic(magic),
        .info_addr = info_addr,
    };

    switch (info.protocol) {
        .multiboot2 => {
            var it = Mb2TagIterator.init(info_addr);
            while (it.next()) |tag| {
                if (tag.type == MB2_TAG_BASIC_MEMINFO) {
                    const mem: *align(1) const extern struct {
                        type: u32,
                        size: u32,
                        mem_lower: u32,
                        mem_upper: u32,
                    } = @ptrCast(tag);
                    info.mem_upper_kb = mem.mem_upper;
                }
            }
        },
        .multiboot1 => {
            const mb1: *align(1) const Mb1Info = @ptrFromInt(info_addr);
            if (mb1.flags & MB1_FLAG_MEMINFO != 0) info.mem_upper_kb = mb1.mem_upper;
        },
        .unknown => {},
    }

    return info;
}

const Mb2TagIterator = struct {
    cursor: usize,
    end: usize,

    fn init(info_addr: usize) Mb2TagIterator {
        const total_size: *align(1) const u32 = @ptrFromInt(info_addr);
        return .{
            // The first 8 bytes are total_size + reserved.
            .cursor = info_addr + 8,
            .end = info_addr + total_size.*,
        };
    }

    fn next(self: *Mb2TagIterator) ?*align(1) const Mb2Tag {
        if (self.cursor + @sizeOf(Mb2Tag) > self.end) return null;
        const tag: *align(1) const Mb2Tag = @ptrFromInt(self.cursor);
        if (tag.type == MB2_TAG_END or tag.size < @sizeOf(Mb2Tag)) return null;
        // Tags are padded to an 8-byte boundary.
        self.cursor += (tag.size + 7) & ~@as(usize, 7);
        return tag;
    }
};

const Mb2MmapIterator = struct {
    cursor: usize = 0,
    end: usize = 0,
    entry_size: u32 = 0,

    fn init(info_addr: usize) Mb2MmapIterator {
        var tags = Mb2TagIterator.init(info_addr);
        while (tags.next()) |tag| {
            if (tag.type != MB2_TAG_MMAP) continue;
            const mmap: *align(1) const Mb2MmapTag = @ptrCast(tag);
            if (mmap.entry_size < @sizeOf(Mb2MmapEntry)) return .{};
            const base = @intFromPtr(tag) + @sizeOf(Mb2MmapTag);
            return .{
                .cursor = base,
                .end = @intFromPtr(tag) + tag.size,
                .entry_size = mmap.entry_size,
            };
        }
        return .{};
    }

    fn next(self: *Mb2MmapIterator) ?MemoryRegion {
        if (self.entry_size == 0 or self.cursor + self.entry_size > self.end) return null;
        const e: *align(1) const Mb2MmapEntry = @ptrFromInt(self.cursor);
        self.cursor += self.entry_size;
        return .{ .base = e.base, .len = e.len, .kind = kindFromType(e.type) };
    }
};

const Mb1MmapIterator = struct {
    cursor: usize = 0,
    end: usize = 0,

    fn init(info_addr: usize) Mb1MmapIterator {
        const mb1: *align(1) const Mb1Info = @ptrFromInt(info_addr);
        if (mb1.flags & MB1_FLAG_MMAP == 0) return .{};
        return .{ .cursor = mb1.mmap_addr, .end = mb1.mmap_addr + mb1.mmap_length };
    }

    fn next(self: *Mb1MmapIterator) ?MemoryRegion {
        if (self.cursor + @sizeOf(Mb1MmapEntry) > self.end) return null;
        const e: *align(1) const Mb1MmapEntry = @ptrFromInt(self.cursor);
        // `size` covers the entry excluding the size field itself.
        const stride = e.size + @sizeOf(u32);
        if (stride < @sizeOf(Mb1MmapEntry)) return null;
        self.cursor += stride;
        return .{ .base = e.base, .len = e.len, .kind = kindFromType(e.type) };
    }
};

pub const MemoryMapIterator = union(enum) {
    mb1: Mb1MmapIterator,
    mb2: Mb2MmapIterator,
    none: void,

    pub fn next(self: *MemoryMapIterator) ?MemoryRegion {
        return switch (self.*) {
            .mb1 => |*it| it.next(),
            .mb2 => |*it| it.next(),
            .none => null,
        };
    }
};
