const std = @import("std");

const Direction = @import("Direction.zig");
const DirectionEnum = Direction.DirectionEnum;

pub const BlockType = enum(u4) {
    empty = 0,
    source,
    wire,
    block,
    repeater,
};

pub const Delay = enum(u2) {
    one = 0,
    two = 1,
    three = 2,
    four = 3,

    fn mask(d: Delay) u4 {
        return @intCast(
            u4,
            @shlExact(@as(u5, 2), @enumToInt(d)) - 1,
        );
    }

    test "Delay.mask" {
        try std.testing.expectEqual(
            @as(u4, 0b0001),
            Delay.mask(.one),
        );
        try std.testing.expectEqual(
            @as(u4, 0b0011),
            Delay.mask(.two),
        );
        try std.testing.expectEqual(
            @as(u4, 0b0111),
            Delay.mask(.three),
        );
        try std.testing.expectEqual(
            @as(u4, 0b1111),
            Delay.mask(.four),
        );
    }
};

pub const Repeater = struct {
    facing: DirectionEnum,
    delay: Delay,
    /// Each bit of `memory` holds the state from it's "input"
    /// a number of ticks back:
    ///
    /// - `memory&0b0001` holds a value from `delay` ticks back
    /// - `memory&0b0010` holds a value from `delay - 1` ticks back
    /// - `memory&0b0100` holds a value from `delay - 2` ticks back
    /// - `memory&0b1000` holds a value from `delay - 3` ticks back
    ///
    /// So, on the next iteration it's output
    /// will be `memory&0b0001`.
    /// And then `memory&0b0010`, ...
    /// (Sure, assuming that `delay` is long enought).
    ///
    /// The smaller the delay, more bits will be unused,
    /// which means they should be set to 0:
    ///
    /// - `delay == .one` implies that `memory & 0b1110 == 0`
    /// - `delay == .two` implies that `memory & 0b1100 == 0`
    /// - `delay == .three` implies that `memory & 0b1000 == 0`
    /// - `delay == .four` implies that `memory & 0b0000 == 0`
    /// (note: no unused bits)
    ///
    /// At the start of the update function,
    /// this will be copied from previous state.
    ///
    /// Therefore, in the middle of the update function
    /// the last bit (`memory&0b0001`)
    /// will be the current output.
    ///
    /// Then, at the end of the update function,
    /// the current state's input will `shift`ed in.
    memory: u4 = 0,

    pub fn is_valid(r: Repeater) bool {
        return ~r.delay.mask() & r.memory == 0;
    }

    pub fn shift(self: Repeater, curr_in: u1) Repeater {
        std.debug.assert(self.is_valid());
        const top_bit = @shlExact(
            @as(u4, curr_in),
            @enumToInt(self.delay),
        );
        return .{
            .facing = self.facing,
            .delay = self.delay,
            .memory = top_bit | (self.memory >> 1),
        };
    }

    pub fn next_out(self: Repeater) u1 {
        return @intCast(u1, self.memory & 1);
    }

    pub fn is_on(self: Repeater) bool {
        return self.next_out() == 1;
    }
};

pub const Block = union(BlockType) {
    empty: struct {},
    source: struct {},
    wire: struct {},
    block: struct {},
    repeater: Repeater,

    pub fn facing(self: Block) ?DirectionEnum {
        return switch (self) {
            .empty, .source, .wire, .block => null,
            .repeater => |r| r.facing,
        };
    }
};
