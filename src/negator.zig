const std = @import("std");

const Direction = @import("Direction.zig");
const DirectionEnum = Direction.DirectionEnum;

pub const Negator = struct {
    facing: DirectionEnum = .Up,
    memory: u1 = 0,
    last_out: u1 = 0,

    pub fn with_facing(n: Negator, newfacing: DirectionEnum) Negator {
        return .{
            .facing = newfacing,
            .memory = n.memory,
            .last_out = n.last_out,
        };
    }

    pub fn with_memory(n: Negator, newmemory: u1) Negator {
        return .{
            .facing = n.facing,
            .memory = newmemory,
            .last_out = n.last_out,
        };
    }

    pub fn shift(n: Negator, curr_in: u1) Negator {
        return .{
            .facing = n.facing,
            .memory = curr_in,
            .last_out = n.next_out(),
        };
    }

    pub fn next_out(n: Negator) u1 {
        return n.memory ^ 1;
    }

    pub fn is_on(n: Negator) bool {
        return n.next_out() == 1;
    }
};

test "Negator compiles!" {
    std.testing.refAllDeclsRecursive(@This());
}
