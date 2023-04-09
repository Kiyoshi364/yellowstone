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

    pub fn add(
        self: DirectionEnum,
        comptime Uint: type,
        z: Uint,
        y: Uint,
        x: Uint,
    ) ?[3]Uint {
        const should_inc = switch (self) {
            .Above, .Right, .Down => true,
            .Up, .Left, .Below => false,
        };
        const ov = switch (self) {
            .Above, .Below => blk: {
                const ov = if (should_inc)
                    @addWithOverflow(z, 1)
                else
                    @subWithOverflow(z, 1);
                break :blk .{ [3]Uint{ ov[0], y, x }, ov[1] };
            },
            .Up, .Down => blk: {
                const ov = if (should_inc)
                    @addWithOverflow(y, 1)
                else
                    @subWithOverflow(y, 1);
                break :blk .{ [3]Uint{ z, ov[0], x }, ov[1] };
            },
            .Right, .Left => blk: {
                const ov = if (should_inc)
                    @addWithOverflow(x, 1)
                else
                    @subWithOverflow(x, 1);
                break :blk .{ [3]Uint{ z, y, ov[0] }, ov[1] };
            },
        };
        return if (ov[1] != 0) null else ov[0];
    }

    pub fn add_arr(
        self: DirectionEnum,
        comptime Uint: type,
        pos: [3]Uint,
    ) ?[3]Uint {
        return self.add(Uint, pos[0], pos[1], pos[2]);
    }

    pub fn add_sat(
        self: DirectionEnum,
        comptime Uint: type,
        z: Uint,
        y: Uint,
        x: Uint,
    ) [3]Uint {
        const should_inc = switch (self) {
            .Above, .Right, .Down => true,
            .Up, .Left, .Below => false,
        };
        return switch (self) {
            .Above, .Below => [_]Uint{
                if (should_inc) z +| 1 else z -| 1,
                y,
                x,
            },
            .Up, .Down => [_]Uint{
                z,
                if (should_inc) y +| 1 else y -| 1,
                x,
            },
            .Right, .Left => [_]Uint{
                z,
                y,
                if (should_inc) x +| 1 else x -| 1,
            },
        };
    }

    pub fn add_sat_arr(
        self: DirectionEnum,
        comptime Uint: type,
        pos: [3]Uint,
    ) [3]Uint {
        return self.add_sat(Uint, pos[0], pos[1], pos[2]);
    }

    pub fn inbounds(
        self: DirectionEnum,
        comptime Uint: type,
        z: Uint,
        y: Uint,
        x: Uint,
        bounds: [3]Uint,
    ) ?[3]Uint {
        const ret = self.add(Uint, z, y, x) orelse return null;
        return for (ret, 0..) |v, i| {
            if (v < 0 or bounds[i] <= v) {
                break null;
            }
        } else ret;
    }

    pub fn inbounds_arr(
        self: DirectionEnum,
        comptime Uint: type,
        pos: [3]Uint,
        bounds: [3]Uint,
    ) ?[3]Uint {
        return self.inbounds(Uint, pos[0], pos[1], pos[2], bounds);
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
    return inbounds_arr(self, Uint, [_]Uint{ z, y, x }, bounds);
}

pub fn inbounds_arr(
    self: Direction,
    comptime Uint: type,
    pos: [3]Uint,
    bounds: [3]Uint,
) ?[3]Uint {
    if (@typeInfo(Uint) != .Int) {
        @compileError("Expected int type, found '" ++ @typeName(Uint) ++ "'");
    }
    var ret = @as([3]Uint, undefined);
    return inline for (pos, 0..) |v, i| {
        const ov = switch (@field(self, .{ "z", "y", "x" }[i])) {
            0 => @addWithOverflow(v, 0),
            -1 => @subWithOverflow(v, 1),
            1 => @addWithOverflow(v, 1),
            -2 => unreachable,
        };
        if (ov[1] != 0 or ov[0] < 0 or bounds[i] <= ov[0]) {
            break null;
        } else {
            ret[i] = ov[0];
        }
    } else ret;
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
