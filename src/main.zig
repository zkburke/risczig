const std = @import("std");
const Vm = @import("Vm.zig");

pub fn main() !void {
    // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});

    // stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    try stdout.print("Run `zig build test` to run the tests.\n", .{});

    try bw.flush(); // don't forget to flush!

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
        pub fn ecall(vm: *Vm) Vm.InterruptResult {
            const syscall_register = Vm.AbiRegister.a7;

            const ecall_code = vm.registers[@intFromEnum(syscall_register)];

            std.log.info("ecall", .{});

            switch (ecall_code) {
                //example exit
                0 => {
                    std.log.info("ecall: exit", .{});
                    return .halt;
                },
                //putchar example
                1 => {
                    std.log.info("ecall: putchar: {c}", .{@as(u8, @intCast(vm.registers[@intFromEnum(Vm.AbiRegister.a0)]))});
                },
                else => unreachable,
            }

            return .pass;
        }

        pub fn ebreak(vm: *Vm) Vm.InterruptResult {
            for (vm.registers[0..16], 0..) |value, register| {
                std.log.info("x{} = {}", .{ register, value });
            }

            return .pass;
        }
    };

    var vm = Vm.init();
    defer vm.deinit();

    vm.execute(
        .{
            .ecall_handler = Handlers.ecall,
            .ebreak_handler = Handlers.ebreak,
        },
        &loop_code,
    );
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
