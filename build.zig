const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const script_target = b.resolveTargetQuery(.{
        .cpu_arch = .riscv64,
        .abi = .musl,
        .os_tag = .linux,
        .cpu_features_sub = std.Target.riscv.featureSet(&.{
            .c,
        }),
    });

    const riscv_script = b.addExecutable(.{
        .name = "riscv_script",
        .root_source_file = .{ .path = "src/example/riscv_script.zig" },
        .target = script_target,
        .optimize = .Debug,
        .use_llvm = true,
        .link_libc = false,
        .single_threaded = true,
        .pic = true,
        .strip = true,
        .linkage = .static,
    });

    riscv_script.pie = true;

    b.installArtifact(riscv_script);

    const exe = b.addExecutable(.{
        .name = "riscz",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const lib_unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/root.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);
}
