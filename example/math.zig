fn rational(comptime T: type) type {
    return RationalType(
        @typeInfo(T).int.signedness,
        @bitSizeOf(T),
        @bitSizeOf(T),
    );
}

fn RationalType(
    comptime signedness: std.builtin.Signedness,
    comptime numerator_bits: comptime_int,
    comptime denominator_bits: comptime_int,
) type {
    return packed struct {
        numerator: Numerator,
        denominator: Denominator,

        pub const T = Numerator;

        pub const Numerator = std.meta.Int(signedness, numerator_bits);
        pub const Denominator = std.meta.Int(.unsigned, denominator_bits);

        pub const NumeratorDouble = std.meta.Int(@typeInfo(Numerator).int.signedness, @bitSizeOf(Numerator) * 2);
        pub const DenominatorDouble = std.meta.Int(@typeInfo(Numerator).int.signedness, @bitSizeOf(Denominator) * 2);

        pub const max_value: @This() = .{ .numerator = std.math.maxInt(Numerator), .denominator = 0 };
        pub const nonzero_min_value: @This() = .{ .numerator = 1, .denominator = std.math.maxInt(Denominator) };

        pub fn float(a: anytype) @This() {
            return .fromFixed(.float(a));
        }

        pub fn integer(a: T) @This() {
            return .{ .numerator = a, .denominator = 0 };
        }

        pub fn quotient(a: T, b: T) @This() {
            return .div(.integer(a), .integer(b));
        }

        pub fn reciprocal(a: @This()) @This() {
            //Handles the encoding of 1 in the denominator as 0x00
            std.debug.assert(a.numerator != 0);

            const res_numerator: NumeratorDouble = a.numerator;
            const res_denominator: DenominatorDouble = a.denominator;

            var result: @This() = .{ .numerator = @intCast(res_denominator + 1), .denominator = @intCast(@abs(res_numerator) - 1) };

            result.numerator *= @intCast(std.math.sign(res_numerator));

            return result;
        }

        pub fn fromFixed(a: fixed(T)) @This() {
            return .quotient(a.value, fixed(T).scaling_factor);
        }

        pub fn add(lhs: @This(), rhs: @This()) @This() {
            //a/b + c/d = ad/bd + bc/bd = (ad + bc) / bd

            const lhs_numerator: NumeratorDouble = lhs.numerator;
            const lhs_denominator: DenominatorDouble = lhs.denominator;

            const rhs_numerator: NumeratorDouble = rhs.numerator;
            const rhs_denominator: DenominatorDouble = rhs.denominator;

            var res_numerator = lhs_numerator * (rhs_denominator + 1) + rhs_numerator * (lhs_denominator + 1);
            var res_denominator = (lhs_denominator + 1) * (rhs_denominator + 1);

            const gcd = std.math.gcd(@abs(res_numerator), res_denominator);

            res_numerator /= gcd;
            res_denominator /= gcd;

            return .{ .numerator = @intCast(res_numerator), .denominator = @intCast(res_denominator - 1) };
        }

        pub const Fraction = struct {
            numerator: NumeratorDouble,
            denominator: DenominatorDouble,
        };

        pub fn addNonCanonical(lhs: @This(), rhs: @This()) Fraction {
            const lhs_numerator: NumeratorDouble = lhs.numerator;
            const lhs_denominator: DenominatorDouble = lhs.denominator;

            const rhs_numerator: NumeratorDouble = rhs.numerator;
            const rhs_denominator: DenominatorDouble = rhs.denominator;

            const res_numerator = lhs_numerator * (rhs_denominator + 1) + rhs_numerator * (lhs_denominator + 1);
            const res_denominator = (lhs_denominator + 1) * (rhs_denominator + 1);

            return .{ .numerator = res_numerator, .denominator = res_denominator };
        }

        pub fn subNonCanonical(lhs: @This(), rhs: @This()) Fraction {
            return addNonCanonical(lhs, rhs.neg());
        }

        pub fn sub(lhs: @This(), rhs: @This()) @This() {
            return lhs.add(rhs.neg());
        }

        pub fn mul(lhs: @This(), rhs: @This()) @This() {
            const lhs_numerator: NumeratorDouble = lhs.numerator;
            const lhs_denominator: DenominatorDouble = lhs.denominator;

            const rhs_numerator: NumeratorDouble = rhs.numerator;
            const rhs_denominator: DenominatorDouble = rhs.denominator;

            var res_numerator = lhs_numerator * rhs_numerator;
            var res_denominator = (lhs_denominator + 1) * (rhs_denominator + 1);

            const gcd: NumeratorDouble = @intCast(std.math.gcd(@abs(res_numerator), @abs(res_denominator)));

            res_numerator = @divTrunc(res_numerator, gcd);
            res_denominator = @divTrunc(res_denominator, gcd);

            return .{ .numerator = @intCast(res_numerator), .denominator = @intCast(res_denominator - 1) };
        }

        pub fn div(lhs: @This(), rhs: @This()) @This() {
            return .mul(lhs, .reciprocal(rhs));
        }

        pub fn neg(x: @This()) @This() {
            return .{ .numerator = -x.numerator, .denominator = x.denominator };
        }

        pub fn abs(x: @This()) @This() {
            return .{ .numerator = @abs(x.numerator), .denominator = x.denominator };
        }

        pub fn sign(x: @This()) @This() {
            return .integer(std.math.sign(x.numerator));
        }

        pub fn floor(x: @This()) @This() {
            const numerator: NumeratorDouble = x.numerator;
            const denominator: DenominatorDouble = x.denominator;

            const result = @divFloor(numerator, denominator + 1);

            return .integer(@intCast(result));
        }

        pub fn ceil(x: @This()) @This() {
            var result = floor(x);

            const numerator: NumeratorDouble = x.numerator;
            const denominator: DenominatorDouble = x.denominator;

            result.numerator += @intFromBool(@abs(numerator) % (denominator + 1) != 0);

            return result;
        }

        pub fn fractionalPart(x: @This()) @This() {
            return x.sub(x.floor());
        }

        pub fn lessThan(a: @This(), b: @This()) bool {
            const difference = a.subNonCanonical(b);

            return difference.numerator < 0;
        }

        pub fn lessThanEqual(a: @This(), b: @This()) bool {
            const difference = a.subNonCanonical(b);

            return difference.numerator <= 0;
        }

        pub fn greaterThan(a: @This(), b: @This()) bool {
            return !lessThan(a, b);
        }

        pub fn greaterThanEqual(a: @This(), b: @This()) bool {
            return !lessThanEqual(a, b);
        }
    };
}

pub fn fixed(comptime T: type) type {
    return FixedType(
        @typeInfo(T).int.signedness,
        @bitSizeOf(T),
        (std.math.maxInt(std.meta.Int(@typeInfo(T).int.signedness, @bitSizeOf(T) / 2))) + 1,
    );
}

pub fn FixedType(
    comptime signedness: std.builtin.Signedness,
    comptime bits: comptime_int,
    comptime _scaling_factor: comptime_int,
) type {
    return packed struct(std.meta.Int(.unsigned, bits)) {
        value: Integer,

        pub const scaling_factor = _scaling_factor;

        pub const Integer = std.meta.Int(signedness, bits);
        pub const IntegerDouble = std.meta.Int(signedness, bits * 2);

        pub const max_value: @This() = .{ .value = std.math.maxInt(Integer) };
        pub const min_value: @This() = .{ .value = std.math.minInt(Integer) };

        pub inline fn integer(a: Integer) @This() {
            return .{
                .value = a * scaling_factor,
            };
        }

        pub inline fn ratio(a: Integer, b: Integer) @This() {
            return .fromRational(.quotient(a, b));
        }

        pub inline fn fromRational(rat: rational(Integer)) @This() {
            const numerator: rational(Integer).NumeratorDouble = rat.numerator;
            const denominator: rational(Integer).DenominatorDouble = rat.denominator + 1;

            const result = @divTrunc(numerator * scaling_factor, denominator);

            return .{ .value = @intCast(result) };
        }

        pub inline fn float(a: anytype) @This() {
            return .{ .value = @intFromFloat(@round(a * scaling_factor)) };
        }

        pub inline fn toFloat(self: @This(), comptime Float: type) Float {
            const float_value: Float = @floatFromInt(self.value);

            return float_value / scaling_factor;
        }

        pub inline fn add(a: @This(), b: @This()) @This() {
            const lhs: IntegerDouble = a.value;
            const rhs: IntegerDouble = b.value;

            return .{ .value = @intCast(lhs + rhs) };
        }

        pub inline fn sub(a: @This(), b: @This()) @This() {
            const lhs: IntegerDouble = a.value;
            const rhs: IntegerDouble = b.value;

            return .{ .value = @intCast(lhs - rhs) };
        }

        pub inline fn mul(a: @This(), b: @This()) @This() {
            const lhs: IntegerDouble = a.value;
            const rhs: IntegerDouble = b.value;
            return .{ .value = @intCast(@divTrunc(lhs * rhs, scaling_factor)) };
        }

        ///Fused multiply add: (a * b) + c
        pub inline fn mulAdd(a: @This(), b: @This(), c: @This()) @This() {
            const a_double: IntegerDouble = a.value;
            const b_double: IntegerDouble = b.value;
            const c_double: IntegerDouble = c.value;

            const result = a_double * b_double + c_double * scaling_factor;

            return .{ .value = @intCast(@divTrunc(result, scaling_factor)) };
        }

        pub inline fn div(a: @This(), b: @This()) @This() {
            const lhs: IntegerDouble = a.value;
            const rhs: IntegerDouble = b.value;
            return .{ .value = @intCast(@divTrunc(lhs * scaling_factor, rhs)) };
        }

        pub inline fn reciprocal(a: @This()) @This() {
            return .div(.integer(1), a);
        }

        pub inline fn floor(x: @This()) @This() {
            return .{ .value = @divFloor(x.value, scaling_factor) * scaling_factor };
        }

        pub inline fn trunc(x: @This()) @This() {
            return .{ .value = @divTrunc(x.value, scaling_factor) * scaling_factor };
        }

        pub inline fn abs(x: @This()) @This() {
            return .{ .value = @intCast(@abs(x.value)) };
        }

        pub inline fn neg(x: @This()) @This() {
            return .{ .value = -x.value };
        }

        pub inline fn sign(x: @This()) @This() {
            return .{ .value = std.math.sign(x.value) * scaling_factor };
        }

        pub inline fn lessThan(a: @This(), b: @This()) bool {
            return a.value < b.value;
        }

        pub inline fn lessThanEqual(a: @This(), b: @This()) bool {
            return a.value <= b.value;
        }

        pub inline fn greaterThan(a: @This(), b: @This()) bool {
            return a.value > b.value;
        }

        pub inline fn greaterThanEqual(a: @This(), b: @This()) bool {
            return a.value >= b.value;
        }

        pub inline fn cast(fixed_value: anytype) @This() {
            const other_scaling_factor: comptime_int = @TypeOf(fixed_value).scaling_factor;

            if (scaling_factor > other_scaling_factor) {
                const scale = scaling_factor / other_scaling_factor;

                @compileLog(std.math.log2(scale));

                return .{ .value = fixed_value.value * scale };
            } else {
                @compileError("lol");
            }
        }
    };
}

fn fixedSqrt(comptime T: type, x: fixed(T)) fixed(T) {
    var t = x;

    for (0..4) |_| {
        t = fixed(T).mulAdd(t, t, x).div(t.add(t));
    }

    return t;
}

fn fixedCosSquaredTau(comptime T: type, x: fixed(T)) fixed(T) {
    return fixedCosTau(T, x.add(x)).add(.integer(1)).div(.integer(2));
}

pub fn fixedSinTau(comptime T: type, x: fixed(T)) fixed(T) {
    return fixedCosTau(T, x.neg().add(.ratio(1, 4)));
}

pub fn fixedCosTau(comptime T: type, x: fixed(T)) fixed(T) {
    return fixedNormCosTau(T, x);
}

fn fixedNormCosTau(comptime T: type, x: fixed(T)) fixed(T) {
    var r = x.abs().sub(x.abs().floor());

    var sign: fixed(T) = .integer(1);

    if (r.greaterThanEqual(.ratio(1, 2))) {
        r = r.sub(.ratio(1, 2));
        sign = sign.neg();
    }

    if (r.greaterThanEqual(.ratio(1, 4))) {
        r = fixed(T).ratio(1, 2).sub(r);
        sign = sign.neg();
    }

    var result: fixed(T) = .integer(0);

    if (r.lessThanEqual(.ratio(1, 8))) {
        const r_2 = r.mul(r);

        const n = 3;

        inline for (0..n + 1) |k| {
            result = .mulAdd(result, r_2, cosCoeff(T, n - k));
        }
    } else {
        const n = 2;

        const new_r = r.neg().add(.ratio(1, 4));
        const r_2 = new_r.mul(new_r);

        inline for (0..n + 1) |k| {
            result = .mulAdd(result, r_2, sinCoeff(T, n - k));
        }

        result = result.mul(new_r);
    }

    return result.mul(sign);
}

fn cosCoeff(comptime T: type, comptime n: comptime_int) fixed(T) {
    const result = repeatedMul(T, .float(std.math.tau), n * 2).div(.integer(factorial(n * 2)));

    return if (n % 2 == 0) result else result.neg();
}

fn sinCoeff(comptime T: type, comptime n: comptime_int) fixed(T) {
    const result = repeatedMul(T, .float(std.math.tau), n * 2 + 1).div(.integer(factorial(n * 2 + 1)));

    return if (n % 2 == 0) result else result.neg();
}

fn repeatedMul(comptime T: type, comptime x: fixed(T), comptime n: comptime_int) fixed(T) {
    var t: fixed(T) = .integer(1);

    for (0..n) |_| {
        t = t.mul(x);
    }

    return t;
}

fn factorial(comptime n: comptime_int) comptime_int {
    var x = 1;

    for (0..n) |k| {
        x *= (n - k);
    }

    return x;
}

pub fn formatFixed(comptime T: type, value: fixed(T)) void {
    const leading_bin_zeros: u64 = @min(@clz(@bitReverse(value.value)), @bitSizeOf(T) / 2);
    const filled_fract_bits: u64 = (@bitSizeOf(T) / 2) - leading_bin_zeros;
    _ = filled_fract_bits; // autofix

    const decimal_scaling_mag: u64 = 10;

    const decimal_scaling = std.math.pow(u128, 10, decimal_scaling_mag + 1);

    const integer_part = value.abs().trunc();
    const fractional_part = value.sub(integer_part.abs());

    var fract: u128 = @abs(fractional_part.value);

    fract *= decimal_scaling;
    fract /= fixed(T).scaling_factor;

    if (value.sign().value >= 0) {
        std.log.err("{}.{}", .{ @divTrunc(integer_part.value, fixed(T).scaling_factor), fract });
    } else {
        std.log.err("-{}.{}", .{ @divTrunc(integer_part.value, fixed(T).scaling_factor), fract });
    }
}

const std = @import("std");
