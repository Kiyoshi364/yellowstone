const std = @import("std");
const Allocator = std.mem.Allocator;

const lib_sim = @import("lib_sim");

const Direction = @import("Direction.zig");
const DirectionEnum = Direction.DirectionEnum;

const sim = @import("simulation.zig");
const SimState = sim.State;
const SimInput = sim.Input;

const block = @import("block.zig");
const Block = block.Block;
const BlockType = block.BlockType;
const Repeater = block.Repeater;

pub const controler = lib_sim.Sandboxed(CtlState, CtlInput){
    .update = update,
};

const starting_block_state = [_]Block{
    .{ .empty = .{} },
    .{ .source = .{} },
    .{ .wire = .{} },
    .{ .block = .{} },
    .{ .repeater = Repeater.init(.Up, .one) },
    .{ .repeater = Repeater.init(.Up, .two) },
    .{ .repeater = Repeater.init(.Up, .three) },
    .{ .repeater = Repeater.init(.Up, .four) },
    .{ .negator = .{} },
};

const Camera = struct {
    pos: [3]isize = .{ 0, 0, 0 },
    dim: [2]usize = .{ 3, 7 },

    fn is_cursor_inside(self: Camera, cursor: [3]u8) bool {
        return (self.pos[0] <= cursor[0] and
            cursor[0] - self.pos[0] <= 0) and
            (self.pos[1] <= cursor[1] and
            cursor[1] - self.pos[1] <= self.dim[0]) and
            (self.pos[2] <= cursor[2] and
            cursor[2] - self.pos[2] <= self.dim[1]);
    }

    fn mut_follow_cursor(
        self: *Camera,
        cursor: [3]u8,
        de: DirectionEnum,
    ) void {
        if (self.is_cursor_inside(cursor)) {
            // Empty
        } else {
            self.*.pos = if (de.add_arr(
                @TypeOf(self.pos[0]),
                self.pos,
            )) |val|
                val
            else
                self.pos;
        }
    }
};

pub const CtlState = struct {
    update_count: usize = 0,
    sim_state: SimState,
    last_input: ?SimInput = null,
    cursor: [3]u8,
    camera: Camera = .{},
    block_state: @TypeOf(starting_block_state) = starting_block_state,
    curr_block: usize = 0,

    const blks_len = @intCast(
        @typeInfo(BlockType).Enum.tag_type,
        @as(
            CtlState,
            undefined,
        ).block_state.len,
    );
};

pub const CtlInput = union(enum) {
    step: struct {},
    putBlock: struct {},
    moveCursor: DirectionEnum,
    nextBlock: struct {},
    prevBlock: struct {},
    nextRotate: struct {},
    prevRotate: struct {},
};

fn DirPosIter(comptime Int: type) type {
    const Uint = @Type(.{ .Int = .{
        .bits = @typeInfo(Int).Int.bits - 1,
        .signedness = .unsigned,
    } });
    return struct {
        dir: DirectionEnum,
        bounds: [3]Uint,
        offset: [3]Int,
        count: usize,

        pub fn init(
            dir: DirectionEnum,
            bounds: [3]Uint,
            offset: [3]Int,
            count: usize,
        ) DirPosIter(Int) {
            return .{
                .dir = dir,
                .bounds = bounds,
                .offset = offset,
                .count = count,
            };
        }

        fn inbounds_or_null(pos: [3]Int, bounds: [3]Uint) ?[3]Uint {
            var ret = @as([3]Uint, undefined);
            return for (pos, 0..) |x, i| {
                if (x < 0 or bounds[i] < x) {
                    break null;
                } else {
                    ret[i] = @intCast(Uint, x);
                }
            } else ret;
        }

        pub fn next_m_pos(self: *DirPosIter(Int)) ??[3]Uint {
            if (self.count > 0) {
                self.*.count -= 1;
                const ret_pos =
                    inbounds_or_null(self.offset, self.bounds);
                self.*.offset = if (self.dir.add_arr(
                    @TypeOf(self.offset[0]),
                    self.offset,
                )) |val|
                    val
                else
                    self.offset;
                return ret_pos;
            } else {
                return @as(??[3]Uint, null);
            }
        }
    };
}

pub fn update(
    ctl: CtlState,
    cinput: CtlInput,
    alloc: Allocator,
) Allocator.Error!CtlState {
    var newctl = ctl;
    switch (cinput) {
        .step => {
            const input = .empty;
            newctl.sim_state =
                try sim.simulation.update(
                ctl.sim_state,
                input,
                alloc,
            );
            newctl.update_count = ctl.update_count +| 1;
            newctl.last_input = input;
        },
        .putBlock => {
            const input = SimInput{ .putBlock = .{
                .z = ctl.cursor[0],
                .y = ctl.cursor[1],
                .x = ctl.cursor[2],
                .block = ctl.block_state[ctl.curr_block],
            } };
            newctl.sim_state =
                try sim.simulation.update(
                ctl.sim_state,
                input,
                alloc,
            );
            newctl.update_count = ctl.update_count +| 1;
            newctl.last_input = input;
        },
        .moveCursor => |de| if (de.inbounds_arr(
            u8,
            newctl.cursor,
            [_]u8{ sim.depth, sim.height, sim.width },
        )) |npos| {
            newctl.cursor = npos;
            newctl.camera.mut_follow_cursor(newctl.cursor, de);
        },
        .nextBlock => newctl.curr_block =
            (newctl.curr_block +% 1) % CtlState.blks_len,
        .prevBlock => newctl.curr_block =
            (newctl.curr_block +% CtlState.blks_len -% 1) % CtlState.blks_len,
        .nextRotate => newctl.block_state[newctl.curr_block] =
            newctl.block_state[newctl.curr_block].nextRotate(),
        .prevRotate => newctl.block_state[newctl.curr_block] =
            newctl.block_state[newctl.curr_block].prevRotate(),
    }
    return newctl;
}

fn print_repeat_ln(
    writer: anytype,
    comptime fmt: []const u8,
    args: anytype,
    times: usize,
) !void {
    var i = @as(usize, 0);
    while (i < times) : (i += 1) {
        try writer.print(fmt, args);
    }
    try writer.print("\n", .{});
}

fn print_input_ln(writer: anytype, update_count: usize, m_input: ?sim.Input) !void {
    if (m_input) |input| {
        try writer.print("= Input({d}): ", .{update_count});
        switch (input) {
            .empty => try writer.print("Step", .{}),
            .putBlock => |i| {
                try writer.print("Put .{s} at (y: {}, x: {})", .{
                    @tagName(i.block),
                    i.y,
                    i.x,
                });
            },
        }
    } else {
        try writer.print("= Start", .{});
    }
    try writer.print("\n", .{});
}

pub fn draw(ctl: CtlState, alloc: std.mem.Allocator) !void {
    const state = ctl.sim_state;
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    const camera = ctl.camera;
    const line_width = camera.dim[1] + 1;

    const line_buffer = try alloc.alloc(sim.DrawBlock, line_width);
    defer alloc.free(line_buffer);

    var screen_down_iter = DirPosIter(isize).init(
        DirectionEnum.Down,
        .{ sim.depth, sim.height, sim.width },
        camera.pos,
        camera.dim[0] + 1,
    );

    try stdout.print("+", .{});
    try print_repeat_ln(stdout, "---+", .{}, line_width);

    while (screen_down_iter.next_m_pos()) |m_pos| {
        if (m_pos) |upos| {
            const pos = [_]isize{
                @as(isize, upos[0]),
                @as(isize, upos[1]),
                @as(isize, upos[2]),
            };
            { // build line_buffer
                var screen_right_iter = DirPosIter(isize).init(
                    DirectionEnum.Right,
                    .{ sim.depth, sim.height, sim.width },
                    pos,
                    camera.dim[1] + 1,
                );

                var i = @as(usize, 0);
                while (screen_right_iter.next_m_pos()) |m_lpos| : (i += 1) {
                    line_buffer[i] =
                        if (m_lpos) |lpos|
                    blk: {
                        const b = state.block_grid[lpos[0]][lpos[1]][lpos[2]];
                        const this_power = state.power_grid[lpos[0]][lpos[1]][lpos[2]];
                        break :blk sim.render_block(b, this_power);
                    } else .{
                        .up_row = "***".*,
                        .mid_row = "***".*,
                        .bot_row = "***".*,
                    };
                }
            }

            try stdout.print("|", .{});
            if (pos[0] == ctl.cursor[0] and pos[1] == ctl.cursor[1]) {
                for (line_buffer, 0..) |x, i| {
                    if (pos[2] + @intCast(isize, i) == ctl.cursor[2]) {
                        try stdout.print("{s: ^2}x|", .{x.up_row[0..2]});
                    } else {
                        try stdout.print("{s: ^3}|", .{x.up_row});
                    }
                } else try stdout.print("\n", .{});
            } else {
                for (line_buffer) |x| {
                    try stdout.print("{s: ^3}|", .{x.up_row});
                } else try stdout.print("\n", .{});
            }

            try stdout.print("|", .{});
            for (line_buffer) |x| {
                try stdout.print("{s: ^3}|", .{x.mid_row});
            } else try stdout.print("\n", .{});

            try stdout.print("|", .{});
            for (line_buffer) |x| {
                try stdout.print("{s: ^3}|", .{x.bot_row});
            } else try stdout.print("\n", .{});
        } else {
            try stdout.print("|", .{});
            try print_repeat_ln(stdout, "***|", .{}, line_width);

            try stdout.print("|", .{});
            try print_repeat_ln(stdout, "***|", .{}, line_width);

            try stdout.print("|", .{});
            try print_repeat_ln(stdout, "***|", .{}, line_width);
        }

        try stdout.print("+", .{});
        try print_repeat_ln(stdout, "---+", .{}, line_width);
    }

    try print_repeat_ln(stdout, "=", .{}, line_width * 4 + 1);

    try print_input_ln(stdout, ctl.update_count, ctl.last_input);
    try stdout.print(
        "= cursor: z: {d:0>3} y: {d:0>3} x: {d:0>3}\n",
        .{ ctl.cursor[0], ctl.cursor[1], ctl.cursor[2] },
    );
    try stdout.print("= camera:\n", .{});
    try stdout.print(
        "= > pos: z: {d: >3} y: {d: >3} x: {d: >3}\n",
        .{ ctl.camera.pos[0], ctl.camera.pos[1], ctl.camera.pos[2] },
    );
    try stdout.print(
        "= > rot: v: down ({d:0>2}) >: right({d:0>2})\n",
        .{ ctl.camera.dim[0] + 1, ctl.camera.dim[1] + 1 },
    );
    try stdout.print(
        "= curr_block ({d}): {}\n",
        .{ ctl.curr_block, ctl.block_state[ctl.curr_block] },
    );

    try print_repeat_ln(stdout, "=", .{}, line_width * 4 + 1);

    try bw.flush();
}

test "controler compiles!" {
    std.testing.refAllDeclsRecursive(@This());
    std.testing.refAllDeclsRecursive(DirPosIter(isize));
}
