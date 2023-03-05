const std = @import("std");

/// Negative values encode special meaning
pub const PowerInt = i5;
pub const PowerUint = @Type(.{ .Int = .{
    .bits = @typeInfo(PowerInt).Int.bits,
    .signedness = .unsigned,
} });

power: PowerInt = 0,

const Power = @This();

pub const EMPTY_POWER = Power{ .power = 0 };
pub const SOURCE_POWER = Power{ .power = -16 };
pub const REPEATER_POWER = Power{ .power = -15 };

pub const FROM_SOURCE_POWER = Power{ .power = 15 };
pub const FROM_REPEATER_POWER = FROM_SOURCE_POWER;

pub const BLOCK_ON_POWER = Power{ .power = 1 };
pub const BLOCK_OFF_POWER = Power{ .power = 0 };

pub const BLOCK_MAX_VALUE = @as(PowerInt, 1);

test "static asserts for constants" {
    try std.testing.expectEqual(
        SOURCE_POWER.power,
        FROM_SOURCE_POWER.power +% 1,
    );
    try std.testing.expectEqual(
        FROM_REPEATER_POWER,
        FROM_SOURCE_POWER,
    );
}

pub fn to_index(self: Power) usize {
    return @bitCast(PowerUint, self.power);
}

test "to_index non-negative values" {
    var i = @as(PowerInt, 0);
    while (i >= 0) : (i +%= 1) {
        const result = (Power{ .power = i }).to_index();
        try std.testing.expectEqual(@intCast(usize, i), result);
    }
}

test "to_index negative values" {
    try std.testing.expectEqual(
        @as(usize, 16),
        SOURCE_POWER.to_index(),
    );
}
