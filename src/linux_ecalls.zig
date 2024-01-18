//!Implementation for some basic linux ecalls

var err_buff: [128]u8 = [_]u8{0} ** 128;

pub fn ecall(vm: *Hart) Hart.InterruptResult {
    const code_register = Hart.AbiRegister.a7;

    const ecall_code: ECallCode = @enumFromInt(vm.registers[@intFromEnum(code_register)]);

    std.log.info("linux ecall: ", .{});

    switch (ecall_code) {
        .write => {
            const pointer = vm.registers[@intFromEnum(Hart.AbiRegister.a6)];
            const file_descriptor = vm.registers[@intFromEnum(Hart.AbiRegister.a0)];
            const len = vm.registers[@intFromEnum(Hart.AbiRegister.a2)];

            // const string_begin: [*]u8 = @ptrFromInt(pointer + 12832);
            const string_begin: [*]u8 = @ptrFromInt(pointer + 0);

            std.log.info("write_output (fd = {}): ptr = 0x{x}, len = {} not_sure = {s}, (num={any})", .{
                file_descriptor,
                pointer,
                len,
                string_begin[0..len],
                string_begin[0..len],
            });

            vm.setRegister(@intFromEnum(Hart.AbiRegister.a3), @intFromPtr(&err_buff));

            //set error code
            vm.setRegister(@intFromEnum(Hart.AbiRegister.a5), 0);
        },
        .exit => {
            const error_code = vm.registers[@intFromEnum(Hart.AbiRegister.a0)];

            std.log.info("riscv script exited with code 0x{x}", .{error_code});

            return .halt;
        },
        .print_int => {
            const int = vm.registers[@intFromEnum(Hart.AbiRegister.a0)];

            std.log.info("print_int: {}", .{int});
        },
        .gimme_a_number => {
            vm.registers[@intFromEnum(Hart.AbiRegister.a0)] = 40;
        },
        _ => {
            std.log.info("script tried to execute unknown/unimplemented syscall {}", .{ecall_code});

            for (vm.registers, 0..) |value, register| {
                std.log.info("x{} = 0x{x}", .{ register, value });
            }

            @panic("Unimplemented ecall");
        },
    }

    return .pass;
}

pub const ECallCode = enum(u16) {
    exit = 93,
    write = 64,

    //temporary debugging ecalls, not linux ones
    print_int = 1024,
    gimme_a_number = 1025,
    _,
};

const std = @import("std");
const Hart = @import("Hart.zig");
