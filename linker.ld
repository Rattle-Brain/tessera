ENTRY(_start)

SECTIONS
{
    /* Load kernel at 1MB physical address */
    . = 1M;

    /* Multiboot header must be in first 8KB */
    .boot :
    {
        *(.multiboot)
    }

    /* Text section (code) */
    .text ALIGN(4K) :
    {
        *(.text)
    }

    /* Read-only data */
    .rodata ALIGN(4K) :
    {
        *(.rodata)
    }

    /* Initialized data */
    .data ALIGN(4K) :
    {
        *(.data)
    }

    /* Uninitialized data */
    .bss ALIGN(4K) :
    {
        *(COMMON)
        *(.bss)
    }

    /* Mark end of kernel for memory allocation */
    kernel_end = .;
}
