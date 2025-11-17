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
}
