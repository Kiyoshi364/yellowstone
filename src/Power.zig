const PowerUint = u5;

power: PowerUint = 0,

const Power = @This();

pub const EMPTY_POWER = Power{ .power = 0 };
pub const SOURCE_POWER = Power{ .power = 16 };

pub const BLOCK_MAX_VALUE = @as(PowerUint, 1);

pub fn isEqual(self: Power, other: Power) bool {
    return self.power == other.power;
}
