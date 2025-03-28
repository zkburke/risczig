pub const Hart = @import("Hart.zig");
pub const ElfLoader = @import("ElfLoader.zig");
pub const abi = @import("abi.zig");

pub fn ProcedureAddress(comptime Prototype: type) type {
    return packed struct(u64) {
        address: u64,

        pub const prototype = Prototype;
    };
}

///Call a RISC-V proecedure
///Modelled after the @call builtin
pub inline fn callProcedure(
    hart: *Hart,
    comptime config: Hart.ExecuteConfig,
    procedure: anytype,
    args: anytype,
) Hart.ExecuteError!ReturnType(@TypeOf(procedure).prototype) {
    const FunctionType = @TypeOf(procedure).prototype;

    if (args.len != @typeInfo(FunctionType).@"fn".params.len) {
        @compileError("Missing args");
    }

    const parameter_abi_locations = comptime abi.getParameterLocations(FunctionType);

    inline for (args, 0..) |arg, index| {
        abi.storeParameter(hart, parameter_abi_locations[index], @TypeOf(arg), arg);
    }

    try hart.execute(config, @ptrFromInt(procedure.address));

    const return_abi_location = comptime abi.getReturnLocation(FunctionType) orelse return;

    return abi.loadReturnValue(hart, return_abi_location, ReturnType(FunctionType));
}

fn ReturnType(comptime procedure: type) type {
    return @typeInfo(procedure).@"fn".return_type.?;
}

const std = @import("std");
