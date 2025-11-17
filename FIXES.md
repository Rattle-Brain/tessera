# Fixes and issues with the codes

Down below is a list of all the things wrong with the kernel so far.

## Compilation Issue

**Critical**: Can't compile due to invalid ASM code.

```bash
  ⎿  Error: Exit code 1
     install
     +- install tessera.elf
        +- compile exe tessera.elf Debug x86_64-freestanding-none 4 errors
     src/arch/x86_64/gdt.zig:53:1: error: unknown size: '(%%rax)'
     fn load() void {
     ^~~~~~~~~~~~~~
     src/arch/x86_64/idt.zig:46:1: error: unknown size: '(%%rax)'
```
## Code Correctness Issues

1. Boot Code - Architecture Mismatch (boot/boot.S:1-29)

- Using x86_64 registers (%rsp, %rbx) but Multiboot2 starts in 32-bit protected mode
- Need to set up long mode and paging before using 64-bit instructions
- Missing Multiboot2 magic check

2. Linker Script Issues (linker.ld:12-31)

- Higher-half kernel addressing (0xFFFFFFFF80000000) but no paging setup in boot code
- Boot code will immediately crash accessing higher-half addresses

3. GDT Issues (arch/x86_64/gdt.zig)

- x86_64 long mode requires different GDT format (no base/limit needed)
- Inline assembly has incorrect syntax for AT&T dialect (missing $ on immediate)
- Should use 64-bit code/data segments properly

4. IDT Issues (arch/x86_64/idt.zig:26)

- All 256 interrupts use the same handler - can't differentiate which interrupt occurred
- No error code handling for CPU exceptions that push error codes
- No interrupt vector passed to handlers

5. ISR Issues (arch/x86_64/isr.zig)

- sti at line 48/88 re-enables interrupts before iretq - dangerous, could cause nested interrupts
- No interrupt number tracking
- Hardcoded PIC EOI only for master PIC (line 100), slave PIC needs EOI too

6. Port I/O Constraints (arch/x86_64/port.zig:7,22,37)

- Constraint "N{dx}" is incorrect - should be just "N" for immediate or "{dx}" for register
- Won't compile with stricter Zig versions

7. Memory Management

- PMM (memory/pmm.zig:23): Hardcoded 128MB assumption - no multiboot memory map parsing
- VMM (memory/vmm.zig): Completely stubbed out - kernel relies on bootloader identity mapping
- Heap (memory/heap.zig:6): Bump allocator overlaps with potential kernel code (1MB start)

8. Missing Multiboot Info (boot/multiboot.zig:10)

- Architecture set to 0 (i386) but kernel is x86_64
- No parsing of multiboot info structure passed by bootloader

## Missing Critical Features

### Essential for a working kernel:

1. Long mode setup - Paging tables (PML4, PDPT, PD, PT) and CR0/CR3/CR4 configuration
2. Proper multiboot2 handling - Parse memory map, modules, framebuffer info
3. PIC initialization - Remap IRQs, set masks (currently uninitialized)
4. Individual ISR stubs - One per interrupt with vector number
5. Page fault handler - Critical for debugging
6. Real VMM - Page table management, mapping/unmapping
7. Proper allocator - At least a free-list allocator

### Nice to have:

1. Timer (PIT/APIC) - For scheduling
2. Keyboard driver - User input
3. Basic syscalls - For future userspace
4. CPUID detection - Verify CPU features
5. Assertions/debug macros - Better debugging
6. Stack traces - For panic handler
7. Unit tests - Verify components work

### Improvements Needed

1. Boot sequence: Implement proper 32→64 bit transition
2. Build system: Fix for Zig 0.15.x compatibility
3. Error handling: Add proper error types and handling throughout
4. Documentation: Add module-level docs explaining each component
5. Testing: Add integration tests that can run in QEMU
6. Logging: Structured logging system (levels: DEBUG, INFO, WARN, ERROR)
