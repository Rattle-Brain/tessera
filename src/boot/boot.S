.section .text
.code32
.global _start
.type _start, @function

_start:
    # Disable interrupts
    cli

    # Save multiboot2 magic and info pointer (32-bit registers)
    mov %eax, %edi  # Multiboot2 magic
    mov %ebx, %esi  # Multiboot2 info pointer

    # Verify multiboot2 magic 
    # (Multiboot 2 compliant kernels used the magic number 0xE85250D6, and Multiboot-compliant bootloaders report themselves with magic number 0x36D76289)
    cmp $0x36D76289, %edi
    jne multiboot_error

    # Set up minimal stack for 32-bit mode
    mov $stack_top, %esp

    # Clear direction flag
    cld

    # Set up paging for long mode
    call setup_page_tables
    call enable_paging

    # Load GDT
    lgdt gdt64_pointer

    # Far jump to 64-bit code segment
    ljmp $0x08, $long_mode_start

multiboot_error:
    # Hang on multiboot error
    cli
1:
    hlt
    jmp 1b

# Set up identity mapping for first 2MB + higher half mapping
setup_page_tables:
    # Zero out all three page tables (PML4, PDPT, PD)
    mov $boot_pml4, %edi
    mov $0, %eax
    mov $3072, %ecx  # 3 pages * 4096 bytes / 4 = 3072 dwords
    rep stosl

    # PML4[0] -> boot_pdpt (identity map first 2MB)
    mov $boot_pml4, %edi
    mov $boot_pdpt, %eax
    or $0b11, %eax  # Present + Writable
    mov %eax, (%edi)

    # PML4[511] -> boot_pdpt (higher half at 0xFFFFFFFF80000000)
    # Note: Same PDPT for both identity and higher half for simplicity
    mov $boot_pml4, %edi
    add $4088, %edi  # 511 * 8
    mov $boot_pdpt, %eax
    or $0b11, %eax
    mov %eax, (%edi)

    # PDPT[0] -> boot_pd
    mov $boot_pdpt, %edi
    mov $boot_pd, %eax
    or $0b11, %eax
    mov %eax, (%edi)

    # PD[0] -> 2MB huge page at 0x0
    mov $boot_pd, %edi
    mov $0x0, %eax
    or $0b10000011, %eax  # Present + Writable + Huge
    mov %eax, (%edi)

    ret

enable_paging:
    # Load PML4 into CR3
    mov $boot_pml4, %eax
    mov %eax, %cr3

    # Enable PAE (CR4.PAE = 1)
    mov %cr4, %eax
    or $(1 << 5), %eax
    mov %eax, %cr4

    # Enable long mode (EFER.LME = 1) and NX bit (EFER.NXE = 1)
    mov $0xC0000080, %ecx
    rdmsr
    or $(1 << 8) | (1 << 11), %eax  # LME + NXE
    wrmsr

    # Enable paging (CR0.PG = 1)
    mov %cr0, %eax
    or $(1 << 31), %eax
    mov %eax, %cr0

    ret

.code64
long_mode_start:
    # Load segment registers
    mov $0x10, %ax
    mov %ax, %ds
    mov %ax, %es
    mov %ax, %fs
    mov %ax, %gs
    mov %ax, %ss

    # Set up 64-bit stack
    mov $stack_top, %rsp

    # Restore multiboot info (zero-extend esi to rsi)
    mov %esi, %esi
    push %rsi

    # Call the Zig kernel main function
    call kmain

    # Hang if kmain returns
    cli
1:
    hlt
    jmp 1b

.size _start, . - _start

# Temporary GDT for 64-bit mode
.section .rodata
.align 16
gdt64:
    .quad 0                        # Null descriptor
    .quad 0x00AF9A000000FFFF       # Code segment (64-bit)
    .quad 0x00AF92000000FFFF       # Data segment (64-bit)
gdt64_pointer:
    .word gdt64_pointer - gdt64 - 1
    .quad gdt64

# Page tables (aligned to 4KB)
.section .bss
.align 4096
boot_pml4:
    .skip 4096
boot_pdpt:
    .skip 4096
boot_pd:
    .skip 4096

# Reserve stack space
.align 16
stack_bottom:
    .skip 16384  # 16 KiB stack
stack_top:
