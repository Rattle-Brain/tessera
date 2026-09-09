# Tessera Kernel Architecture

## Overview

Tessera is a modular x86_64 kernel written in Zig, booted by a Multiboot-
compliant bootloader (GRUB via Multiboot 2, or QEMU's built-in Multiboot 1
loader for quick testing).

## Boot Process

1. **Bootloader**
   - Finds a Multiboot header in the first 32 KiB of the ELF (`.boot` section).
   - Loads the `PT_LOAD` segments at their physical addresses (1 MiB upwards).
   - Enters `_start` in 32-bit protected mode, paging off, interrupts off, with
     the protocol magic in `EAX` and the info structure address in `EBX`.

2. **Bootstrap (`src/boot/boot.S`)**
   - Points `ESP` at the boot stack and zeroes `.bss`.
   - Validates the Multiboot magic and `CPUID.80000001h:EDX.LM`. Either failure
     paints a message to VGA and COM1 and halts, rather than faulting blind.
   - Identity maps the low 4 GiB with 2 MiB pages (PML4 -> PDPT -> 4x PD).
   - Sets `CR4.PAE`, `EFER.LME|NXE`, `CR0.PG|WP`, loads a temporary 64-bit GDT
     and far-jumps into long mode.
   - Calls `kmain(magic, mb_info)` per the System V AMD64 ABI, with the stack
     16-byte aligned at the call site.

3. **Kernel initialization (`src/main.zig`)**
   - Serial + VGA consoles.
   - Parses the Multiboot info structure.
   - Installs the permanent GDT and the TSS, then the IDT (which first remaps
     the PIC).
   - Points `#DF` at IST1 so a double fault gets its own stack.
   - Initializes the PMM from the bootloader's memory map, then the heap/VMM.
   - Runs the memory self-tests, unmasks the timer and keyboard IRQs, enables
     interrupts, and idles in `hlt`.

## Components

### Boot (`src/boot`)
- **boot.S**: Multiboot 1 and 2 headers; 32-bit -> long mode bring-up.
- **multiboot.zig**: Normalizes the Multiboot 1 and 2 info structures behind one
  memory-map iterator.

### Kernel (`src/kernel`)
- **main.zig**: Entry point and init order.
- **panic.zig**: The root `panic` namespace. Hand-written rather than
  `std.debug.FullPanic` so safety checks do not pull std's formatting and Io
  stack into a freestanding image.
- **log.zig**: Minimal console tee (VGA + COM1) with decimal/hex/byte-size
  helpers. Deliberately avoids `std.fmt`.

### Memory management (`src/memory`)
- **pmm.zig**: Bitmap allocator over 4 KiB frames, populated from the Multiboot
  memory map. Reserves low memory and the kernel image. Tracks the low 4 GiB —
  the range `boot.S` identity maps.
- **vmm.zig**: 4-level page table walker: `mapPage`, `unmapPage`,
  `getPhysicalAddress`. Refuses to touch addresses covered by a 2 MiB/1 GiB
  mapping rather than silently unmapping live memory.
- **heap.zig**: Bump allocator over PMM-supplied frames.

### Architecture-specific (`src/arch/x86_64`)
- **gdt.zig**: Permanent GDT (ring 0/3 code and data) plus the 16-byte TSS
  descriptor. Reloads CS with a far return (`lretq`).
- **tss.zig**: TSS, `rsp0` and the interrupt stack table.
- **idt.zig**: 256-entry IDT. Vectors without a stub are left not-present, so a
  stray interrupt raises `#GP` instead of jumping through garbage. Interrupts
  are not enabled here — the caller decides when.
- **isr.S**: One stub per vector, normalizing the frame so vectors that push an
  error code and vectors that do not share a single layout.
- **isr.zig**: Dispatch. IRQs go to registered handlers and are always EOI'd;
  unrecoverable exceptions dump registers (plus CR2 and a decoded error code for
  `#PF`) and panic instead of returning into the faulting instruction.
- **pic.zig**: 8259 remap to vectors 32-47, per-line masking.
- **port.zig**: Port I/O.

### Drivers (`src/drivers`)
- **vga.zig**: 80x25 text mode, scrolling, hardware cursor.
- **serial.zig**: COM1 at 38400 8N1 with a loopback self-test.

## Memory Layout

```
0x00000000 - 0x000FFFFF  Low memory (BIOS, EBDA, VGA) - reserved in the PMM
0x000B8000               VGA text buffer
0x00100000               .boot (Multiboot headers)
0x00101000 - kernel_end  .text / .rodata / .data / .bss
kernel_end - 4 GiB       PMM-managed frames (minus bootloader-reserved holes)
0x00000000 - 4 GiB       Identity mapped by boot.S with 2 MiB pages
```

`kernel_end` is exported by `linker.ld` and is what the PMM uses to avoid
handing out the kernel's own pages.

### Linker script notes

`linker.ld` matches every input section family explicitly (`.text .text.*`,
`.rodata .rodata.*`, ...). Zig compiles with function sections, so a bare
`*(.text)` matches nothing and the real code becomes an orphan section that LLD
places wherever it likes. The Multiboot headers are wrapped in `KEEP()` because
nothing in the kernel references them and `--gc-sections` is on.

## Interrupt Handling

- Vectors 0-31: CPU exceptions.
- Vectors 32-47: PIC IRQs (`pic.VECTOR_BASE`).
- Vectors 48-255: not present.
- `#DF` (vector 8) runs on IST1.

## Known Limitations

- No guard page below the kernel stack, so a stack overflow corrupts `.bss`
  silently instead of faulting.
- Physical memory above 4 GiB is ignored (nothing maps it yet).
- The kernel is identity mapped, not higher-half.
- `isr_common_stub` saves only the general purpose registers. This is why the
  build subtracts SSE/MMX/AVX from the target: if kernel code used `xmm`
  registers, an interrupt would clobber the interrupted context.
- The heap cannot free individual allocations.

## Building

```bash
zig build            # zig-out/bin/tessera.elf
zig build run        # boot it in QEMU
zig build iso        # bootable GRUB ISO (needs grub-mkrescue + xorriso)
```

## Future Improvements

- [ ] Guard page for the kernel stack
- [ ] Higher-half kernel
- [ ] Slab/buddy allocator
- [ ] Keyboard driver
- [ ] Timer/scheduler
- [ ] System calls
- [ ] Userspace
- [ ] File system support
