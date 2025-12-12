(git clone https://codeberg.org/Limine/Limine.git --branch=v10.x-binary --depth=1)
To generate the .iso from a .elf file it's needed this 4 files in the same folder:
    
    -limine-bios-cd.bin
    -limine-bios.sys
    -limine-cfg
    -tessera.elf

    And the limine.exe to execute the installation.

This generates a ISO using xorriso:
    
    xorriso -as mkisofs -b boot/limine-bios-cd.bin -no-emul-boot -boot-load-size 4 -boot-info-table iso -o tessera.iso

Once you have this files, you can execute the command (WSL on Windows): 
    
    cmd.exe /C limine.exe bios-install tessera.elf

Finally, execute qemu with the new .iso file:
    
    qemu-system-x86_64 -cdrom tessera.iso -serial stdio