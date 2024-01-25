pub fn main() !void {
    var cli_args = std.process.args();

    _ = cli_args.skip();

    const iterations_string = cli_args.next().?;

    const iterations = try std.fmt.parseInt(u64, iterations_string, 10);

    std.log.info("Hello, benchmark", .{});

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const elf_file = try std.fs.cwd().readFileAlloc(allocator, "zig-out/benchmark/riscv/factorial/libfactorial.so", std.math.maxInt(u64));
    defer allocator.free(elf_file);

    const module = try risczig.ElfLoader.load(
        allocator,
        elf_file,
        null,
        &.{},
        &.{},
    );
    defer allocator.free(module.image);
    defer allocator.free(module.stack);

    var hart = risczig.Hart.init();
    defer hart.deinit();

    const entry_point: [*]const u32 = @ptrFromInt(@intFromPtr(module.image.ptr) + module.entry_point);

    //Input to the pure function
    const input: u64 = if (std.time.timestamp() > 3) 10 else 32;

    //Number of times the procedure is called
    //This measures call overhead
    const call_iterations: u64 = iterations;

    //Canonical test
    const native_result = shared_factorial.factorialRecursive(input);

    var native_time: i128 = 0;
    var interpreter_time: i128 = 0;

    {
        const time_begin = std.time.nanoTimestamp();
        defer {
            const time_end = std.time.nanoTimestamp();

            const time_elapsed = time_end - time_begin;

            native_time = time_elapsed;
        }

        for (0..call_iterations) |_| {
            // const iter_result = shared_factorial.factorialRecursive(input);

            _ = @call(.never_inline, shared_factorial.factorialRecursive, .{input});
        }
    }

    hart.setRegister(@intFromEnum(risczig.Hart.AbiRegister.sp), @intFromPtr(module.stack.ptr + module.stack.len));

    {
        const time_begin = std.time.nanoTimestamp();
        defer {
            const time_end = std.time.nanoTimestamp();

            const time_elapsed = time_end - time_begin;

            interpreter_time = time_elapsed;
        }

        for (0..call_iterations) |_| {
            hart.setRegister(@intFromEnum(risczig.Hart.AbiRegister.a0), input);

            try hart.execute(
                .{
                    .debug_instructions = false,
                    .handle_traps = false,
                },
                entry_point,
            );
        }
    }

    std.log.info("registers = {any}", .{hart.registers});

    std.debug.assert(hart.registers[@intFromEnum(risczig.Hart.AbiRegister.a0)] == native_result);

    std.log.info("native time = {}", .{native_time});
    std.log.info("interpreter_time time = {}", .{interpreter_time});

    const ratio = @as(f64, @floatFromInt(interpreter_time)) / @as(f64, @floatFromInt(native_time));

    std.log.info("interp:native ratio = {d}", .{ratio});
}

pub const std_options = struct {
    pub const log_level: std.log.Level = .debug;
};

const shared_factorial = @import("shared/numeric/factorial.zig");

const std = @import("std");
const risczig = @import("risczig");
