const std = @import("std");

const Direction = @import("Direction.zig");
const DirectionEnum = Direction.DirectionEnum;

pub const Repeater = ImplicitDelayRepeater;

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
    facing: DirectionEnum = .Up,
    delay: Delay = .one,
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

    pub fn with_facing(r: CanonicalRepeater, newfacing: DirectionEnum) CanonicalRepeater {
        return .{
            .facing = newfacing,
            .delay = r.delay,
            .memory = r.memory,
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

const SeqIter = struct {
    delay: Delay,
    i: u4 = 0,
    done: bool = false,

    fn init(delay: Delay) SeqIter {
        return .{ .delay = delay };
    }

    fn next(self: *SeqIter) ?u4 {
        const max_seq = @shlExact(
            @as(u5, 2),
            @enumToInt(self.delay),
        );
        return if (self.done)
            null
        else blk: {
            const seq = self.i;
            const ov = @addWithOverflow(self.i, 1);
            self.i = ov[0];
            self.done = ov[1] == 1 or self.i >= max_seq;
            break :blk seq;
        };
    }
};

fn test_repeater_with_facing_delay(
    comptime RepeaterType: type,
    facing: DirectionEnum,
    delay: Delay,
) !void {
    var rep = RepeaterType.init(facing, delay);
    var last_seq = @as(?u4, null);
    var seq_iter = SeqIter.init(delay);

    const bits = @enumToInt(delay) +% 1;
    while (seq_iter.next()) |sequence| : (last_seq = sequence) {
        var bit_i = @as(u3, 0);
        while (bit_i <= @enumToInt(delay)) : (bit_i += 1) {
            const i = @intCast(u2, bit_i);
            const bit_mask = @shlExact(@as(u4, 1), i);
            const bit = @intCast(
                u1,
                @shrExact(sequence & bit_mask, i),
            );

            const ls = last_seq orelse 0;

            const new_mask = @intCast(
                u4,
                @shlExact(@as(u5, 1), i) - 1,
            );
            const old_mask = ~new_mask;

            const old_mem = @shrExact(ls & old_mask, i);
            const new_mem = @shlExact(
                sequence & new_mask,
                bits -% i,
            );

            const mem = new_mem | old_mem;
            const last_bit = @intCast(u1, old_mem & 1);
            try std.testing.expectEqual(
                last_bit,
                rep.next_out(),
            );
            try std.testing.expectEqual(
                if (last_bit == 1) true else false,
                rep.is_on(),
            );
            try std.testing.expectEqual(delay, rep.get_delay());
            try std.testing.expectEqual(mem, rep.get_memory());
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

pub const ImplicitDelayRepeater = struct {
    facing: DirectionEnum = .Up,

    /// Please, look at CanonicalRepeater.memory for reference.
    /// This is the same but in a compressed form.
    ///
    /// The `delay` is encoded in the following way
    /// (`x` represent `memory` bits):
    ///
    /// - `0b0000x`: invalid
    /// - `0b0001x`: `.one`
    /// - `0b001xx`: `.two`
    /// - `0b01xxx`: `.three`
    /// - `0b1xxxx`: `.four`
    data: u5 = pack_delay_mem(.one, 0),

    pub fn init(facing: DirectionEnum, delay: Delay) ImplicitDelayRepeater {
        return init_mem(facing, delay, 0);
    }

    pub fn init_mem(facing: DirectionEnum, delay: Delay, mem: u4) ImplicitDelayRepeater {
        return .{
            .facing = facing,
            .data = pack_delay_mem(delay, mem),
        };
    }

    pub fn with_facing(r: ImplicitDelayRepeater, newfacing: DirectionEnum) ImplicitDelayRepeater {
        return .{
            .facing = newfacing,
            .data = r.data,
        };
    }

    inline fn pack_delay_mem(delay: Delay, mem: u4) u5 {
        const idelay = @enumToInt(delay);
        const not_m_mask = @as(u5, 0b11110) << idelay;
        const delay_bits = @as(u5, 0b00010) << idelay;

        std.debug.assert(not_m_mask & mem == 0);

        return delay_bits | mem;
    }

    inline fn unpack_delay_mem(in: u5) struct { delay: Delay, mem: u4 } {
        const clz = @clz(@intCast(u3, in >> 2));
        const delay = @intToEnum(Delay, 3 - clz);

        return .{
            .delay = delay,
            .mem = @intCast(u4, in & delay.mask()),
        };
    }

    pub fn is_valid(r: ImplicitDelayRepeater) bool {
        return @clz(r.data) < 4;
    }

    pub fn get_delay(r: ImplicitDelayRepeater) Delay {
        const pack = unpack_delay_mem(r.data);
        return pack.delay;
    }

    pub fn get_memory(r: ImplicitDelayRepeater) u4 {
        const pack = unpack_delay_mem(r.data);
        return pack.mem;
    }

    pub fn shift(r: ImplicitDelayRepeater, curr_in: u1) ImplicitDelayRepeater {
        std.debug.assert(r.is_valid());
        const clz = @clz(r.data);
        const flip_mask = @shlExact(
            @as(u5, 0b11) ^ @as(u5, curr_in),
            3 - clz,
        );
        const data = (r.data >> 1) ^ flip_mask;

        return .{
            .facing = r.facing,
            .data = data,
        };
    }

    pub fn next_out(r: ImplicitDelayRepeater) u1 {
        return @intCast(u1, r.data & 1);
    }

    pub fn is_on(r: ImplicitDelayRepeater) bool {
        return r.next_out() == 1;
    }

    test "ImplicitDelayRepeater.pack and ImplicitDelayRepeater.unpack}" {
        const delays = [_]Delay{ .one, .two, .three, .four };
        for (delays) |delay| {
            var seq_iter = SeqIter.init(delay);
            while (seq_iter.next()) |seq| {
                const data = pack_delay_mem(delay, seq);
                const pack = unpack_delay_mem(data);
                try std.testing.expectEqual(delay, pack.delay);
                try std.testing.expectEqual(seq, pack.mem);
            }
        }
    }
};

test "ImplicitDelayRepeater" {
    const directions = DirectionEnum.directions;
    const delays = [_]Delay{ .one, .two, .three, .four };
    for (directions) |facing| {
        for (delays) |delay| {
            try test_repeater_with_facing_delay(
                ImplicitDelayRepeater,
                facing,
                delay,
            );
        }
    }
}

test "Repeater compiles!" {
    std.testing.refAllDeclsRecursive(@This());
}
