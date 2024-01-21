const global = "hello, world!!!!!!";

extern fn lol() callconv(.C) u32;

const TestNativeCallFn = fn (x: u32) callconv(.C) void;

extern fn testNativeCall(x: u32) callconv(.C) void;
extern fn puts(string: [*:0]const u8) callconv(.C) void;

extern var funny_value: u32;

const log = std.log.scoped(.riscv_script);

export fn modInit() void {
    log.info("Hello from modInit! initial funny_value = {}", .{funny_value});

    funny_value += 13;
}

export fn modDeinit() void {
    log.info("Hello from modDenit! final funny_value = {}", .{funny_value});

    testNativeCall(funny_value);
}

pub export fn _start() void {
    log.info("Hello from _start! initial funny_value = {}", .{funny_value});

    log.err("{s}", .{global});

    const nul_addr: *u32 = if (funny_value == 21) undefined else &funny_value;

    nul_addr.* = 0;

    const fib_res: i32 = @intCast(fib(10));

    log.err("lol: fib_res = {}", .{fib_res});

    const res = factorial(@intCast(gimmeANumber()));

    log.err("double lol: fact_res = {}", .{res});

    testNativeCall(funny_value);

    const c_return_val = lol();

    testNativeCall(funny_value);

    puts("Hello, world from zig");

    log.err("c_return_val = {}", .{c_return_val});

    log.err("@returnAddress() = {}", .{@returnAddress()});

    printInt(res + fib_res);

    printInt(@divTrunc(res, zero(0)));

    for (3..10) |_| printInt(res);

    std.os.exit(0);
}

export fn zprint(str: [*:0]const u8) void {
    log.err("c string: {s}", .{std.mem.span(str)});
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
    log.err("printInt = {}", .{x});
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
        const level_txt = comptime message_level.asText();
        const prefix2 = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";

        var print_buffer: [10 * 1024]u8 = undefined;

        const output = std.fmt.bufPrint(&print_buffer, level_txt ++ prefix2 ++ format ++ "\n", args) catch return;

        _ = std.os.write(std.os.STDOUT_FILENO, output) catch return;

        // const stderr = std.io.getStdErr().writer();
        // stderr.print(level_txt ++ prefix2 ++ format ++ "\n", args) catch return;
    }
};

pub fn panic(msg: []const u8, stacktrace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    // std.log.info("panic: {s}", .{msg});
    // std.log.info("stacktrace = {*}", .{stacktrace});

    _ = std.io.getStdErr().write("panic: ") catch 0;
    _ = std.io.getStdErr().write(msg) catch 0;
    _ = std.io.getStdErr().write("\n") catch 0;

    _ = stacktrace;
    if (false) {
        var stack_trace: std.builtin.StackTrace = undefined;

        std.debug.captureStackTrace(ret_addr, &stack_trace);

        @breakpoint();

        var buffer_writer: std.io.FixedBufferStream([1024]u8) = undefined;

        const writer = buffer_writer.writer();

        var fixed_buffer: [1024]u8 = undefined;

        var fba = std.heap.FixedBufferAllocator.init(&fixed_buffer);

        var arena = std.heap.ArenaAllocator.init(fba.allocator());
        defer arena.deinit();

        const tty_config: std.io.tty.Config = .no_color;

        _ = tty_config;

        writer.writeAll("\n") catch unreachable;

        // std.debug.writeStackTrace(stack_trace, writer, arena.allocator(), debug_info, tty_config) catch |err| {
        //     writer.print("Unable to print stack trace: {s}\n", .{@errorName(err)}) catch unreachable;
        // };

        // std.debug.dumpStackTrace(stack_trace);
        // stack_trace.format("", .{}, buffer_writer.writer()) catch {
        //     std.os.exit(255);
        // };
    }

    std.os.exit(1);
}

const std = @import("std");
