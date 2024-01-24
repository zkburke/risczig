//!Implementation of the standard ABI for native calls
//!Allows for callconv(.C) zig functions to be wrapped automatically at compile time

///Returns a native wrapper function for a callconv(.C) function
///Arguments must be representable in the ABI
pub fn nativeCallWrapper(comptime function: anytype) Hart.NativeCall {
    const function_info = @typeInfo(@TypeOf(function)).Fn;

    validateFunctionPrototype(function);

    const Args = std.meta.ArgsTuple(@TypeOf(function));

    //TODO: create some kind of map from Type.Fn.param to abi location

    const S = struct {
        pub fn native(hart: *Hart) void {
            var args: Args = undefined;

            inline for (function_info.params, 0..) |param, param_index| {
                switch (param.type.?) {
                    *const Hart, *Hart, Hart => {
                        @field(args, std.fmt.comptimePrint("{}", .{param_index})) = hart;
                    },
                    else => {
                        @field(args, std.fmt.comptimePrint("{}", .{param_index})) = loadParameter(
                            hart,
                            param.type.?,
                            param_index,
                        );
                    },
                }
            }

            const return_value = @call(.always_inline, function, args);

            //TODO: handle return
            switch (@TypeOf(return_value)) {
                void => {},
                else => {},
            }
        }

        ///Loads parameter from well defined abi location
        pub fn loadParameter(
            hart: *Hart,
            comptime T: type,
            comptime param_index: comptime_int,
        ) T {
            const location = comptime mapParameterToLocation(param_index);

            switch (T) {
                *Hart, *const Hart => hart,
                Hart => hart.*,
                else => {},
            }

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
                        if (other_param.type == *const Hart or other_param.type == *Hart) continue;

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

fn validateFunctionPrototype(comptime function: anytype) void {
    const function_info = @typeInfo(@TypeOf(function)).Fn;

    if (function_info.calling_convention != .C) {
        @compileError("Function can only use the C calling convention");
    }

    var hart_parameter_count = 0;

    inline for (function_info.params, 0..) |param, param_index| {
        _ = param_index; // autofix

        switch (param.type.?) {
            *Hart, *const Hart, Hart => {
                hart_parameter_count += 1;
            },
            else => {},
        }
    }

    if (hart_parameter_count > 1) {
        @compileError("Function can only have a single Hart parameter");
    }
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
