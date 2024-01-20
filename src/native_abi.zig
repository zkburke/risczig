//!Implementation of the standard ABI for native calls
//!Allows for callconv(.C) zig functions to be wrapped automatically at compile time

///Returns a native wrapper function for a callconv(.C) function
///Arguments must be representable in the ABI
pub fn nativeCallWrapper(comptime function: anytype) Hart.NativeCall {
    const function_info = @typeInfo(@TypeOf(function)).Fn;

    std.debug.assert(function_info.calling_convention == .C);

    const Args = std.meta.ArgsTuple(@TypeOf(function));

    //TODO: create some kind of map from Type.Fn.param to abi location

    const S = struct {
        pub fn native(hart: *Hart) void {
            var args: Args = undefined;

            inline for (function_info.params, 0..) |param, param_index| {
                @field(args, std.fmt.comptimePrint("{}", .{param_index})) = loadParameter(
                    hart,
                    param.type.?,
                    param_index,
                );
            }

            @call(.always_inline, function, args);

            //TODO: handle return
        }

        ///Loads parameter from well defined abi location
        pub fn loadParameter(
            hart: *Hart,
            comptime T: type,
            comptime param_index: comptime_int,
        ) T {
            const location = comptime mapParameterToLocation(param_index);

            switch (@typeInfo(T)) {
                .Pointer => {
                    std.debug.assert(location == .general_register);

                    switch (location) {
                        .general_register => |register| {
                            const register_value = hart.registers[@intFromEnum(register)];

                            return @ptrFromInt(register_value);
                        },
                        .stack => unreachable,
                    }
                },
                .Int => |integer_type| {
                    std.debug.assert(location == .general_register);

                    switch (location) {
                        .general_register => |register| {
                            const register_value: if (integer_type.signedness == .unsigned) u64 else i64 = @bitCast(hart.registers[@intFromEnum(register)]);

                            return @truncate(register_value);
                        },
                        .stack => unreachable,
                    }
                },
                else => @compileError("Type unsupported"),
            }

            unreachable;
        }

        pub fn mapParameterToLocation(
            comptime param_index: comptime_int,
        ) AbiLocation {
            var next_general_register: ?Hart.AbiRegister = .a0;

            var location: AbiLocation = undefined;

            //walk through arguments in order and allocate locations
            inline for (function_info.params[0 .. param_index + 1]) |other_param| {
                switch (@typeInfo(other_param.type.?)) {
                    .Pointer => {
                        location = .{ .general_register = next_general_register.? };

                        next_general_register = @enumFromInt(@intFromEnum(next_general_register.?) + 1);
                    },
                    .Int => {
                        location = .{ .general_register = next_general_register.? };

                        next_general_register = @enumFromInt(@intFromEnum(next_general_register.?) + 1);
                    },
                    else => @compileError("Type unsupported"),
                }
            }

            return location;
        }
    };

    return S.native;
}

///Represents the location where a (register sized or less) value can be loaded and stored from
pub const AbiLocation = union(enum) {
    general_register: Hart.AbiRegister,
    stack: struct {
        offset: i64,
    },
};

const Hart = @import("Hart.zig");
const std = @import("std");
