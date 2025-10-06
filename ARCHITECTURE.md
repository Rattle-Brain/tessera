# Tessera Kernel Architecture

## Overview
Tessera is a modular x86_64 kernel written in Zig with support for both Limine and Multiboot2 bootloaders.

## Boot Process

1. **Bootloader** (Limine or Multiboot2-compliant)
   - Loads the kernel into memory
   - Sets up initial page tables
   - Passes control to `_start` in boot.S

2. **Bootstrap (boot.S)**
   - Disables interrupts
   - Sets up initial stack
   - Saves multiboot information
   - Calls `kmain()` in kernel/main.zig

3. **Kernel Initialization (kernel/main.zig)**
   - Initializes VGA text mode for output
   - Initializes serial port for debugging
   - Sets up Global Descriptor Table (GDT)
   - Sets up Interrupt Descriptor Table (IDT)
   - Initializes Physical Memory Manager (PMM)
   - Enters idle loop

## Components

### Boot (/boot)
- **multiboot.zig**: Multiboot2 header structure
- **boot.S**: Assembly bootstrap code

### Kernel (/kernel)
- **main.zig**: Kernel entry point and initialization
- **panic.zig**: Kernel panic handler

### Memory Management (/memory)
- **pmm.zig**: Physical memory manager (bitmap-based)
- **vmm.zig**: Virtual memory manager (placeholder)
- **heap.zig**: Kernel heap allocator (bump allocator)

### Architecture-Specific (/arch/x86_64)
- **gdt.zig**: Global Descriptor Table setup
- **idt.zig**: Interrupt Descriptor Table setup
- **isr.zig**: Interrupt Service Routines
- **port.zig**: Port I/O operations (inb, outb, etc.)

### Drivers (/drivers)
- **vga.zig**: VGA text mode driver (80x25)
- **serial.zig**: Serial port driver (COM1)

## Memory Layout

```
0x00000000 - 0x000FFFFF  : Low memory (BIOS, Video, etc.)
0x00100000 - ...         : Kernel code and data
0xB8000                  : VGA text buffer
0xFFFFFFFF80000000+      : Higher half kernel (future)
```

## Interrupt Handling

- Interrupts 0-31: CPU exceptions
- Interrupts 32-47: Hardware IRQs (PIC)
- Interrupts 48+: Software interrupts

## Building

The kernel uses Zig's build system. See `build.zig` for build configuration.

```bash
zig build
```

Output: `zig-out/bin/tessera.elf`

## Testing

```bash
qemu-system-x86_64 -kernel zig-out/bin/tessera.elf -serial stdio
```

## Future Improvements

- [ ] Complete virtual memory manager
- [ ] Better heap allocator (slab/buddy)
- [ ] Keyboard driver
- [ ] Timer/scheduler
- [ ] System calls
- [ ] Userspace
- [ ] File system support
