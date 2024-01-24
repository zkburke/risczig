const std = @import("std");
const Hart = @import("Hart.zig");
const ElfLoader = @import("ElfLoader.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() != .leak);

    const allocator = gpa.allocator();

    const code = [_]u32{
        0x00112623,
        0x00812423,
        //lui x10, 306
        0x00132537,
        //addi a1, a0, 1
        0x00150593,
        //addi a1, a1, -2
        0xffe58593,
        //sub a0, a1, a2
        0x40c58533,
        //add a0, a1, a2
        0x00c58533,
        //and a0, a1, a2
        0x00c5f533,
        //or a0, a1, a2
        0x00c5e533,
        //andi a0, a0, 0x10
        0x01057513,
        //beq a0, a1, 50
        0x02b50963,
        //auipc ra, 0x00
        0x00000097,
        0x00000037,
    };
    _ = code; // autofix

    const loop_code = [_]u32{
        //addi x10, x0, 10 (mov x10, 10)
        0x00a00513,
        //ebreak
        0x00100073,
        //addi x10, x10, -1
        0xfff50513,
        //bne x10, x0, -2
        0xfe051fe3,

        //addi a2, x0, 0b1111110100

        //addi a7, x0, 2
        0x00200893,
        //addi a0, x0, 32
        0x02000513,
        //ecall
        0x00000073,
        0x3f400613,
        //ebreak
        0x00100073,
        //addi a5, x0, 69
        0x04500793,
        //sw a5, 0(a6)
        0x00f82023,
        //lw a5, 0(a6)
        0x00082783,
        //ebreak
        0x00100073,
        //mv a7, 1
        0x00100893,
        //mv a0, 37
        0x02500513,
        //ecall
        0x00000073,
        //mv a7, 0 (ecall: exit)
        0x000008b3,
        //ecall
        0x00000073,
    };
    _ = loop_code; // autofix

    const assembled_code = [_]u32{
        //mv      a1,s0,
        0x00040593,
        0x00112623,
        0x01010413,
        0x00558513,
        0x00558513,
        0x00012537,
    };
    _ = assembled_code; // autofix

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
    };

    var imported_symbol_addresses: [2]u64 = undefined;

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

    const mod_init_address: [*]const u32 = @ptrFromInt(imported_symbol_addresses[0]);
    const mod_deinit_address: [*]const u32 = @ptrFromInt(imported_symbol_addresses[1]);

    vm.setRegister(@intFromEnum(Hart.AbiRegister.sp), @intFromPtr(loaded_module.stack.ptr + loaded_module.stack.len));

    try vm.execute(
        .{
            .ecall_handler = linux_ecalls.ecall,
            .ebreak_handler = Handlers.ebreak,
            .debug_instructions = false,
        },
        entry_point,
    );

    vm.resetRegisters();
    vm.setRegister(@intFromEnum(Hart.AbiRegister.sp), @intFromPtr(loaded_module.stack.ptr + loaded_module.stack.len));

    try vm.execute(
        .{
            .ecall_handler = linux_ecalls.ecall,
            .ebreak_handler = Handlers.ebreak,
        },
        mod_init_address,
    );

    vm.resetRegisters();
    vm.setRegister(@intFromEnum(Hart.AbiRegister.sp), @intFromPtr(loaded_module.stack.ptr + loaded_module.stack.len));

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

fn ImportProceduresFromStruct(comptime namespace: anytype) type {
    const Entry = struct { []const u8, *const Hart.NativeCall };
    var kv_list: []const Entry = &.{};

    for (@typeInfo(namespace).Struct.decls) |decl| {
        const exported_name = functionNameStem(decl.name);

        kv_list = kv_list ++ [_]Entry{
            .{ exported_name, &native_abi.nativeCallWrapper(@field(namespace, decl.name)) },
        };
    }

    return std.ComptimeStringMap(*const Hart.NativeCall, kv_list);
}

///Native api exposed to scripts
pub const natives = struct {
    pub fn puts(string: [*:0]const u8) callconv(.C) void {
        _ = std.io.getStdErr().write(std.mem.span(string)) catch unreachable;
        _ = std.io.getStdErr().write("\n") catch unreachable;
    }

    pub fn printf(hart: *const Hart, format: [*:0]const u8) callconv(.C) void {
        // _ = std.io.getStdErr().write(std.mem.span(format)) catch unreachable;
        defer _ = std.io.getStdErr().write("\n") catch unreachable;

        const format_slice = std.mem.span(format);

        var state: enum {
            start,
            print_variable,
        } = .start;

        //eg: printf("hello %s");

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

fn nativePuts(string: [*:0]const u8) callconv(.C) void {
    _ = std.io.getStdErr().write(std.mem.span(string)) catch unreachable;
    _ = std.io.getStdErr().write("\n") catch unreachable;
}

fn nativePrintf(hart: *const Hart, format: [*:0]const u8) callconv(.C) void {
    _ = hart; // autofix
    _ = std.io.getStdErr().write(std.mem.span(format)) catch unreachable;
    _ = std.io.getStdErr().write("\n") catch unreachable;
}

fn testNativeCall(x: u32) callconv(.C) void {
    std.log.info("testNativeCall: x = {}", .{x});
}

const native_abi = @import("native_abi.zig");
const linux_ecalls = @import("linux_ecalls.zig");
