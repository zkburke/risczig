// pub fn main() void {
//     // _ = std.os.write(std.os.STDOUT_FILENO, "Hello, world!") catch unreachable;

//     std.os.exit(0);
// }

const global = "hello, world!!!!!!";

pub export fn _start() noreturn {
    _ = std.os.write(std.os.STDOUT_FILENO, global) catch unreachable;

    // const res = fib_iter(10);

    const res = fib(gimmeANumber());

    for (0..10) |_| printInt(res);

    std.os.exit(0);
}

fn fib_iter(x: u32) u32 {
    var result: u32 = x;

    for (1..x) |i| {
        result += x * @as(u32, @intCast(i));
    }

    return result;
}

fn fib(x: u32) u32 {
    //using plus cuz mul isn't implemented

    if (x == 1) return 1;
    if (x == 0) return 0;

    return x + fib(x - 1);
}

pub fn printInt(x: usize) void {
    _ = specialCall(1024, x);
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

const std = @import("std");
