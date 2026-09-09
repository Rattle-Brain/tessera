# Fixes and issues with the code

Status of the issues that were tracked here. The kernel now boots to its idle
loop under both Multiboot 1 (`zig build run`) and Multiboot 2 (GRUB).

## Why it did not boot

Three independent showstoppers, in the order they bit:

1. **The Multiboot header was never in the loaded image.** `boot.S` declared
   `.section .multiboot2` with no flags. GAS gives a custom-named section no
   flags at all, so it was not `SHF_ALLOC`, the linker kept it out of every
   `PT_LOAD` segment, and `multiboot_header` resolved to address `0`. Any
   bootloader scanning the image found nothing and refused to boot.
   Fixed by `.section .multiboot, "a", @progbits` + `KEEP()` in the linker
   script.

2. **The kernel was linked outside the region it mapped.** `boot.S` identity
   mapped exactly one 2 MiB page, but the image was landing at 16 MiB. The
   instruction right after `CR0.PG` was set had no mapping, so the CPU took a
   page fault with no IDT installed and triple faulted into a reboot loop.
   Fixed by mapping the low 4 GiB with 2 MiB pages and pinning `KERNEL_BASE` to
   `0x100000`.

3. **`kmain` was called with a misaligned stack and no arguments.**
   `long_mode_start` did `push %rsi; call kmain`, which left `RSP` 8 bytes off
   the ABI-required 16-byte alignment at the call site, and passed the Multiboot
   pointer on the stack when the ABI puts it in `RDI`. Fixed: arguments in
   `RDI`/`RSI`, nothing pushed.

The kernel also did not compile at all on Zig 0.16 (`addAssemblyFile` moved from
`Compile` to `Module`).

## Code correctness issues

1. Boot code - architecture mismatch (`boot/boot.S`) -- **FIXED**
   Also added: `.bss` zeroing, a `CPUID` long mode check, and a 32-bit failure
   path that prints to VGA + COM1 instead of hanging silently.

2. Linker script issues (`linker.ld`) -- **FIXED**
   Higher-half addressing removed (it was never mapped; `PML4[511]` pointed at a
   PDPT whose entry 510 was empty). Section wildcards now match the `.text.*` /
   `.rodata.*` families Zig actually emits — `*(.text)` alone matched nothing, so
   all real code was placed as an orphan section. `.eh_frame` is discarded and
   `kernel_end` / `__bss_start` / `__bss_end` are exported.

3. GDT issues (`arch/x86_64/gdt.zig`) -- **FIXED**
   The far-return trick used `retq` (a *near* return), so it never reloaded CS
   and leaked 8 bytes of stack per call; now `lretq`. Struct sizes are asserted
   at comptime. The TSS limit is derived from `@bitSizeOf`, not `@sizeOf`, which
   rounds a packed struct up to its backing integer's alignment.

4. IDT issues (`arch/x86_64/idt.zig`) -- **FIXED**
   Per-vector stubs, error codes and vector numbers were already in place; what
   was wrong is that `init` ended with `sti`, enabling interrupts from inside IDT
   setup before the rest of the kernel was up. Interrupt enabling is now the
   caller's decision (`idt.enableInterrupts`).

5. ISR issues (`arch/x86_64/isr.zig`) -- **FIXED**
   No `sti` before `iretq`. Slave PIC EOI handled. The important fix: the
   handler used to print a message and return, and returning from a fault
   re-executes the faulting instruction forever — unrecoverable exceptions now
   dump registers (and CR2 plus a decoded error code for `#PF`) and panic.
   `#DF` runs on a dedicated IST1 stack so a blown kernel stack is reported
   rather than triple faulting.

6. Port I/O constraints (`arch/x86_64/port.zig`) -- **NOT A BUG**
   The constraints were already `"{dx}"` / `"{al}"` and compile fine on 0.16.

7. Memory management -- **FIXED**
   - PMM: parses the real Multiboot memory map (both revisions). It used to
     assume a flat 128 MiB and mark everything above 1 MiB as free — which is
     where the kernel image lives, so the first allocation handed out kernel
     code. It also had an unconditional `bit: u3` counter incremented to 8,
     which is an overflow panic in Debug and an infinite loop otherwise; the
     scan now uses `@ctz`. Bitmap sizing was inconsistent with its own comment
     (32 KiB of bitmap for a claimed 128 MiB).
   - VMM: implemented. `mapPage` / `unmapPage` / `getPhysicalAddress` walk the
     four levels, allocating tables from the PMM, and refuse to edit a range
     covered by a huge page instead of silently unmapping live memory.
   - Heap: was bump-allocating out of `[1 MiB, 2 MiB)`, i.e. straight over the
     kernel. Now takes frames from the PMM.

8. Missing Multiboot info (`boot/multiboot.zig`) -- **FIXED**
   The duplicate header this file exported (in a `.multiboot` section the linker
   script did not reference) is gone; `boot.S` owns the headers. The file now
   parses the info structure. Note the header's architecture field being `0` was
   *correct*: it describes the state the loader must hand over in (32-bit
   protected mode), not the width of the kernel.

## Also fixed along the way

- **Zig 0.16 build**: `addAssemblyFile` moved to `Module`. Set `red_zone = false`
  (an interrupt pushes its frame over the red zone and corrupts the interrupted
  leaf function), `pic = false`, `unwind_tables = .none`, `sanitize_c = .off`,
  and `use_llvm = true` (the self-hosted x86_64 backend cannot yet codegen this
  target — it fails on `f128` conversions and emits `movups xmm0` with SSE off).
- **SSE**: MMX/SSE/AVX are subtracted from the target. GRUB hands over with
  `CR4.OSFXSR` clear, so an `xmm` instruction would `#UD` before anything could
  be printed; and `isr_common_stub` only saves general purpose registers, so
  kernel `xmm` usage would be silently clobbered by any interrupt.
- **Panic handler**: the old `pub fn panic(msg, ?*StackTrace, ?usize)` form still
  compiles through a deprecation shim, but that shim routes safety panics through
  `std.debug.panicExtra`, pulling std's formatting and Io stack into the image.
  Replaced with a hand-written panic namespace; combined with re-enabling
  `--gc-sections` (safe now that the headers are `KEEP()`-ed, which also dropped
  all of `compiler_rt`'s soft-float trig), `.text` went from 358 KiB to 6.7 KiB
  in ReleaseSmall.
- **PIC**: `init` no longer unmasks the timer and keyboard behind the caller's
  back; `unmaskIRQ` opens the cascade line when a slave IRQ is unmasked (without
  it, IRQ 8-15 never arrive).
- **VGA**: hardware cursor is kept in sync; the framebuffer pointer is `const`.
- **Build/run workflow**: `zig build run` boots the kernel in QEMU with no
  bootloader installed. QEMU's `-kernel` implements Multiboot 1 and requires an
  ELFCLASS32 file, so `boot.S` carries a Multiboot 1 header too and
  `tools/mb1image.zig` repacks the ELF64 into a 32-bit container.
- Removed the `sleep 0.1` race workaround in the ISO step (the staging tree is a
  proper `WriteFile` step now), the stale 3.2 MiB `iso/boot/tessera.elf` that was
  committed to git, and the dead `limine.cfg`.

## Still missing

### Essential

1. Guard page below the kernel stack — a stack overflow currently walks down
   through `.bss` (including the boot page tables) without faulting.
2. Physical memory above 4 GiB.
3. Higher-half kernel layout.
4. A real allocator (free lists / slab) — the heap cannot free.
5. Splitting huge pages in the VMM.
6. Saving `xmm` state in `isr_common_stub`, if SSE is ever enabled.

### Nice to have

1. Timer (PIT/APIC) for scheduling
2. Keyboard driver
3. Basic syscalls
4. ACPI / framebuffer tags from Multiboot 2
5. Stack traces in the panic handler
6. Integration tests that boot in QEMU and assert on serial output
7. Structured logging with levels
