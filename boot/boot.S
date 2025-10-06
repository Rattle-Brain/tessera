.section .text
.global _start
.type _start, @function

_start:
    # Disable interrupts
    cli

    # Set up stack
    mov $stack_top, %rsp

    # Clear direction flag
    cld

    # Save multiboot info pointer
    push %rbx

    # Call the Zig kernel main function
    call kmain

    # Hang if kmain returns
    cli
1:
    hlt
    jmp 1b

.size _start, . - _start

# Reserve stack space
.section .bss
.align 16
stack_bottom:
.skip 16384  # 16 KiB stack
stack_top:
