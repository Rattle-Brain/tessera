.PHONY: all clean run debug

all:
	zig build

clean:
	rm -rf zig-cache zig-out

run: all
	qemu-system-x86_64 -kernel zig-out/bin/tessera.elf -serial stdio

debug: all
	qemu-system-x86_64 -kernel zig-out/bin/tessera.elf -serial stdio -s -S

iso: all
	@echo "Creating bootable ISO with Limine..."
	@mkdir -p iso_root
	@cp zig-out/bin/tessera.elf iso_root/
	@cp limine.cfg iso_root/
	@echo "Note: You need to install Limine bootloader files to create a bootable ISO"
