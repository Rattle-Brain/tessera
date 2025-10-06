# Quick Start Guide

## Prerequisites

- Zig compiler (0.11.0 or later recommended)
- QEMU (for testing)
- Make (optional, for convenience commands)

## Building the Kernel

### Using Zig directly:
```bash
zig build
```

### Using Make:
```bash
make
```

The kernel will be built as `zig-out/bin/tessera.elf`

## Testing

### Run with QEMU:
```bash
make run
# or
qemu-system-x86_64 -kernel zig-out/bin/tessera.elf -serial stdio
```

### Debug with QEMU:
```bash
make debug
# Then in another terminal:
gdb zig-out/bin/tessera.elf
(gdb) target remote :1234
```

## Expected Output

When you run the kernel, you should see:

```
Tessera Kernel v0.1.0
Initializing GDT...
GDT initialized
Initializing IDT...
IDT initialized
Initializing PMM...
PMM initialized

Kernel initialization complete!
```

Serial output (if connected) will show:
```
Kernel initialized
```

## Project Structure

```
tessera/
├── boot/           # Bootloader interface
├── kernel/         # Core kernel code
├── memory/         # Memory management
├── arch/x86_64/    # Architecture-specific code
└── drivers/        # Device drivers
```

## Common Tasks

### Clean build artifacts:
```bash
make clean
# or
rm -rf zig-cache zig-out
```

### View build options:
```bash
zig build --help
```

## Troubleshooting

**Build fails with Zig version error:**
- Ensure you have Zig 0.11.0 or later
- Update using `zigup` or download from ziglang.org

**QEMU doesn't start:**
- Ensure qemu-system-x86_64 is installed
- Try: `apt install qemu-system-x86` (Ubuntu/Debian)
- Or: `brew install qemu` (macOS)

**Kernel doesn't boot:**
- Check that the ELF file was created: `ls -lh zig-out/bin/tessera.elf`
- Try enabling QEMU debug output: `-d int,cpu_reset`

## Bootloader Support

### Limine
1. Copy `tessera.elf` and `limine.cfg` to boot partition
2. Install Limine bootloader
3. Boot from the partition

### GRUB (Multiboot2)
1. Copy `tessera.elf` to `/boot/`
2. Add to GRUB config:
```
menuentry "Tessera" {
    multiboot2 /boot/tessera.elf
    boot
}
```

## Contributing

See ARCHITECTURE.md for detailed information about the kernel design.

## License

GPL-3.0 - See LICENSE file for details.
