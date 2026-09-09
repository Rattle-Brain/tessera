//! Virtual memory manager: walks and edits the 4-level page tables boot.S set
//! up.
//!
//! The kernel runs identity-mapped over the low 4 GiB, so a physical address can
//! be dereferenced directly and page tables need no separate mapping window.
//! That assumption is what `physToVirt` encodes; it is the one place to change
//! if the kernel ever moves to a higher-half layout.

const pmm = @import("pmm.zig");

pub const PAGE_SIZE: usize = 4096;
pub const HUGE_PAGE_SIZE: usize = 2 * 1024 * 1024;

pub const Flags = packed struct(u64) {
    present: bool = false,
    writable: bool = false,
    user: bool = false,
    write_through: bool = false,
    no_cache: bool = false,
    accessed: bool = false,
    dirty: bool = false,
    /// On a PDPT/PD entry this means "maps a 1 GiB / 2 MiB page directly".
    huge: bool = false,
    global: bool = false,
    _available: u3 = 0,
    address: u40 = 0,
    _available2: u11 = 0,
    /// Honoured because boot.S sets EFER.NXE.
    no_execute: bool = false,

    pub fn physical(self: Flags) u64 {
        return @as(u64, self.address) << 12;
    }
};

comptime {
    if (@bitSizeOf(Flags) != 64) @compileError("page table entry must be 64 bits");
}

pub const kernel_flags = Flags{ .present = true, .writable = true };
pub const user_flags = Flags{ .present = true, .writable = true, .user = true };

pub const Error = error{
    OutOfMemory,
    /// The target is inside a 2 MiB/1 GiB mapping; splitting it is not
    /// implemented, and silently overwriting the entry would unmap live memory.
    CoveredByHugePage,
    NotMapped,
};

const Table = [512]u64;

/// Identity mapping, per boot.S.
inline fn physToVirt(phys: u64) *Table {
    return @ptrFromInt(@as(usize, @intCast(phys)));
}

pub fn init() void {
    // boot.S already installed a valid CR3; nothing to do until we need
    // mappings outside the identity-mapped window.
}

pub fn currentPml4() *Table {
    const cr3 = asm volatile ("movq %%cr3, %[out]"
        : [out] "=r" (-> u64),
    );
    return physToVirt(cr3 & ~@as(u64, 0xFFF));
}

fn indexOf(virt: u64, level: u2) usize {
    // level 3 = PML4, 2 = PDPT, 1 = PD, 0 = PT
    const shift: u6 = 12 + @as(u6, level) * 9;
    return @intCast((virt >> shift) & 0x1FF);
}

/// Fetch the next level down, allocating it if `create` is set.
fn descend(table: *Table, index: usize, create: bool) Error!*Table {
    var entry: Flags = @bitCast(table[index]);

    if (entry.present) {
        if (entry.huge) return error.CoveredByHugePage;
        return physToVirt(entry.physical());
    }
    if (!create) return error.NotMapped;

    const frame = pmm.allocPage() orelse return error.OutOfMemory;
    const next = physToVirt(frame);
    @memset(next, 0);

    entry = .{ .present = true, .writable = true, .address = @intCast(frame >> 12) };
    table[index] = @bitCast(entry);
    return next;
}

/// Map one 4 KiB page. `virt` and `phys` must be page aligned.
pub fn mapPage(virt: usize, phys: usize, flags: Flags) Error!void {
    const pml4 = currentPml4();
    const pdpt = try descend(pml4, indexOf(virt, 3), true);
    const pd = try descend(pdpt, indexOf(virt, 2), true);
    const pt = try descend(pd, indexOf(virt, 1), true);

    var entry = flags;
    entry.present = true;
    entry.address = @intCast(phys >> 12);
    pt[indexOf(virt, 0)] = @bitCast(entry);

    invalidatePage(virt);
}

pub fn unmapPage(virt: usize) Error!void {
    const pml4 = currentPml4();
    const pdpt = try descend(pml4, indexOf(virt, 3), false);
    const pd = try descend(pdpt, indexOf(virt, 2), false);
    const pt = try descend(pd, indexOf(virt, 1), false);

    pt[indexOf(virt, 0)] = 0;
    invalidatePage(virt);
}

/// Translate a virtual address, honouring 1 GiB and 2 MiB mappings.
pub fn getPhysicalAddress(virt: usize) ?usize {
    var table = currentPml4();
    var level: u2 = 3;
    while (true) {
        const entry: Flags = @bitCast(table[indexOf(virt, level)]);
        if (!entry.present) return null;

        // A huge page at this level: the remaining index bits become the offset.
        if (level != 3 and entry.huge) {
            const shift: u6 = 12 + @as(u6, level) * 9;
            const mask = (@as(u64, 1) << shift) - 1;
            return @intCast(entry.physical() | (virt & mask));
        }
        if (level == 0) return @intCast(entry.physical() | (virt & 0xFFF));

        table = physToVirt(entry.physical());
        level -= 1;
    }
}

pub fn isMapped(virt: usize) bool {
    return getPhysicalAddress(virt) != null;
}

inline fn invalidatePage(virt: usize) void {
    asm volatile ("invlpg (%%rax)"
        :
        : [addr] "{rax}" (virt),
        : .{ .rax = true, .memory = true }
    );
}
