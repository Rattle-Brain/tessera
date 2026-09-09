const std = @import("std");

pub fn build(b: *std.Build) void {
    // A freestanding x86_64 kernel.
    //
    // SSE/MMX/AVX are subtracted from the target so that LLVM never emits xmm
    // instructions. This matters for two reasons:
    //   1. GRUB hands control over with CR4.OSFXSR clear, so any SSE
    //      instruction would raise #UD before we get a chance to print
    //      anything.
    //   2. `isr_common_stub` only saves the general purpose registers. If
    //      kernel code used xmm registers, an interrupt would silently clobber
    //      the interrupted context.
    // `soft_float` lets LLVM lower the (currently unused) float operations
    // without a vector unit.
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .freestanding,
        .abi = .none,
        .cpu_model = .{ .explicit = &std.Target.x86.cpu.x86_64 },
        .cpu_features_sub = std.Target.x86.featureSet(&.{ .mmx, .sse, .sse2, .avx, .avx2, .avx512f }),
        .cpu_features_add = std.Target.x86.featureSet(&.{.soft_float}),
    });

    const optimize = b.standardOptimizeOption(.{});

    const kernel_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        // The System V red zone is unusable in a kernel: an interrupt pushes
        // its frame right over it, corrupting the interrupted leaf function.
        .red_zone = false,
        // A multiboot kernel is loaded at a fixed address and nothing applies
        // dynamic relocations for us, so no PIC/GOT indirection.
        .pic = false,
        // Nothing unwinds in the kernel; keeps .eh_frame out of the image.
        .unwind_tables = .none,
        .omit_frame_pointer = false,
        .single_threaded = true,
        .stack_check = false,
        .stack_protector = false,
        .strip = false,
        // The UBSan runtime is compiled for the *host* std, uses f128 and SSE
        // stores, and cannot be built for a soft-float freestanding target.
        .sanitize_c = .off,
    });

    kernel_mod.addAssemblyFile(b.path("src/boot/boot.S"));
    kernel_mod.addAssemblyFile(b.path("src/arch/x86_64/isr.S"));

    const kernel = b.addExecutable(.{
        .name = "tessera.elf",
        .root_module = kernel_mod,
        // Zig 0.16's self-hosted x86_64 backend cannot yet codegen a soft-float
        // freestanding target (it fails on f128 conversions and emits `movups
        // xmm0` despite SSE being disabled). LLVM handles it correctly.
        .use_llvm = true,
    });
    kernel.setLinkerScript(b.path("linker.ld"));
    // Safe because the linker script wraps the Multiboot headers in KEEP() —
    // nothing in the kernel references them, so GC would otherwise drop them.
    // Without this, all of compiler_rt (soft-float trig, complex division, ...)
    // stays linked in for no reason.
    kernel.link_gc_sections = true;

    b.installArtifact(kernel);

    // ---- zig build run: boot straight out of QEMU, no bootloader needed ----
    // boot.S carries a Multiboot 1 header alongside the Multiboot 2 one because
    // QEMU's built-in -kernel loader only implements Multiboot 1. That loader
    // also insists on an ELFCLASS32 file, so the kernel is repacked into a
    // 32-bit ELF container first (same segments, same entry point).
    const mb1image = b.addExecutable(.{
        .name = "mb1image",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/mb1image.zig"),
            .target = b.graph.host,
            .optimize = .Debug,
        }),
    });

    const repack = b.addRunArtifact(mb1image);
    repack.addFileArg(kernel.getEmittedBin());
    const kernel32 = repack.addOutputFileArg("tessera32.elf");

    const run = b.addSystemCommand(&.{ "qemu-system-x86_64", "-kernel" });
    run.addFileArg(kernel32);
    run.addArgs(&.{ "-m", "512M", "-serial", "stdio", "-no-reboot", "-no-shutdown" });
    if (b.args) |extra| run.addArgs(extra);
    b.step("run", "Boot the kernel in QEMU (no bootloader required)").dependOn(&run.step);

    // ---- zig build iso: GRUB rescue image (needs grub-mkrescue + xorriso) ----
    const iso_tree = b.addWriteFiles();
    _ = iso_tree.addCopyFile(kernel.getEmittedBin(), "boot/tessera.elf");
    _ = iso_tree.addCopyFile(b.path("grub.cfg"), "boot/grub/grub.cfg");

    // GRUB is packaged under different names (plain `grub-mkrescue` on most
    // Linux distros, `x86_64-elf-grub-mkrescue` from Homebrew).
    const grub_mkrescue = b.option(
        []const u8,
        "grub-mkrescue",
        "Name of the grub-mkrescue binary (default: grub-mkrescue)",
    ) orelse "grub-mkrescue";
    const mkrescue = b.addSystemCommand(&.{grub_mkrescue});
    mkrescue.addArg("-o");
    const iso_path = mkrescue.addOutputFileArg("tessera.iso");
    mkrescue.addDirectoryArg(iso_tree.getDirectory());

    const install_iso = b.addInstallFile(iso_path, "tessera.iso");
    const iso_step = b.step("iso", "Build a bootable GRUB ISO (requires grub-mkrescue and xorriso)");
    iso_step.dependOn(&install_iso.step);

    // ---- zig build run-iso: boot that ISO ----
    const run_iso = b.addSystemCommand(&.{ "qemu-system-x86_64", "-cdrom" });
    run_iso.addFileArg(iso_path);
    run_iso.addArgs(&.{ "-m", "512M", "-serial", "stdio", "-boot", "d", "-no-reboot", "-no-shutdown" });
    if (b.args) |extra| run_iso.addArgs(extra);
    b.step("run-iso", "Boot the GRUB ISO in QEMU").dependOn(&run_iso.step);

    // Default: just build and install the kernel. The ISO is opt-in because
    // grub-mkrescue is not available everywhere (notably macOS).
    b.getInstallStep().dependOn(&kernel.step);
}
