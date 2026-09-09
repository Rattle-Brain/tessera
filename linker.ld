/* Tessera kernel link map.
 *
 * The kernel is loaded by a Multiboot bootloader at a fixed physical address
 * and runs identity-mapped, so LMA == VMA everywhere.
 *
 * Every input section is matched explicitly (including the ".text.*" /
 * ".rodata.*" families that Zig emits with -ffunction-sections). Anything left
 * for LLD to place on its own becomes an orphan section, which is how the
 * Multiboot header previously ended up outside every PT_LOAD segment.
 */

ENTRY(_start)

/* 1 MiB: the lowest address that is guaranteed to be usable RAM. Must stay
 * inside the range that boot.S identity-maps. */
KERNEL_BASE = 0x100000;

SECTIONS
{
    . = KERNEL_BASE;

    /* The Multiboot headers must live in the first 32 KiB of the file and be
     * 8-byte aligned. KEEP() stops --gc-sections from dropping them, since
     * nothing in the kernel references them. */
    .boot ALIGN(8) : ALIGN(8)
    {
        __boot_start = .;
        KEEP(*(.multiboot))
        KEEP(*(.multiboot2))
    }

    .text ALIGN(4K) : ALIGN(4K)
    {
        *(.text.unlikely .text.unlikely.*)
        *(.text.startup .text.startup.*)
        *(.text .text.*)
        *(.ltext .ltext.*)
    }

    .rodata ALIGN(4K) : ALIGN(4K)
    {
        *(.rodata .rodata.*)
        *(.rodata.cst*)
        *(.rodata.str*)
        *(.lrodata .lrodata.*)
        *(.srodata .srodata.*)
    }

    .data ALIGN(4K) : ALIGN(4K)
    {
        *(.data .data.*)
        *(.ldata .ldata.*)
        *(.sdata .sdata.*)
        /* Not actually relocated at runtime (we link non-PIC), but LLD may
         * still emit these output section names. */
        *(.data.rel.ro .data.rel.ro.*)
        *(.got .got.plt .igot .igot.plt)
    }

    .bss ALIGN(4K) : ALIGN(4K)
    {
        __bss_start = .;
        *(COMMON)
        *(.bss .bss.*)
        *(.lbss .lbss.*)
        *(.sbss .sbss.*)
        . = ALIGN(8);
        __bss_end = .;
    }

    . = ALIGN(4K);
    /* First free physical address above the kernel image. The PMM uses this to
     * avoid handing out pages the kernel is sitting in. */
    kernel_end = .;
    __kernel_end = .;

    /DISCARD/ :
    {
        *(.eh_frame .eh_frame.*)
        *(.eh_frame_hdr)
        *(.gcc_except_table .gcc_except_table.*)
        *(.note .note.*)
        *(.comment)
        *(.interp)
        *(.dynamic)
        *(.dynsym .dynstr .hash .gnu.hash)
    }
}
