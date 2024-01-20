const global = "hello, world!!!!!!";

extern fn lol() callconv(.C) u32;

const TestNativeCallFn = fn (x: u32) callconv(.C) void;

extern fn testNativeCall(x: u32) callconv(.C) void;

extern var funny_value: u32;

pub export fn _start() void {
    std.log.err("{s}", .{global});

    const fib_res: i32 = @intCast(fib(10));

    std.log.err("lol: fib_res = {}", .{fib_res});

    const res = factorial(@intCast(gimmeANumber()));

    std.log.err("double lol: fact_res = {}", .{res});

    @breakpoint();

    // const native_call_address: usize = if (zero(res) == 0) 0x00000000_00000001 else 0;
    const native_call_address: usize = specialCall(1026, 0);

    {
        @setRuntimeSafety(false);

        const native_call_test: *const TestNativeCallFn = @ptrFromInt(native_call_address);

        native_call_test(9 + 10);
    }

    testNativeCall(21);

    const c_return_val = lol();

    std.log.err("c_return_val = {}", .{c_return_val});

    std.log.err("@returnAddress() = {}", .{@returnAddress()});

    printInt(res + fib_res);

    printInt(res);

    for (3..10) |_| printInt(res);

    std.os.exit(0);
}

export fn zprint(str: [*:0]const u8) void {
    std.log.err("c string: {s}", .{std.mem.span(str)});
}

fn zero(x: i32) i32 {
    if (x < 2302930293029) {
        return 0;
    }
    unreachable;
}

fn fib(x: u32) u32 {
    // std.log.err("@returnAddress() = {x}", .{@returnAddress()});

    if (x == 1) return 1;
    if (x == 0) return 0;

    return fib(x - 1) + fib(x - 2);
}

fn factorial(x: i32) i32 {
    if (x == 0) return 1;

    return x * factorial(x - 1);
}

pub fn printInt(x: i32) void {
    std.log.err("printInt = {}", .{x});
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
        _ = scope; // autofix

        var fmt_buf: [1024]u8 = undefined;

        _ = std.os.write(std.os.STDERR_FILENO, @tagName(message_level) ++ ": ") catch unreachable;

        const printed_word = std.fmt.bufPrint(&fmt_buf, format, args) catch unreachable;

        _ = std.os.write(std.os.STDERR_FILENO, printed_word) catch unreachable;
        _ = std.os.write(std.os.STDERR_FILENO, "\n") catch unreachable;
    }
};

pub fn panic(msg: []const u8, stacktrace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    _ = msg; // autofix
    _ = ret_addr; // autofix
    // std.log.info("panic: {s}", .{msg});

    if (stacktrace != null) {
        std.debug.dumpStackTrace(stacktrace.?.*);
    }

    std.os.exit(1);
}

const std = @import("std");
