const global = "hello, world!!!!!!";

extern fn lol() callconv(.C) u32;

const TestNativeCallFn = fn (x: u32) callconv(.C) void;

extern fn testNativeCall(x: u32) callconv(.C) void;
extern fn puts(string: [*:0]const u8) callconv(.C) void;

extern var funny_value: u32;

export fn modInit() void {
    std.log.info("Hello from modInit!", .{});

    testNativeCall(67);
}

export fn modDeinit() void {
    std.log.info("Hello from modDenit!", .{});

    testNativeCall(4);
}

pub export fn _start() void {
    std.log.err("{s}", .{global});

    const fib_res: i32 = @intCast(fib(10));

    std.log.err("lol: fib_res = {}", .{fib_res});

    const res = factorial(@intCast(gimmeANumber()));

    std.log.err("double lol: fact_res = {}", .{res});

    // const native_call_address: usize = if (zero(res) == 0) 0x00000000_00000001 else 0;
    const native_call_address: usize = specialCall(1026, 0);

    {
        @setRuntimeSafety(false);

        const native_call_test: *const TestNativeCallFn = @ptrFromInt(native_call_address);

        native_call_test(9 + 10);
    }

    testNativeCall(21);

    const c_return_val = lol();

    puts("Hello, world from zig");

    std.log.err("c_return_val = {}", .{c_return_val});

    std.log.err("@returnAddress() = {}", .{@returnAddress()});

    printInt(res + fib_res);

    if (true) unreachable;

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
        const level_txt = comptime message_level.asText();
        const prefix2 = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";

        var print_buffer: [10 * 1024]u8 = undefined;

        const output = std.fmt.bufPrint(&print_buffer, level_txt ++ prefix2 ++ format ++ "\n", args) catch return;

        _ = std.os.write(std.os.STDOUT_FILENO, output) catch return;
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
