const std = @import("std");

// z: i2 = 0,
y: i2 = 0,
x: i2 = 0,

const Direction = @This();

// pub const BELOW = Direction{ .z = -1 };
// pub const ABOVE = Direction{ .z = 1 };
pub const UP = Direction{ .y = -1 };
pub const DOWN = Direction{ .y = 1 };
pub const LEFT = Direction{ .x = -1 };
pub const RIGHT = Direction{ .x = 1 };

pub const DirectionEnum = enum(u3) {
    // Above = 0,
    Up = 1,
    Right = 2,
    Down = 3,
    Left = 4,
    // Below = 5,

    pub const count = 4; // 6;

    pub const directions = blk: {
        var ds = @as([count]DirectionEnum, undefined);
        for (Direction.directions, 0..) |d, i| {
            ds[i] = fromDirection(d).?;
        }
        break :blk ds;
    };

    pub fn back(self: DirectionEnum) DirectionEnum {
        return switch (self) {
            // .Above => .Below,
            .Up => .Down,
            .Right => .Left,
            .Down => .Up,
            .Left => .Right,
            // .Below => .Above,
        };
    }

    pub fn toDirection(self: DirectionEnum) Direction {
        return switch (self) {
            // .Above => ABOVE,
            .Up => UP,
            .Right => RIGHT,
            .Down => DOWN,
            .Left => LEFT,
            // .Below => BELOW,
        };
    }

    pub fn fromDirection(d: Direction) ?DirectionEnum {
        const eql = std.meta.eql;
        return
        // if (eql(d, ABOVE))
        //     .Above
        // else if (eql(d, UP))
        if (eql(d, UP))
            .Up
        else if (eql(d, RIGHT))
            .Right
        else if (eql(d, DOWN))
            .Down
        else if (eql(d, LEFT))
            .Left
            // else if (eql(d, BELOW))
            //     .Below
        else
            null;
    }

    pub fn inbounds(
        self: DirectionEnum,
        comptime Uint: type,
        y: Uint,
        x: Uint,
        h: Uint,
        w: Uint,
    ) ?[2]Uint {
        return self.toDirection().inbounds(Uint, y, x, h, w);
    }
};

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

pub fn others(
    self: Direction,
    buffer: *[DirectionEnum.count]Direction,
) []Direction {
    var i = @as(u3, 0);
    for (std.meta.tags(DirectionEnum)) |de| {
        const d = de.toDirection();
        if (!std.meta.eql(self, d)) {
            buffer[i] = d;
            i += 1;
        }
    }
    return buffer[0..i];
}
