const std = @import("std");

z: i2 = 0,
y: i2 = 0,
x: i2 = 0,

const Direction = @This();

pub const BELOW = Direction{ .z = -1 };
pub const ABOVE = Direction{ .z = 1 };
pub const UP = Direction{ .y = -1 };
pub const DOWN = Direction{ .y = 1 };
pub const LEFT = Direction{ .x = -1 };
pub const RIGHT = Direction{ .x = 1 };

pub const DirectionEnum = enum(u3) {
    Above = 0,
    Up = 1,
    Right = 2,
    Down = 3,
    Left = 4,
    Below = 5,

    pub const count = 6;

    pub const directions = blk: {
        var ds = @as([count]DirectionEnum, undefined);
        for (Direction.directions, 0..) |d, i| {
            ds[i] = fromDirection(d).?;
        }
        break :blk ds;
    };

    pub fn next(self: DirectionEnum) DirectionEnum {
        return switch (self) {
            .Above => .Up,
            .Up => .Right,
            .Right => .Down,
            .Down => .Left,
            .Left => .Below,
            .Below => .Above,
        };
    }

    pub fn prev(self: DirectionEnum) DirectionEnum {
        return switch (self) {
            .Above => .Below,
            .Up => .Above,
            .Right => .Up,
            .Down => .Right,
            .Left => .Down,
            .Below => .Left,
        };
    }

    pub fn back(self: DirectionEnum) DirectionEnum {
        return switch (self) {
            .Above => .Below,
            .Up => .Down,
            .Right => .Left,
            .Down => .Up,
            .Left => .Right,
            .Below => .Above,
        };
    }

    pub fn toDirection(self: DirectionEnum) Direction {
        return switch (self) {
            .Above => ABOVE,
            .Up => UP,
            .Right => RIGHT,
            .Down => DOWN,
            .Left => LEFT,
            .Below => BELOW,
        };
    }

    pub fn fromDirection(d: Direction) ?DirectionEnum {
        const eql = std.meta.eql;
        return if (eql(d, ABOVE))
            .Above
        else if (eql(d, UP))
            .Up
        else if (eql(d, RIGHT))
            .Right
        else if (eql(d, DOWN))
            .Down
        else if (eql(d, LEFT))
            .Left
        else if (eql(d, BELOW))
            .Below
        else
            null;
    }

    pub fn inbounds(
        self: DirectionEnum,
        comptime Uint: type,
        z: Uint,
        y: Uint,
        x: Uint,
        bounds: [3]Uint,
    ) ?[3]Uint {
        return self.toDirection().inbounds(Uint, z, y, x, bounds);
    }

    pub fn inbounds_arr(
        self: DirectionEnum,
        comptime Uint: type,
        pos: [3]Uint,
        bounds: [3]Uint,
    ) ?[3]Uint {
        return self.toDirection().inbounds_arr(Uint, pos, bounds);
    }
};

pub const directions = [_]Direction{ ABOVE, UP, RIGHT, DOWN, LEFT, BELOW };

pub fn inbounds(
    self: Direction,
    comptime Uint: type,
    z: Uint,
    y: Uint,
    x: Uint,
    bounds: [3]Uint,
) ?[3]Uint {
    if (@typeInfo(Uint) != .Int) {
        @compileError("Expected int type, found '" ++ @typeName(Uint) ++ "'");
    }
    const d = bounds[0];
    const h = bounds[1];
    const w = bounds[2];
    const iz = @intCast(isize, z) + self.z;
    const iy = @intCast(isize, y) + self.y;
    const ix = @intCast(isize, x) + self.x;
    const z_is_ofb = iz < 0 or d <= iz;
    const y_is_ofb = iy < 0 or h <= iy;
    const x_is_ofb = ix < 0 or w <= ix;
    return if (z_is_ofb or y_is_ofb or x_is_ofb) null else [_]Uint{
        @intCast(Uint, iz),
        @intCast(Uint, iy),
        @intCast(Uint, ix),
    };
}

pub fn inbounds_arr(
    self: Direction,
    comptime Uint: type,
    pos: [3]Uint,
    bounds: [3]Uint,
) ?[3]Uint {
    return inbounds(self, Uint, pos[0], pos[1], pos[2], bounds);
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
