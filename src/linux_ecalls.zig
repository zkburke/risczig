//!Implementation for some basic linux ecalls

pub fn ecall(vm: *Hart) Hart.InterruptResult {
    const code_register = Hart.AbiRegister.a7;

    const ecall_code: ECallCode = @enumFromInt(vm.registers[@intFromEnum(code_register)]);

    switch (ecall_code) {
        .write => {
            const file_descriptor = vm.registers[@intFromEnum(Hart.AbiRegister.a0)];
            const pointer = vm.registers[@intFromEnum(Hart.AbiRegister.a1)];
            const len = vm.registers[@intFromEnum(Hart.AbiRegister.a2)];

            const string_begin: ?[*:0]u8 = @ptrFromInt(pointer);
            const string = string_begin.?[0..len];

            _ = switch (file_descriptor) {
                0 => @panic("Can't write to stdin"),
                1 => std.os.write(std.os.STDOUT_FILENO, string),
                2 => std.os.write(std.os.STDERR_FILENO, string),
                else => @panic("Invalid file descriptor"),
            } catch @panic("Write returned an error");

            // std.log.info("write_output (fd = {}): ptr = 0x{x}, len = {} not_sure = {s}", .{
            //     file_descriptor,
            //     pointer,
            //     len,
            //     string_begin.?[0..len],
            // });

            //set error code
            vm.setRegister(@intFromEnum(Hart.AbiRegister.a5), 0);
        },
        .exit => {
            const error_code = vm.registers[@intFromEnum(Hart.AbiRegister.a0)];

            std.log.info("riscv script exited with code 0x{x}", .{error_code});

            return .halt;
        },
        .rt_sigaction => {
            const signum = vm.registers[@intFromEnum(Hart.AbiRegister.a0)];

            switch (signum) {
                std.os.SIG.SEGV => {
                    std.log.info("ecall: rt_sigaction: signum = SEGV", .{});
                },
                std.os.SIG.BUS => {
                    std.log.info("ecall: rt_sigaction: signum = BUS", .{});
                },
                else => {
                    std.log.info("ecall: rt_sigaction: signum = {}", .{signum});
                },
            }

            return .pass;
        },
        .clock_gettime => {
            const a0 = &vm.registers[@intFromEnum(Hart.AbiRegister.a0)];

            a0.* = @bitCast(std.time.milliTimestamp());
        },
        //custom syscalls
        .gimme_a_number => {
            vm.registers[@intFromEnum(Hart.AbiRegister.a0)] = 5;
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
    rt_sigaction = 134,
    clock_gettime = 403,

    //temporary debugging ecalls, not linux ones
    gimme_a_number = 1025,
    _,
};

const std = @import("std");
const Hart = @import("Hart.zig");
