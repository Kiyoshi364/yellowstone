const std = @import("std");

/// Negative values encode special meaning
pub const PowerInt = i5;
pub const PowerUint = @Type(.{ .Int = .{
    .bits = @typeInfo(PowerInt).Int.bits,
    .signedness = .unsigned,
} });

pub const Power = enum(PowerInt) {
    pub const zero = Power.empty;

    empty = 0,
    one = 1,
    two = 2,
    three = 3,
    four = 4,
    five = 5,
    six = 6,
    seven = 7,
    eight = 8,
    nine = 9,
    ten = 10,
    eleven = 11,
    twelve = 12,
    thirteen = 13,
    fourteen = 14,
    fifteen = 15,

    source = -16,
    repeater = -15,
    negator = -14,
    _,

    pub fn to_index(self: Power) usize {
        return @bitCast(PowerUint, @enumToInt(self));
    }

    test "to_index non-negative values" {
        var i = @as(PowerInt, 0);
        while (i >= 0) : (i +%= 1) {
            const result = @intToEnum(Power, i).to_index();
            try std.testing.expectEqual(@intCast(usize, i), result);
        }
    }

    test "to_index negative values" {
        try std.testing.expectEqual(
            @as(usize, 16),
            SOURCE_POWER.to_index(),
        );
    }
};

pub const EMPTY_POWER = Power.empty;
pub const SOURCE_POWER = Power.source;
pub const REPEATER_POWER = Power.repeater;
pub const NEGATOR_POWER = Power.negator;

pub const FROM_SOURCE_POWER = Power.fifteen;
pub const FROM_REPEATER_POWER = FROM_SOURCE_POWER;
pub const FROM_NEGATOR_POWER = FROM_SOURCE_POWER;

pub const BLOCK_ON_POWER = Power.one;
pub const BLOCK_OFF_POWER = Power.zero;

test "static asserts for constants" {
    try std.testing.expectEqual(
        @enumToInt(SOURCE_POWER),
        @enumToInt(FROM_SOURCE_POWER) +% 1,
    );
    try std.testing.expectEqual(
        FROM_REPEATER_POWER,
        FROM_SOURCE_POWER,
    );
    try std.testing.expectEqual(
        FROM_NEGATOR_POWER,
        FROM_SOURCE_POWER,
    );
}

pub const InvalidPowerError = error{
    InvalidPower,
};
