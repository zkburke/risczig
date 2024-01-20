//!Program for loading and running tests from risc-v tests and running them with risczig

pub fn main() !void {
    var process_args = std.process.args();

    _ = process_args.next();

    const test_binary_path = process_args.next().?;

    std.log.info("Hello from vm test runner! test = {s}", .{test_binary_path});

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const file = try std.fs.cwd().openFile(test_binary_path, .{});

    const elf_data = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(elf_data);
    file.close();

    const loaded_module = try risczig.ElfLoader.load(
        allocator,
        elf_data,
        null,
        &.{},
        &.{},
    );

    const entry_point_address: [*]const u32 = @alignCast(@ptrCast(loaded_module.image.ptr + loaded_module.entry_point));

    var hart = risczig.Hart.init();
    defer hart.deinit();

    hart.setRegister(@intFromEnum(risczig.Hart.AbiRegister.sp), @intFromPtr(entry_point_address));

    try hart.execute(
        .{
            .ecall_handler = ecall,
        },
        entry_point_address,
    );
}

fn ecall(hart: *risczig.Hart) risczig.Hart.InterruptResult {
    const syscall = hart.registers[17];
    const a0 = hart.registers[10];

    switch (syscall) {
        //exit
        93 => {
            const exit_code: u8 = @truncate(a0);

            std.log.info("Exited with code 0x{x}", .{exit_code});

            switch (exit_code) {
                //success
                0 => {},
                else => {
                    std.os.exit(exit_code);
                },
            }

            return .halt;
        },
        else => unreachable,
    }

    return .pass;
}

pub const std_options = struct {
    pub const log_level = std.log.Level.err;
};

const std = @import("std");
const risczig = @import("risczig");
