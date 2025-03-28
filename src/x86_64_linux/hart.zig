pub const ExecuteBeginContext = struct {
    old_sigsegv_action: std.posix.Sigaction,
};

///This MUST be inlined into execute in order for setjmp to work
pub inline fn executeBegin(hart: *Hart, comptime config: Hart.ExecuteConfig) Hart.ExecuteError!ExecuteBeginContext {
    _ = hart;

    //This is a unstructured control flow from a signal handler, to handle segfaults
    //We should also set this to unlikely when/if such a mechanism is introduced to zig
    if (config.handle_traps and segfault_handling.set_jump(&segfault_handling.segfault_jump_buffer)) {
        return error.MemoryAccessViolation;
    }

    var old_sigsegv_action: std.posix.Sigaction = undefined;

    //Set underlying trap handlers to catch exceptions generated by riscv instructions
    if (config.handle_traps) std.posix.sigaction(
        std.posix.SIG.SEGV,
        &.{ .handler = .{ .sigaction = &segfault_handling.segfaultHandler }, .flags = undefined, .mask = undefined },
        &old_sigsegv_action,
    );

    const context = ExecuteBeginContext{
        .old_sigsegv_action = old_sigsegv_action,
    };

    return context;
}

pub inline fn executeEnd(
    hart: *Hart,
    comptime config: Hart.ExecuteConfig,
    context: *ExecuteBeginContext,
) void {
    _ = hart;
    if (config.handle_traps) {
        std.posix.sigaction(std.posix.SIG.SEGV, &context.old_sigsegv_action, null);
    }
}

//Struct for holding segfault handling state
const segfault_handling = struct {
    ///Buffer holding saved register state
    const JumpBuffer = extern struct {
        a: u64,
        b: u64,
        c: u64,
        d: u64,
        e: u64,
        f: u64,
        g: u64,
        h: u64,
    };

    // pub extern fn set_jump(buf: *JumpBuffer) callconv(.C) bool;
    pub fn set_jump(_: *JumpBuffer) bool {
        return false;
    }

    extern fn long_jump(buf: *JumpBuffer, _: bool) callconv(.C) void;

    pub var segfault_jump_buffer: JumpBuffer = undefined;

    comptime {
        asm (@embedFile("long_jump.S"));
    }

    fn segfaultHandler(_: c_int, signal_info: *const std.posix.siginfo_t, _: ?*const anyopaque) callconv(.C) void {
        _ = signal_info;

        long_jump(&segfault_jump_buffer, true);

        unreachable;
    }
};

const Hart = @import("../Hart.zig");
const std = @import("std");
