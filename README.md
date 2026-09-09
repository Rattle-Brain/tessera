# Tessera

This is Tessera, a modular open-source kernel primarily for x86_64 systems. It's still a much-to-be-done work in progress, but I intend to make a small functional implementation.

The main idea of this is to make a kernel written in Zig that has a very small core and several modules that can be, *ideally*, hot-loaded without needing to recompile the whole kernel code.

## Structure

```
src/
  boot/
    boot.S           # Multiboot 1/2 headers, long mode bring-up
    multiboot.zig    # Multiboot info parsing (memory map, etc.)

  kernel/
    main.zig         # Kernel entry point
    panic.zig        # Panic handler namespace
    log.zig          # Minimal console (VGA + serial)

  memory/
    pmm.zig          # Physical memory manager (bitmap)
    vmm.zig          # Virtual memory manager (4-level page tables)
    heap.zig         # Kernel heap (bump allocator over PMM frames)

  arch/x86_64/
    gdt.zig          # Global Descriptor Table + TSS descriptor
    idt.zig          # Interrupt Descriptor Table
    isr.zig          # Interrupt/exception dispatch
    isr.S            # Per-vector interrupt stubs
    pic.zig          # 8259 PIC remapping
    tss.zig          # Task State Segment
    port.zig         # Port I/O

  drivers/
    vga.zig          # VGA text mode driver
    serial.zig       # Serial output for debugging

tools/
  mb1image.zig       # Host tool: repack the kernel as ELF32 for `qemu -kernel`
```

## Building

Requirements:
- Zig 0.16.0
- QEMU (for testing)
- `grub-mkrescue` + `xorriso` — only for building a bootable ISO

```bash
zig build
```

Produces `zig-out/bin/tessera.elf`, a 64-bit ELF linked at 1 MiB with both a
Multiboot 1 and a Multiboot 2 header.

## Running

```bash
zig build run
```

This needs nothing but Zig and QEMU. Kernel output goes to both the VGA console
and stdio (serial). Extra QEMU flags can be appended after `--`:

```bash
zig build run -- -m 1G -display none
```

> QEMU's built-in `-kernel` loader implements Multiboot **1** and only accepts
> ELFCLASS32 files, so `zig build run` repacks the kernel into a 32-bit ELF
> container first (`tools/mb1image.zig`). The segments and entry point are
> unchanged — this is purely a container swap to satisfy QEMU's loader.

### Debugging

```bash
zig build run -- -s -S
# in another terminal:
gdb zig-out/bin/tessera.elf -ex 'target remote :1234'
```

## Boot Options

### Multiboot 2 (GRUB)

The real target. `zig build iso` stages a boot tree and calls `grub-mkrescue`:

```bash
zig build iso        # -> zig-out/tessera.iso
zig build run-iso
```

On systems where GRUB is packaged under a prefixed name (Homebrew ships
`x86_64-elf-grub-mkrescue`):

```bash
brew install x86_64-elf-grub xorriso
zig build iso -Dgrub-mkrescue=x86_64-elf-grub-mkrescue
```

### Multiboot 1

Supported so that `qemu -kernel` works without a bootloader. Not the primary
path — it provides no framebuffer or ACPI information.

### Limine

Limine support has been cancelled. It would be way too complicated to start by
supporting multiple booting protocols.

## Features

- [x] Multiboot 1 + Multiboot 2 headers
- [x] 32-bit -> long mode bring-up, low 4 GiB identity mapped with 2 MiB pages
- [x] VGA text mode driver (with hardware cursor)
- [x] Serial output for debugging
- [x] GDT + TSS
- [x] IDT, per-vector ISR stubs, exception diagnostics (registers, CR2, error code)
- [x] 8259 PIC remapping, per-IRQ handler registration
- [x] Double fault handled on a dedicated IST stack
- [x] Physical memory manager driven by the bootloader's memory map
- [x] Virtual memory manager (map/unmap/translate, 4 KiB and huge pages)
- [x] Kernel heap (bump allocator backed by the PMM)
- [x] Panic handler
- [ ] Guard page for the kernel stack
- [ ] Physical memory above 4 GiB
- [ ] Higher-half kernel
- [ ] Keyboard driver
- [ ] Timer / scheduler
- [ ] Userspace

## License

GPL-3.0 - See LICENSE file for details.
