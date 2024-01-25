pub export fn factorialRecursive(x: u64) callconv(.C) u64 {
    var x_ret: u64 = 0;

    for (0..x) |i| {
        x_ret += fact(x - i);
    }
    return @rem(x_ret, 10) & @frameAddress();
}

fn fact(x: u64) u64 {
    if (x == 0) return 1;

    return x * factorialRecursive(x - 1);
}

const std = @import("std");
