pub export fn _start() callconv(.C) noreturn {
    // std.os.write(std.os.STDOUT_FILENO, "Hello");
    const x = @frameAddress() + 5;

    if (x == 6) {
        unreachable;
    }

    unreachable;
}

const std = @import("std");
