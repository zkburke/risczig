//!Implementation of the standard ABI for riscv calls into/out from the VM.
//!Allows for callconv(.C) zig functions to be wrapped automatically at compile time

///Returns a native wrapper function for a callconv(.C) function
///Arguments must be representable in the ABI
pub fn nativeCallWrapper(comptime function: anytype) Hart.NativeCall {
    const function_info = @typeInfo(@TypeOf(function)).@"fn";

    validateFunctionPrototype(function);

    const Args = std.meta.ArgsTuple(@TypeOf(function));

    const S = struct {
        pub fn native(hart: *Hart) void {
            var args: Args = undefined;

            inline for (function_info.params, 0..) |param, param_index| {
                switch (param.type.?) {
                    *const Hart, *Hart, Hart => {
                        @field(args, std.fmt.comptimePrint("{}", .{param_index})) = hart;
                    },
                    else => {
                        const parameter_locations = comptime getParameterLocations(@TypeOf(function));

                        @field(args, std.fmt.comptimePrint("{}", .{param_index})) = loadParameter(
                            hart,
                            parameter_locations[param_index],
                            param.type.?,
                        );
                    },
                }
            }

            const call_modifier: std.builtin.CallModifier = switch (@import("builtin").mode) {
                .Debug, .ReleaseSmall => .auto,
                .ReleaseFast, .ReleaseSafe => .always_inline,
            };

            const return_value = @call(call_modifier, function, args);

            const return_location = (comptime getReturnLocation(@TypeOf(function))) orelse return;

            storeReturnValue(hart, return_location, @TypeOf(return_value), return_value);
        }
    };

    return S.native;
}

fn validateFunctionPrototype(comptime function: anytype) void {
    const function_info = @typeInfo(@TypeOf(function)).@"fn";

    if (function_info.calling_convention == .auto) {
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
///Works for integers, floats, pointers, enums
pub const AbiLocation = union(enum) {
    general_register: Hart.AbiRegister,
    float_register: Hart.FloatAbiRegister,
    stack: struct {
        ///Offset from the beginning of the stack frame
        offset: i64,
    },
};

pub fn getParameterLocations(comptime function_type: anytype) []const AbiLocation {
    const function_info = @typeInfo(function_type).@"fn";

    std.debug.assert(!function_info.is_generic);
    std.debug.assert(!function_info.is_var_args);

    var next_general_register: ?Hart.AbiRegister = .a0;

    var locations: []const AbiLocation = &[_]AbiLocation{};

    //walk through arguments in order and allocate locations
    inline for (function_info.params) |param| {
        var location: AbiLocation = undefined;

        const param_size = @sizeOf(param.type.?);

        std.debug.assert(param_size <= @sizeOf(u64));

        switch (@typeInfo(param.type.?)) {
            .pointer => {
                if (param.type == *const Hart or param.type == *Hart) {
                    locations = locations ++ &[_]AbiLocation{location};

                    continue;
                }

                location = .{ .general_register = next_general_register.? };

                next_general_register = @enumFromInt(@intFromEnum(next_general_register.?) + 1);
            },
            .int, .@"enum", .bool => {
                location = .{ .general_register = next_general_register.? };

                next_general_register = @enumFromInt(@intFromEnum(next_general_register.?) + 1);
            },
            .float => {
                @compileError("Floats are unsupported");
            },
            else => @compileError("Type unsupported"),
        }

        locations = locations ++ &[_]AbiLocation{location};
    }

    return locations;
}

pub fn getReturnLocation(comptime function_type: anytype) ?AbiLocation {
    const function_info = @typeInfo(function_type).@"fn";

    if (function_info.return_type == null) return null;

    const Return = function_info.return_type.?;

    if (@sizeOf(Return) == 0) return null;

    var location: AbiLocation = undefined;

    var next_general_register: ?Hart.AbiRegister = .a0;

    std.debug.assert(@sizeOf(Return) <= @sizeOf(u64));

    //walk through arguments in order and allocate locations
    switch (@typeInfo(function_info.return_type.?)) {
        .pointer => {
            location = .{ .general_register = next_general_register.? };

            next_general_register = @enumFromInt(@intFromEnum(next_general_register.?) + 1);
        },
        .int, .@"enum", .bool => {
            location = .{ .general_register = next_general_register.? };

            next_general_register = @enumFromInt(@intFromEnum(next_general_register.?) + 1);
        },
        .float => {
            @compileError("Floats are unsupported");
        },
        .@"struct" => @compileError("Structs are unsupported"),
        .@"union" => @compileError("Unions are unsupported"),
        else => @compileError("Type unsupported"),
    }

    return location;
}

pub inline fn loadParameter(hart: *const Hart, comptime location: AbiLocation, comptime T: type) T {
    switch (@typeInfo(T)) {
        .pointer => {
            std.debug.assert(location == .general_register);

            switch (location) {
                .general_register => |register| {
                    const register_value = hart.registers[@intFromEnum(register)];

                    return @ptrFromInt(register_value);
                },
                .stack => unreachable,
                .float_register => unreachable,
            }
        },
        .int => |integer_type| {
            std.debug.assert(location == .general_register);

            switch (location) {
                .general_register => |register| {
                    const register_value: if (integer_type.signedness == .unsigned) u64 else i64 = @bitCast(hart.registers[@intFromEnum(register)]);

                    return @intCast(register_value);
                },
                .stack => unreachable,
                .float_register => unreachable,
            }
        },
        .@"enum" => {
            std.debug.assert(location == .general_register);

            switch (location) {
                .general_register => |register| {
                    const register_value = hart.registers[@intFromEnum(register)];

                    return @enumFromInt(register_value);
                },
                .stack => unreachable,
                .float_register => unreachable,
            }
        },
        .bool => {
            std.debug.assert(location == .general_register);

            switch (location) {
                .general_register => |register| {
                    const register_value = hart.registers[@intFromEnum(register)];

                    return register_value == 1;
                },
                .stack => unreachable,
                .float_register => unreachable,
            }
        },
        else => @compileError("Type unsupported"),
    }

    unreachable;
}

pub inline fn storeParameter(hart: *Hart, comptime location: AbiLocation, comptime T: type, value: T) void {
    switch (@typeInfo(T)) {
        .pointer => {
            switch (location) {
                .general_register => |register| {
                    hart.registers[@intFromEnum(register)] = @intFromPtr(value);
                },
                else => comptime unreachable,
            }
        },
        .int, .comptime_int => {
            switch (location) {
                .general_register => |register| {
                    hart.registers[@intFromEnum(register)] = value;
                },
                else => comptime unreachable,
            }
        },
        else => @compileError("Invalid type " ++ std.fmt.comptimePrint("'{}'", .{T})),
    }
}

pub inline fn loadReturnValue(hart: *const Hart, comptime location: AbiLocation, comptime T: type) T {
    return loadParameter(hart, location, T);
}

pub inline fn storeReturnValue(hart: *Hart, comptime location: AbiLocation, comptime T: type, value: T) void {
    return storeParameter(hart, location, T, value);
}

const Hart = @import("Hart.zig");
const std = @import("std");
