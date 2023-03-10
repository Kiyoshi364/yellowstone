const std = @import("std");

const Direction = @import("Direction.zig");
const DirectionEnum = Direction.DirectionEnum;

pub const Repeater = CanonicalRepeater;

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

pub const CanonicalRepeater = struct {
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

    pub fn init(facing: DirectionEnum, delay: Delay) CanonicalRepeater {
        return .{
            .facing = facing,
            .delay = delay,
        };
    }

    pub fn init_mem(facing: DirectionEnum, delay: Delay, mem: u4) CanonicalRepeater {
        return .{
            .facing = facing,
            .delay = delay,
            .memory = mem,
        };
    }

    pub fn is_valid(r: CanonicalRepeater) bool {
        return ~r.delay.mask() & r.memory == 0;
    }

    pub fn get_delay(r: CanonicalRepeater) Delay {
        return r.delay;
    }

    pub fn get_memory(r: CanonicalRepeater) u4 {
        return r.memory;
    }

    pub fn shift(r: CanonicalRepeater, curr_in: u1) CanonicalRepeater {
        std.debug.assert(r.is_valid());
        const top_bit = @shlExact(
            @as(u4, curr_in),
            @enumToInt(r.delay),
        );
        return .{
            .facing = r.facing,
            .delay = r.delay,
            .memory = top_bit | (r.memory >> 1),
        };
    }

    pub fn next_out(r: CanonicalRepeater) u1 {
        return @intCast(u1, r.memory & 1);
    }

    pub fn is_on(r: CanonicalRepeater) bool {
        return r.next_out() == 1;
    }
};

fn test_repeater_with_facing_delay(
    comptime RepeaterType: type,
    facing: DirectionEnum,
    delay: Delay,
) !void {
    var rep = RepeaterType.init(facing, delay);
    var overflow = @as(u1, 0);
    var sequence = @as(u4, 0);
    var last_seq = @as(?u4, null);
    const max_seq = @shlExact(@as(u5, 2), @enumToInt(delay));

    while (overflow == 0 and sequence < max_seq) : ({
        last_seq = sequence;
        const ov = @addWithOverflow(sequence, 1);
        sequence = ov[0];
        overflow = ov[1];
    }) {
        var bit_i = @as(u3, 0);
        while (bit_i <= @enumToInt(delay)) : (bit_i += 1) {
            const i = @intCast(u2, bit_i);
            const bit_mask = @shlExact(@as(u4, 1), i);
            const bit = @intCast(
                u1,
                @shrExact(sequence & bit_mask, i),
            );

            const ls = last_seq orelse 0;
            const last_bit = @intCast(
                u1,
                @shrExact(ls & bit_mask, i),
            );
            try std.testing.expectEqual(
                last_bit,
                rep.next_out(),
            );
            try std.testing.expectEqual(
                if (last_bit == 1) true else false,
                rep.is_on(),
            );
            try std.testing.expectEqual(delay, rep.get_delay());
            rep = rep.shift(bit);
        }
    }
    { // last seq
        const ls = last_seq.?;
        var bit_i = @as(u3, 0);
        while (bit_i <= @enumToInt(delay)) : (bit_i += 1) {
            const i = @intCast(u2, bit_i);
            const bit_mask = @shlExact(@as(u4, 1), i);
            const bit = @as(u1, 0);

            const last_bit = @intCast(
                u1,
                @shrExact(ls & bit_mask, i),
            );
            try std.testing.expectEqual(
                last_bit,
                rep.next_out(),
            );
            try std.testing.expectEqual(
                if (last_bit == 1) true else false,
                rep.is_on(),
            );
            rep = rep.shift(bit);
        }
    }
}

test "CanonicalRepeater" {
    const directions = DirectionEnum.directions;
    const delays = [_]Delay{ .one, .two, .three, .four };
    for (directions) |facing| {
        for (delays) |delay| {
            try test_repeater_with_facing_delay(
                CanonicalRepeater,
                facing,
                delay,
            );
        }
    }
}

test "Repeater compiles!" {
    std.testing.refAllDeclsRecursive(@This());
}
