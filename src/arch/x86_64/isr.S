// This macro creates an ISR stub for exceptions that do NOT push an error code.
// It pushes a dummy error code (0) and the interrupt number, then jumps to the common stub.
.macro ISR_NO_ERR_CODE int_num
.global isr\int_num
isr\int_num:
    cli
    pushq $0  // Dummy error code
    pushq $\int_num
    jmp isr_common_stub
.endm

// This macro creates an ISR stub for exceptions that DO push an error code.
// It just pushes the interrupt number and jumps to the common stub.
.macro ISR_ERR_CODE int_num
.global isr\int_num
isr\int_num:
    cli
    // Error code is already on the stack
    pushq $\int_num
    jmp isr_common_stub
.endm

// Create the ISR stubs for the first 48 vectors (CPU exceptions + PIC IRQs)
ISR_NO_ERR_CODE 0
ISR_NO_ERR_CODE 1
ISR_NO_ERR_CODE 2
ISR_NO_ERR_CODE 3
ISR_NO_ERR_CODE 4
ISR_NO_ERR_CODE 5
ISR_NO_ERR_CODE 6
ISR_NO_ERR_CODE 7
ISR_ERR_CODE    8  // Double Fault
ISR_NO_ERR_CODE 9
ISR_ERR_CODE    10 // Invalid TSS
ISR_ERR_CODE    11 // Segment Not Present
ISR_ERR_CODE    12 // Stack-Segment Fault
ISR_ERR_CODE    13 // General Protection Fault
ISR_ERR_CODE    14 // Page Fault
ISR_NO_ERR_CODE 15
ISR_NO_ERR_CODE 16 // x87 Floating-Point
ISR_ERR_CODE    17 // Alignment Check
ISR_NO_ERR_CODE 18 // Machine Check
ISR_NO_ERR_CODE 19 // SIMD Floating-Point
ISR_NO_ERR_CODE 20
ISR_NO_ERR_CODE 21
ISR_NO_ERR_CODE 22
ISR_NO_ERR_CODE 23
ISR_NO_ERR_CODE 24
ISR_NO_ERR_CODE 25
ISR_NO_ERR_CODE 26
ISR_NO_ERR_CODE 27
ISR_NO_ERR_CODE 28
ISR_NO_ERR_CODE 29
ISR_ERR_CODE    30 // Security Exception
ISR_NO_ERR_CODE 31

// IRQs (Hardware Interrupts)
ISR_NO_ERR_CODE 32 // Timer
ISR_NO_ERR_CODE 33 // Keyboard
ISR_NO_ERR_CODE 34
ISR_NO_ERR_CODE 35
ISR_NO_ERR_CODE 36
ISR_NO_ERR_CODE 37
ISR_NO_ERR_CODE 38
ISR_NO_ERR_CODE 39
ISR_NO_ERR_CODE 40
ISR_NO_ERR_CODE 41
ISR_NO_ERR_CODE 42
ISR_NO_ERR_CODE 43
ISR_NO_ERR_CODE 44
ISR_NO_ERR_CODE 45
ISR_NO_ERR_CODE 46
ISR_NO_ERR_CODE 47

// This is the common C-callable stub.
.extern interruptHandler // This is our main Zig handler

.global isr_common_stub
isr_common_stub:
    // Push all general purpose registers
    pushq %rax
    pushq %rbx
    pushq %rcx
    pushq %rdx
    pushq %rsi
    pushq %rdi
    pushq %rbp
    pushq %r8
    pushq %r9
    pushq %r10
    pushq %r11
    pushq %r12
    pushq %r13
    pushq %r14
    pushq %r15

    // The stack pointer (%rsp) now points to our complete InterruptFrame.
    // Per the System V AMD64 ABI, the first argument to a function is passed in %rdi.
    movq %rsp, %rdi
    
    // Call the high-level Zig handler.
    call interruptHandler

    // Pop all registers in reverse order
    popq %r15
    popq %r14
    popq %r13
    popq %r12
    popq %r11
    popq %r10
    popq %r9
    popq %r8
    popq %rbp
    popq %rdi
    popq %rsi
    popq %rdx
    popq %rcx
    popq %rbx
    popq %rax
    
    // Pop the interrupt number and error code pushed by our stubs
    addq $16, %rsp
    
    // Re-enable interrupts and return from interrupt
    sti
    iretq

// Append this to the end of isr.S

.section .rodata
.global isr_stub_table
isr_stub_table:
    .quad isr0
    .quad isr1
    .quad isr2
    .quad isr3
    .quad isr4
    .quad isr5
    .quad isr6
    .quad isr7
    .quad isr8
    .quad isr9
    .quad isr10
    .quad isr11
    .quad isr12
    .quad isr13
    .quad isr14
    .quad isr15
    .quad isr16
    .quad isr17
    .quad isr18
    .quad isr19
    .quad isr20
    .quad isr21
    .quad isr22
    .quad isr23
    .quad isr24
    .quad isr25
    .quad isr26
    .quad isr27
    .quad isr28
    .quad isr29
    .quad isr30
    .quad isr31
    .quad isr32
    .quad isr33
    .quad isr34
    .quad isr35
    .quad isr36
    .quad isr37
    .quad isr38
    .quad isr39
    .quad isr40
    .quad isr41
    .quad isr42
    .quad isr43
    .quad isr44
    .quad isr45
    .quad isr46
    .quad isr47

    // TODO: To be completed as needed...
