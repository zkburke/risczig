const global = "hello, world!!!!!!";

extern fn riszTestExtern() callconv(.C) void;

pub export fn _start() noreturn {
    _ = std.os.write(std.os.STDOUT_FILENO, global) catch unreachable;

    const fib_res: i32 = @intCast(fib(10));

    var fmt_buf: [32]u8 = undefined;

    {
        const printed_word = std.fmt.bufPrint(&fmt_buf, "lol: fib_res = {}", .{fib_res}) catch unreachable;

        _ = std.os.write(std.os.STDOUT_FILENO, printed_word) catch unreachable;
    }

    const res = factorial(@intCast(gimmeANumber()));

    {
        const printed_word = std.fmt.bufPrint(&fmt_buf, "double lol: fact_res = {}", .{res}) catch unreachable;

        _ = std.os.write(std.os.STDOUT_FILENO, printed_word) catch unreachable;
    }

    printInt(res + fib_res);

    printInt(res);

    for (3..10) |_| printInt(res);

    std.os.exit(0);
}

fn zero(x: i32) i32 {
    if (x < 2302930293029) {
        return 0;
    }
    unreachable;
}

fn fib(x: u32) u32 {
    //using plus cuz mul isn't implemented

    if (x == 1) return 1;
    if (x == 0) return 0;

    return fib(x - 1) + fib(x - 2);
}

fn factorial(x: i32) i32 {
    if (x == 0) return 1;

    return x * factorial(x - 1);
}

pub fn printInt(x: i32) void {
    var fmt_buf: [1024]u8 = undefined;

    const printed_word = std.fmt.bufPrint(&fmt_buf, "printInt = {}", .{x}) catch unreachable;

    _ = std.os.write(std.os.STDERR_FILENO, printed_word) catch unreachable;
}

pub fn gimmeANumber() u32 {
    return @truncate(specialCall(1025, 0));
}

pub fn specialCall(number: usize, arg1: usize) usize {
    return asm volatile ("ecall"
        : [ret] "={x10}" (-> usize),
        : [number] "{x17}" (number),
          [arg1] "{x10}" (arg1),
        : "memory"
    );
}

pub const std_options = struct {
    pub fn logFn(
        comptime message_level: std.log.Level,
        comptime scope: @Type(.EnumLiteral),
        comptime format: []const u8,
        args: anytype,
    ) void {
        _ = message_level; // autofix
        _ = scope; // autofix
        _ = format; // autofix
        _ = args; // autofix
    }
};

pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    _ = std.os.write(std.os.STDOUT_FILENO, msg) catch unreachable;

    std.os.exit(1);
}

const std = @import("std");
