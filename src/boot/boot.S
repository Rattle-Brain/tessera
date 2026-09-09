/*
 * Tessera bootstrap: Multiboot entry -> long mode -> kmain().
 *
 * The bootloader hands us 32-bit protected mode, paging disabled, interrupts
 * disabled, and a flat GDT it owns. Everything below builds the minimum
 * required to run 64-bit Zig code:
 *
 *   1. zero .bss           (do not assume the loader did it)
 *   2. verify CPUID/long mode
 *   3. identity map the low 4 GiB with 2 MiB pages
 *   4. PAE + EFER.LME + CR0.PG, then a far jump into a 64-bit code segment
 *   5. call kmain(magic, mb_info)
 */

/*
 * NOTE: the ",\"a\"" is load-bearing. Without the SHF_ALLOC flag GAS gives a
 * custom-named section no flags at all, the linker keeps it out of every
 * PT_LOAD segment, and the bootloader then finds no Multiboot header in the
 * loaded image and refuses to boot.
 */
.section .multiboot, "a", @progbits

/* ---- Multiboot 1 header (0x1BADB002) ------------------------------------
 * Only here so that `qemu-system-x86_64 -kernel` can boot the ELF directly:
 * QEMU's built-in loader implements Multiboot 1 but not Multiboot 2.
 */
.set MB1_MAGIC, 0x1BADB002
.set MB1_FLAGS, 0x00000003          /* align modules to 4K | provide meminfo */

.balign 4
mb1_header:
    .long MB1_MAGIC
    .long MB1_FLAGS
    .long -(MB1_MAGIC + MB1_FLAGS)

/* ---- Multiboot 2 header (0xE85250D6) ---------------------------------- */
.set MB2_MAGIC, 0xE85250D6
.set MB2_ARCH,  0                   /* 0 = i386 protected mode. This is the
                                     * state the loader must enter us in, not
                                     * the width of the kernel, so 0 is correct
                                     * for an x86_64 kernel too. */

.balign 8
mb2_header:
    .long MB2_MAGIC
    .long MB2_ARCH
    .long mb2_header_end - mb2_header
    .long -(MB2_MAGIC + MB2_ARCH + (mb2_header_end - mb2_header))

    /* End tag */
    .balign 8
    .short 0                        /* type = end */
    .short 0                        /* flags   */
    .long  8                        /* size    */
mb2_header_end:


.section .text, "ax", @progbits
.code32
.global _start
.type _start, @function
_start:
    cli
    cld

    /* Stash the Multiboot handoff registers in callee-preserved registers.
     * ebp = magic, edx = info pointer. Both survive the .bss wipe below,
     * which clobbers eax/ecx/edi. */
    movl %eax, %ebp
    movl %ebx, %edx

    /* The stack lives in .bss; it is safe to point at it before the wipe
     * because nothing has been pushed yet. */
    movl $stack_top, %esp

    /* ---- 1. Zero .bss ------------------------------------------------- */
    movl $__bss_start, %edi
    movl $__bss_end, %ecx
    subl %edi, %ecx
    shrl $2, %ecx                   /* linker script aligns __bss_end to 8 */
    xorl %eax, %eax
    rep stosl

    /* Now that .bss is clean, park the handoff values there. */
    movl %ebp, mb_magic
    movl %edx, mb_info

    /* ---- 2. Validate the handoff and the CPU -------------------------- */
    cmpl $0x36D76289, %ebp          /* Multiboot 2 */
    je 1f
    cmpl $0x2BADB002, %ebp          /* Multiboot 1 */
    je 1f
    movl $err_no_multiboot, %esi
    jmp boot_fail32
1:
    call check_long_mode

    /* ---- 3/4. Paging and long mode ------------------------------------ */
    call setup_page_tables
    call enable_long_mode

    lgdt gdt64_pointer
    ljmp $0x08, $long_mode_start


/*
 * Confirm the CPU implements extended CPUID leaves and long mode.
 * Clobbers eax/ebx/ecx/edx (edx is reloaded from mb_info by the caller's
 * later use of memory, so it must not be relied on after this point).
 */
check_long_mode:
    /* Extended leaves present? */
    movl $0x80000000, %eax
    cpuid
    cmpl $0x80000001, %eax
    jb 1f

    /* CPUID.80000001h:EDX.LM (bit 29) */
    movl $0x80000001, %eax
    cpuid
    testl $(1 << 29), %edx
    jz 1f
    ret
1:
    movl $err_no_long_mode, %esi
    jmp boot_fail32


/*
 * Identity map [0, 4 GiB) using 2 MiB pages:
 *   PML4[0]      -> boot_pdpt
 *   PDPT[0..3]   -> boot_pd[0..3]
 *   boot_pd[i]   -> 2 MiB page at i * 2 MiB
 *
 * 4 GiB (rather than the single 2 MiB page this used to map) means the kernel
 * keeps running no matter where in low memory it was linked, and it also covers
 * the VGA window and the usual PCI MMIO hole. The tables are already zeroed by
 * the .bss wipe, so only the live entries are written.
 */
setup_page_tables:
    /* PML4[0] -> boot_pdpt */
    movl $boot_pdpt, %eax
    orl  $0x03, %eax                /* present | writable */
    movl %eax, boot_pml4

    /* PDPT[0..3] -> the four page directories */
    movl $boot_pdpt, %edi
    movl $boot_pd, %eax
    orl  $0x03, %eax
    movl $4, %ecx
1:
    movl %eax, (%edi)
    addl $4096, %eax                /* next page directory */
    addl $8, %edi
    loop 1b

    /* 2048 * 2 MiB = 4 GiB of huge pages */
    movl $boot_pd, %edi
    movl $0x83, %eax                /* present | writable | page size (2 MiB) */
    movl $2048, %ecx
1:
    movl %eax, (%edi)
    addl $0x200000, %eax
    addl $8, %edi
    loop 1b

    ret


enable_long_mode:
    /* CR3 = PML4 */
    movl $boot_pml4, %eax
    movl %eax, %cr3

    /* CR4.PAE (bit 5) is mandatory for long mode. */
    movl %cr4, %eax
    orl  $(1 << 5), %eax
    movl %eax, %cr4

    /* IA32_EFER.LME (bit 8) | .NXE (bit 11) */
    movl $0xC0000080, %ecx
    rdmsr
    orl  $((1 << 8) | (1 << 11)), %eax
    wrmsr

    /* CR0.PG (bit 31) | CR0.WP (bit 16) */
    movl %cr0, %eax
    orl  $((1 << 31) | (1 << 16)), %eax
    movl %eax, %cr0

    ret


/*
 * Fatal error before we have any drivers: paint a message into the VGA text
 * buffer and push it out COM1, then stop. esi = NUL-terminated string.
 * Paging is still off here, so 0xB8000 is directly addressable.
 */
boot_fail32:
    /* Minimal 38400-8N1 COM1 setup so the message also reaches -serial. */
    movl $0x3F9, %edx               /* IER  */
    xorl %eax, %eax
    outb %al, %dx
    movl $0x3FB, %edx               /* LCR: enable DLAB */
    movb $0x80, %al
    outb %al, %dx
    movl $0x3F8, %edx               /* divisor low = 3 */
    movb $0x03, %al
    outb %al, %dx
    movl $0x3F9, %edx               /* divisor high = 0 */
    xorl %eax, %eax
    outb %al, %dx
    movl $0x3FB, %edx               /* LCR: 8N1 */
    movb $0x03, %al
    outb %al, %dx

    movl $0xB8000, %edi
    movl $0x4F00, %ebx              /* white on red */
1:
    movzbl (%esi), %eax
    testb %al, %al
    jz 3f

    /* VGA cell */
    orl  %ebx, %eax
    movw %ax, (%edi)
    addl $2, %edi

    /* COM1, spinning on LSR.THRE (bit 5) */
    movl $0x3FD, %edx
2:
    inb  %dx, %al
    testb $0x20, %al
    jz 2b
    movzbl (%esi), %eax
    movl $0x3F8, %edx
    outb %al, %dx

    addl $1, %esi
    jmp 1b
3:
    cli
4:
    hlt
    jmp 4b


.code64
long_mode_start:
    /* Reload the data segment selectors from our own GDT. */
    movw $0x10, %ax
    movw %ax, %ds
    movw %ax, %es
    movw %ax, %fs
    movw %ax, %gs
    movw %ax, %ss

    movq $stack_top, %rsp
    xorq %rbp, %rbp

    /*
     * System V AMD64: first two args in rdi/rsi, and rsp must be 16-byte
     * aligned *at the call site*. stack_top is 16-byte aligned and nothing has
     * been pushed, so calling directly is correct. (Pushing an argument here,
     * as this code used to, both misaligned the stack and put the argument
     * somewhere kmain never looks.)
     */
    movl mb_magic(%rip), %edi       /* zero-extends into rdi */
    movl mb_info(%rip), %esi        /* zero-extends into rsi */
    call kmain

    /* kmain is noreturn; if it ever does return, stop hard. */
    cli
1:
    hlt
    jmp 1b

.size _start, . - _start


.section .rodata, "a", @progbits
err_no_multiboot:
    .asciz "FATAL: not loaded by a Multiboot-compliant bootloader"
err_no_long_mode:
    .asciz "FATAL: CPU does not support x86_64 long mode"

/* Minimal long-mode GDT: null, 64-bit ring 0 code, ring 0 data.
 * gdt.zig installs the real one (with a TSS) once Zig code is running. */
.balign 16
gdt64:
    .quad 0                         /* null */
    .quad 0x00AF9A000000FFFF        /* 0x08: code64, present, ring 0, L=1 */
    .quad 0x00CF92000000FFFF        /* 0x10: data,   present, ring 0       */
gdt64_pointer:
    .word gdt64_pointer - gdt64 - 1
    .quad gdt64


.section .bss, "aw", @nobits

/* Multiboot handoff values, saved before we clobber the registers. */
.balign 8
mb_magic:
    .skip 8
mb_info:
    .skip 8

/* Boot page tables. Must be 4 KiB aligned; contents come from the .bss wipe. */
.balign 4096
boot_pml4:
    .skip 4096
boot_pdpt:
    .skip 4096
boot_pd:
    .skip 4096 * 4                  /* four directories = 4 GiB of 2 MiB pages */

/* Boot/kernel stack. stack_top must be 16-byte aligned for the SysV ABI. */
.balign 16
stack_bottom:
    .skip 65536                     /* 64 KiB */
stack_top:
