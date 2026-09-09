# Quick Start Guide

## Prerequisites

- Zig 0.16.0
- QEMU (`brew install qemu` / `apt install qemu-system-x86`)
- Make (optional, just a wrapper around `zig build`)

## Build

```bash
zig build          # -> zig-out/bin/tessera.elf
```

## Run

```bash
zig build run
```

No bootloader required. Extra QEMU flags go after `--`, e.g.
`zig build run -- -m 1G -display none`.

## Expected Output

Both the VGA console and the serial line should show:

```
Tessera 0.1.0
boot: Multiboot 1, info at 0x00009500
cpu: installing GDT/TSS
cpu: installing IDT and remapping PIC
mem: physical memory map
  0x000000000000 - 0x00000009FC00  usable
  0x00000009FC00 - 0x0000000A0000  reserved
  0x0000000F0000 - 0x000000100000  reserved
  0x000000100000 - 0x00001FFE0000  usable
  0x00001FFE0000 - 0x000020000000  reserved
  0x0000FFFC0000 - 0x000100000000  reserved
  0x00FD00000000 - 0x010000000000  reserved
mem: 511 MiB usable, 510 MiB free
self-test: pmm, heap and vmm OK
boot: initialisation complete
```

The exact memory map depends on how much RAM you gave QEMU. Booting via GRUB
says `Multiboot 2` instead.

After that the kernel idles in `hlt` servicing timer interrupts.

## Debugging

```bash
zig build run -- -s -S
# in another terminal
gdb zig-out/bin/tessera.elf -ex 'target remote :1234'
```

Useful QEMU flags:

- `-d int,cpu_reset` — log every interrupt and every CPU reset. This is the
  quickest way to tell a triple fault (reset loop) apart from a hang.
- `-d guest_errors` — flag bad MMIO/port access.
- `-display none` — headless; serial still goes to stdio.

## Bootable ISO (GRUB / Multiboot 2)

Needs `grub-mkrescue` and `xorriso`.

```bash
zig build iso                                            # Linux
zig build iso -Dgrub-mkrescue=x86_64-elf-grub-mkrescue   # Homebrew
zig build run-iso
```

## Troubleshooting

**`qemu-system-x86_64: Cannot load x86-64 image, give a 32bit one`**
You pointed `-kernel` at `zig-out/bin/tessera.elf` directly. QEMU's Multiboot
loader needs an ELFCLASS32 file; use `zig build run`, which repacks it first.

**Nothing on screen and QEMU keeps restarting**
That is a triple fault. Add `-no-reboot -d int,cpu_reset` so QEMU stops on the
first reset and logs the CPU state that led to it.

**`FATAL: not loaded by a Multiboot-compliant bootloader`**
The magic value in EAX was neither `0x2BADB002` nor `0x36D76289`. Whatever
loaded the kernel is not speaking Multiboot.

**`FATAL: CPU does not support x86_64 long mode`**
The emulated CPU has no `CPUID.80000001h:EDX.LM`. Drop any `-cpu` override.

**Kernel builds but the bootloader says there is no Multiboot header**
Check that `.boot` is still an allocated section inside a `PT_LOAD` segment:

```bash
objdump --headers zig-out/bin/tessera.elf | grep boot
objdump -p zig-out/bin/tessera.elf | head
```

A custom-named section declared without the `"a"` (SHF_ALLOC) flag is silently
kept out of every load segment, which makes the header invisible to the loader.

## Contributing

See ARCHITECTURE.md for detailed information about the kernel design.

## License

GPL-3.0 - See LICENSE file for details.
