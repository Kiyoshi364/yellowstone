const std = @import("std");

const Direction = @import("Direction.zig");
const DirectionEnum = Direction.DirectionEnum;

pub const Comparator = struct {
    facing: DirectionEnum = .Up,
    memory: u4 = 0,

    pub fn with_facing(c: Comparator, newfacing: DirectionEnum) Comparator {
        return .{
            .facing = newfacing,
            .memory = c.memory,
        };
    }

    pub fn with_memory(c: Comparator, newmemory: u4) Comparator {
        return .{
            .facing = c.facing,
            .memory = newmemory,
        };
    }

    pub fn shift(c: Comparator, curr_in: u4, highest_side: u4) Comparator {
        return if (curr_in >= highest_side)
            c.with_memory(curr_in)
        else
            c.with_memory(0);
    }

    pub fn next_out(c: Comparator) u4 {
        return c.memory;
    }
};

test "Comparator compiles!" {
    std.testing.refAllDeclsRecursive(@This());
}
