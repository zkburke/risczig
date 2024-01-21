const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const risczig_module = b.addModule("risczig", .{
        .root_source_file = .{ .path = b.pathFromRoot("src/root.zig") },
    });

    const script_target = b.resolveTargetQuery(.{
        .cpu_arch = .riscv64,
        .abi = .gnu,
        .os_tag = .linux,
        .cpu_features_sub = std.Target.riscv.featureSet(&.{
            .c,
        }),
    });

    const riscv_script = b.addSharedLibrary(.{
        .name = "riscv_script",
        .root_source_file = .{ .path = "src/example/riscv_script.zig" },
        .target = script_target,
        .optimize = .Debug,
        .use_llvm = true,
        .link_libc = false,
        .single_threaded = true,
        .pic = true,
        .strip = true,
        .error_tracing = true,
    });

    const asm_path = riscv_script.getEmittedAsm();

    const install_file = b.addInstallFile(asm_path, "asm.asm");

    b.getInstallStep().dependOn(&install_file.step);

    //link some c in as well
    riscv_script.addCSourceFile(.{
        .file = .{ .path = "src/example/riscv_script_c.c" },
    });

    //Question to self: is this required?
    // riscv_script.pie = true;

    b.installArtifact(riscv_script);

    if (false) {
        const riscv_script_c = b.addExecutable(.{
            .name = "riscv_script_c",
            .root_source_file = null,
            .target = script_target,
            .optimize = .Debug,
            .use_llvm = true,
            .single_threaded = true,
            .pic = true,
            .strip = false,
            .linkage = .static,
        });
        riscv_script_c.pie = true;

        riscv_script_c.addCSourceFile(.{
            .file = .{ .path = "src/example/riscv_script_c.c" },
        });

        b.installArtifact(riscv_script_c);
    }

    const exe = b.addExecutable(.{
        .name = "riscz",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
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

    const include_riscv_tests = b.option(bool, "include_riscv_tests", "Compile the risc-v-tests test suite") orelse false;

    //Compile All riscv-test assembly files into their own seperate objects
    //We *should* be able to use clang
    if (include_riscv_tests) {
        const test_runner = b.addExecutable(.{
            .name = "risczig_test_runner",
            .root_source_file = .{ .path = "test/vm/test_runner.zig" },
            .target = b.host,
            .optimize = .Debug,
        });

        test_runner.root_module.addImport("risczig", risczig_module);

        const test_riscv_target = b.resolveTargetQuery(.{
            .cpu_arch = .riscv64,
            .abi = .gnu,
            .os_tag = .freestanding,
            .cpu_features_sub = std.Target.riscv.featureSet(&.{
                .c,
            }),
        });

        const riscv_tests_path = "test/lib/riscv-tests/";

        const test_vms = [_][]const u8{
            "rv64ui/",
            "rv64um/",
        };

        for (test_vms) |test_vm_path| {
            const test_vm_path_from_root = b.pathJoin(&.{
                riscv_tests_path,
                "isa/",
                test_vm_path,
            });

            const test_vm_actual_path = b.pathFromRoot(test_vm_path_from_root);

            var test_vm_directory = try std.fs.openDirAbsolute(test_vm_actual_path, .{
                .iterate = true,
            });
            defer test_vm_directory.close();

            var directory_iterator = test_vm_directory.iterate();

            while (try directory_iterator.next()) |entry| {
                const assembly_sub_path = entry.name;

                if (std.mem.eql(u8, entry.name, "Makefrag")) {
                    continue;
                }

                const executable_name = std.fs.path.stem(assembly_sub_path);

                const assembly_test_executable = b.addExecutable(.{
                    .name = executable_name,
                    .target = test_riscv_target,
                    .optimize = .Debug,
                    .use_llvm = true,
                    .link_libc = false,
                    .single_threaded = true,
                    .pic = true,
                    .strip = true,
                    .error_tracing = false,
                });

                assembly_test_executable.addIncludePath(.{ .path = b.pathFromRoot(riscv_tests_path ++ "env/p/") });
                assembly_test_executable.addIncludePath(.{ .path = b.pathFromRoot(riscv_tests_path ++ "isa/macros/scalar/") });
                assembly_test_executable.setLinkerScript(.{ .path = b.pathFromRoot(riscv_tests_path ++ "env/p/link.ld") });

                const assembly_source_path = b.pathJoin(&.{
                    riscv_tests_path,
                    "isa/",
                    test_vm_path,
                    assembly_sub_path,
                });

                assembly_test_executable.addAssemblyFile(.{ .path = assembly_source_path });

                const install_directory = b.pathJoin(&.{
                    "test/",
                    test_vm_path,
                });

                const install_assembly = b.addInstallArtifact(assembly_test_executable, .{
                    .dest_dir = .{ .override = .{ .custom = install_directory } },
                });

                b.getInstallStep().dependOn(&install_assembly.step);

                test_step.dependOn(&install_assembly.step);

                const run_test_runner = b.addRunArtifact(test_runner);

                const test_binary_path = b.pathJoin(&.{
                    b.install_path,
                    install_assembly.dest_dir.?.custom,
                    install_assembly.dest_sub_path,
                });

                run_test_runner.addArg(b.pathFromRoot(test_binary_path));
                run_test_runner.step.dependOn(&install_assembly.step);

                test_step.dependOn(&run_test_runner.step);
            }
        }
    }
}
