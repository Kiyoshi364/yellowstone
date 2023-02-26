y: i2 = 0,
x: i2 = 0,

const Direction = @This();

pub const UP = Direction{ .y = -1 };
pub const DOWN = Direction{ .y = 1 };
pub const LEFT = Direction{ .x = -1 };
pub const RIGHT = Direction{ .x = 1 };

pub const directions = [_]Direction{ UP, RIGHT, DOWN, LEFT };

pub fn inbounds(
    self: Direction,
    comptime Uint: type,
    y: Uint,
    x: Uint,
    h: Uint,
    w: Uint,
) ?[2]Uint {
    if (@typeInfo(Uint) != .Int) {
        @compileError("Expected int type, found '" ++ @typeName(Uint) ++ "'");
    }
    const iy = @intCast(isize, y) + self.y;
    const ix = @intCast(isize, x) + self.x;
    const y_is_ofb = iy < 0 or h <= iy;
    const x_is_ofb = ix < 0 or w <= ix;
    return if (y_is_ofb or x_is_ofb) null else [_]usize{
        @intCast(usize, iy),
        @intCast(usize, ix),
    };
}
