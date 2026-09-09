//! Kernel panic handling.
//!
//! `namespace` below is what `main.zig` exports as the root `panic` decl. Since
//! Zig 0.14 the root `panic` must be a *namespace* of handler functions rather
//! than a single function; the old single-function form still compiles through a
//! deprecation shim, but that shim routes safety panics through
//! `std.debug.panicExtra`, which drags std's formatting and Io machinery into a
//! freestanding build. Providing the namespace by hand keeps the kernel small
//! and every safety check lowering to `call` below.
//!
//! Modelled on `std.debug.simple_panic`.

const log = @import("log.zig");
const vga = @import("../drivers/vga.zig");

/// Explicit `@panic` calls and every safety check land here.
pub fn call(msg: []const u8, ra: ?usize) noreturn {
    @branchHint(.cold);

    // Interrupts off first: a panic must not be re-entered by an IRQ.
    asm volatile ("cli");

    vga.setColor(0x4F); // white on red
    log.nl();
    log.line("*** KERNEL PANIC ***");
    log.str("  ");
    log.line(msg);
    if (ra) |addr| {
        log.str("  at ");
        log.hex(addr);
        log.nl();
    }
    log.line("System halted.");

    halt();
}

pub fn halt() noreturn {
    while (true) asm volatile ("cli; hlt");
}

pub fn sentinelMismatch(expected: anytype, found: @TypeOf(expected)) noreturn {
    _ = found;
    call("sentinel mismatch", @returnAddress());
}

pub fn unwrapError(err: anyerror) noreturn {
    _ = &err;
    call("attempt to unwrap error", @returnAddress());
}

pub fn outOfBounds(index: usize, len: usize) noreturn {
    _ = index;
    _ = len;
    call("index out of bounds", @returnAddress());
}

pub fn startGreaterThanEnd(start: usize, end: usize) noreturn {
    _ = start;
    _ = end;
    call("start index is larger than end index", @returnAddress());
}

pub fn inactiveUnionField(active: anytype, accessed: @TypeOf(active)) noreturn {
    _ = accessed;
    call("access of inactive union field", @returnAddress());
}

pub fn sliceCastLenRemainder(src_len: usize) noreturn {
    _ = src_len;
    call("slice length does not divide exactly into destination elements", @returnAddress());
}

pub fn reachedUnreachable() noreturn {
    call("reached unreachable code", @returnAddress());
}

pub fn unwrapNull() noreturn {
    call("attempt to use null value", @returnAddress());
}

pub fn castToNull() noreturn {
    call("cast causes pointer to be null", @returnAddress());
}

pub fn incorrectAlignment() noreturn {
    call("incorrect alignment", @returnAddress());
}

pub fn invalidErrorCode() noreturn {
    call("invalid error code", @returnAddress());
}

pub fn integerOutOfBounds() noreturn {
    call("integer does not fit in destination type", @returnAddress());
}

pub fn integerOverflow() noreturn {
    call("integer overflow", @returnAddress());
}

pub fn shlOverflow() noreturn {
    call("left shift overflowed bits", @returnAddress());
}

pub fn shrOverflow() noreturn {
    call("right shift overflowed bits", @returnAddress());
}

pub fn divideByZero() noreturn {
    call("division by zero", @returnAddress());
}

pub fn exactDivisionRemainder() noreturn {
    call("exact division produced remainder", @returnAddress());
}

pub fn integerPartOutOfBounds() noreturn {
    call("integer part of floating point value out of bounds", @returnAddress());
}

pub fn corruptSwitch() noreturn {
    call("switch on corrupt value", @returnAddress());
}

pub fn shiftRhsTooBig() noreturn {
    call("shift amount is greater than the type size", @returnAddress());
}

pub fn invalidEnumValue() noreturn {
    call("invalid enum value", @returnAddress());
}

pub fn forLenMismatch() noreturn {
    call("for loop over objects with non-equal lengths", @returnAddress());
}

pub fn copyLenMismatch() noreturn {
    call("source and destination have non-equal lengths", @returnAddress());
}

pub fn memcpyAlias() noreturn {
    call("@memcpy arguments alias", @returnAddress());
}

pub fn noreturnReturned() noreturn {
    call("'noreturn' function returned", @returnAddress());
}
