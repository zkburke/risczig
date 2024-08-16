pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() != .leak);

    const allocator = gpa.allocator();

    const Handlers = struct {
        pub fn ebreak(vm: *Hart) Hart.InterruptResult {
            std.log.info("riscv script triggered breakpoint: pc = 0x{x}", .{@intFromPtr(vm.program_counter)});

            for (vm.registers, 0..) |value, register| {
                std.log.info("x{} = 0x{x}", .{ register, value });
            }

            return .halt;
        }
    };

    const riscv_script_file = try std.fs.cwd().openFile("zig-out/lib/libriscv_script.so", .{});

    const elf_data = try riscv_script_file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(elf_data);
    riscv_script_file.close();

    const native_procedures = ImportProceduresFromStruct(natives);

    //Procedures we want to import from the script
    const imported_symbol_names = [_][:0]const u8{
        "mod_init",
        "mod_deinit",
        "modInit",
    };

    var imported_symbol_addresses: [3]u64 = undefined;

    const Imports = struct {
        zig_mod_init: riscz.ProcedureAddress(fn () callconv(.C) void),
        c_mod_init: ?riscz.ProcedureAddress(fn () callconv(.C) void) = null,
    };
    _ = Imports; // autofix

    var loaded_module = try ElfLoader.load(
        allocator,
        elf_data,
        native_procedures,
        &imported_symbol_names,
        &imported_symbol_addresses,
    );
    defer ElfLoader.unload(&loaded_module, allocator);

    std.log.info("imported_symbol_addresses = {x}", .{imported_symbol_addresses});

    var vm = Hart.init();
    defer vm.deinit();

    //The entry point specified in the elf header
    const entry_point: [*]const u32 = @alignCast(@ptrCast(&loaded_module.image[loaded_module.entry_point]));

    const mod_deinit_address: [*]const u32 = @ptrFromInt(imported_symbol_addresses[1]);

    vm.writeRegister(@intFromEnum(Hart.AbiRegister.sp), @intFromPtr(loaded_module.stack.ptr + loaded_module.stack.len));

    try vm.execute(
        .{
            .ecall_handler = linux_ecalls.ecall,
            .ebreak_handler = Handlers.ebreak,
            .debug_instructions = false,
            .enable_f_extension = false,
            .enable_a_extension = false,
            .enable_m_extension = true,
        },
        entry_point,
    );

    const execute_config = Hart.ExecuteConfig{
        .ecall_handler = linux_ecalls.ecall,
        .ebreak_handler = Handlers.ebreak,
        .debug_instructions = false,
        .handle_traps = false,
    };

    const ModInitResult = enum(u8) {
        succeed = 0,
        fail = 1,
        _,
    };

    const zig_mod_init_address: riscz.ProcedureAddress(fn () callconv(.C) ModInitResult) = .{ .address = imported_symbol_addresses[2] };
    const mod_init_address: riscz.ProcedureAddress(fn (ctx_value: u32) callconv(.C) u32) = .{ .address = imported_symbol_addresses[0] };

    vm.resetRegisters();
    vm.writeRegister(@intFromEnum(Hart.AbiRegister.sp), @intFromPtr(loaded_module.stack.ptr + loaded_module.stack.len));

    switch (try riscz.callProcedure(&vm, execute_config, zig_mod_init_address, .{})) {
        .succeed => {
            std.log.info("modInit succeeded", .{});
        },
        .fail => {
            std.log.info("modInit failed", .{});
        },
        _ => unreachable,
    }

    vm.resetRegisters();
    vm.writeRegister(@intFromEnum(Hart.AbiRegister.sp), @intFromPtr(loaded_module.stack.ptr + loaded_module.stack.len));

    const mod_init_res = try riscz.callProcedure(&vm, execute_config, mod_init_address, .{98});

    std.log.info("mod_init_res = {}", .{mod_init_res});

    vm.resetRegisters();
    vm.writeRegister(@intFromEnum(Hart.AbiRegister.sp), @intFromPtr(loaded_module.stack.ptr + loaded_module.stack.len));

    try vm.execute(
        .{
            .ecall_handler = linux_ecalls.ecall,
            .ebreak_handler = Handlers.ebreak,
            .debug_instructions = false,
            .handle_traps = false,
        },
        mod_deinit_address,
    );
}

fn functionNameStem(path: []const u8) []const u8 {
    const index = std.mem.lastIndexOfScalar(u8, path, '.') orelse return path[0..];
    if (index == 0) return path;
    return path[index..];
}

fn ImportProceduresFromStruct(comptime namespace: anytype) std.StaticStringMap(*const Hart.NativeCall) {
    const Entry = struct { []const u8, *const Hart.NativeCall };
    comptime var kv_list: []const Entry = &.{};

    comptime {
        for (@typeInfo(namespace).Struct.decls) |decl| {
            const exported_name = functionNameStem(decl.name);

            kv_list = kv_list ++ [_]Entry{
                .{ exported_name, &abi.nativeCallWrapper(@field(namespace, decl.name)) },
            };
        }
    }

    return std.StaticStringMap(*const Hart.NativeCall).initComptime(kv_list);
}

///Native api exposed to scripts
pub const natives = struct {
    pub fn puts(string: [*:0]const u8) callconv(.C) void {
        _ = std.io.getStdErr().write(std.mem.span(string)) catch unreachable;
        _ = std.io.getStdErr().write("\n") catch unreachable;
    }

    pub fn printf(hart: *const Hart, format: [*:0]const u8) callconv(.C) void {
        defer _ = std.io.getStdErr().write("\n") catch unreachable;

        const format_slice = std.mem.span(format);

        var state: enum {
            start,
            print_variable,
        } = .start;

        var vararg_start_register: u5 = @intFromEnum(Hart.AbiRegister.a1);

        for (format_slice, 0..) |char, index| {
            _ = index; // autofix

            switch (state) {
                .start => {
                    switch (char) {
                        '%' => state = .print_variable,
                        else => {
                            _ = std.io.getStdErr().write(&[_]u8{char}) catch unreachable;
                        },
                    }
                },
                .print_variable => {
                    switch (char) {
                        'i' => {
                            const vararg_register_value = hart.registers[vararg_start_register];
                            vararg_start_register += 1;

                            const value: u32 = @truncate(vararg_register_value);

                            var format_buffer: [256]u8 = undefined;

                            const print_out = std.fmt.bufPrint(&format_buffer, "{}", .{value}) catch unreachable;

                            _ = std.io.getStdErr().write(print_out) catch unreachable;
                        },
                        'u' => unreachable,
                        'd' => unreachable,
                        's' => {
                            const vararg_register_value = hart.registers[vararg_start_register];
                            vararg_start_register += 1;

                            const value: [*:0]const u8 = @ptrFromInt(vararg_register_value);

                            _ = std.io.getStdErr().write(std.mem.span(value)) catch unreachable;
                        },
                        'c' => unreachable,
                        else => {
                            _ = std.io.getStdErr().write(&[_]u8{char}) catch unreachable;

                            state = .start;
                        },
                    }
                },
            }
        }
    }

    pub fn native_call(x: u32) callconv(.C) void {
        std.log.info("testNativeCall: x = {}", .{x});
    }
};

const std = @import("std");
const riscz = @import("riscz");
const linux_ecalls = @import("linux_ecalls.zig");
const Hart = riscz.Hart;
const ElfLoader = riscz.ElfLoader;
const abi = riscz.abi;
