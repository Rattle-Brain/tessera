# Tessera
This is Tessera, a modular open-source kernel primarily for x86_64 systems. It's still a much-to-be-done work in progress, but I intend to make a small functional implementation.

The main idea of this is to make a kernel written in Zig that has a very small core and several modules that can be, *ideally*, hot-loaded without needing to recompile the whole kernel code.

## Structure

```
boot/
  multiboot.zig    # Multiboot2 header
  boot.S           # Bootstrap assembly code

kernel/
  main.zig         # Kernel entry point
  panic.zig        # Panic handler

memory/
  pmm.zig          # Physical memory manager
  vmm.zig          # Virtual memory manager
  heap.zig         # Heap allocator

arch/x86_64/
  gdt.zig          # Global Descriptor Table
  idt.zig          # Interrupt Descriptor Table
  isr.zig          # Interrupt Service Routines
  port.zig         # Port I/O operations

drivers/
  vga.zig          # VGA text mode driver
  serial.zig       # Serial output for debugging
```

## Building

Requirements:
- Zig compiler (0.11.0 or later)
- GNU Make (optional)
- QEMU (for testing)

```bash
# Build the kernel
zig build

# The kernel ELF will be in zig-out/bin/tessera.elf
```

## Boot Options

### Limine Bootloader
Copy `tessera.elf` and `limine.cfg` to a boot partition and install Limine.

### Multiboot2
The kernel includes a Multiboot2 header and can be booted by any Multiboot2-compliant bootloader (GRUB2, etc.)

## Testing

```bash
# Test with QEMU (using multiboot2)
qemu-system-x86_64 -kernel zig-out/bin/tessera.elf -serial stdio
```

## Features

- [x] Multiboot2 support
- [x] VGA text mode driver
- [x] Serial output for debugging
- [x] GDT initialization
- [x] IDT initialization
- [x] Basic physical memory manager
- [x] Panic handler
- [ ] Virtual memory manager (in progress)
- [ ] Heap allocator (basic implementation)
- [ ] Keyboard driver
- [ ] Timer
- [ ] Userspace

## License

GPL-3.0 - See LICENSE file for details.

