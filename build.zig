const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .freestanding,
        .abi = .none,
    });

    const optimize = b.standardOptimizeOption(.{});

    const kernel = b.addExecutable(.{
        .name = "tessera.elf",
        .root_module = b.createModule(.{
            .root_source_file =  b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    kernel.setLinkerScript(b.path("linker.ld"));
    kernel.addAssemblyFile(b.path("src/arch/x86_64/isr.S"));
    kernel.addAssemblyFile(b.path("src/boot/boot.S"));

    b.installArtifact(kernel);


    // Create the output directory (iso/boot)
    const iso_dir = b.addSystemCommand(&.{"mkdir", "-p", "iso/boot/grub"});

    const copy_kernel = b.addSystemCommand(&.{
        "cp",
        b.getInstallPath(.bin, "tessera.elf"),
        "iso/boot/tessera.elf"
    });

    copy_kernel.step.dependOn(&kernel.step);
    copy_kernel.step.dependOn(&iso_dir.step);

    const copy_grub_cfg = b.addSystemCommand(&.{
        "cp",
        "grub.cfg",
        "iso/boot/grub/grub.cfg"
    });
    copy_grub_cfg.step.dependOn(&iso_dir.step);

    const make_iso = b.addSystemCommand(&.{
        "grub-mkrescue",
        "-o",
        "zig-out/tessera.iso",
        "iso/"
    });
    make_iso.step.dependOn(&copy_kernel.step);
    make_iso.step.dependOn(&copy_grub_cfg.step);

    b.default_step.dependOn(&make_iso.step);
}
