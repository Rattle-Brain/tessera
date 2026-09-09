# Thin wrapper around `zig build`. See build.zig for the real definitions.
#
# GRUB is packaged under different names; on Homebrew it is
# `x86_64-elf-grub-mkrescue`, so pass GRUB_MKRESCUE to override.
GRUB_MKRESCUE ?= grub-mkrescue

.PHONY: all run debug iso run-iso clean

all:
	zig build

# Boots straight out of QEMU: no bootloader needed, output on stdio.
run:
	zig build run

# Same, but stopped at the first instruction with a gdb stub on :1234.
# In another terminal: gdb zig-out/bin/tessera.elf -ex 'target remote :1234'
debug:
	zig build run -- -s -S

iso:
	zig build iso -Dgrub-mkrescue=$(GRUB_MKRESCUE)

run-iso:
	zig build run-iso -Dgrub-mkrescue=$(GRUB_MKRESCUE)

clean:
	rm -rf .zig-cache zig-out
