const std = @import("std");
const Allocator = std.mem.Allocator;

const lib_sim = @import("lib_sim");

const Direction = @import("Direction.zig");
const DirectionEnum = Direction.DirectionEnum;
const Axis = Direction.Axis;

const sim = @import("simulation.zig");
const SimState = sim.State;
const SimInput = sim.Input;

const block = @import("block.zig");
const Block = block.Block;
const BlockType = block.BlockType;
const Repeater = block.Repeater;

const Uisize = @Type(.{ .Int = .{
    .bits = @typeInfo(isize).Int.bits - 1,
    .signedness = .unsigned,
} });

pub const controler = lib_sim.Sandboxed(CtlState, CtlInput){
    .update = update,
};

const starting_block_state = [_]Block{
    .{ .empty = .{} },
    .{ .source = .{} },
    .{ .wire = .{} },
    .{ .block = .{} },
    .{ .led = .{} },
    .{ .repeater = Repeater.init(.Up, .one) },
    .{ .repeater = Repeater.init(.Up, .two) },
    .{ .repeater = Repeater.init(.Up, .three) },
    .{ .repeater = Repeater.init(.Up, .four) },
    .{ .negator = .{} },
};

const Camera = struct {
    pos: [3]isize = .{ 0, 0, 0 },
    dir: [3]DirectionEnum = .{ .Above, .Down, .Right },
    dim: [3]Uisize = .{ 0, 7, 15 },

    fn perspective_de(self: Camera, de: DirectionEnum) DirectionEnum {
        const dir = self.dir[de.axis()];
        return if (de.is_positive())
            dir
        else
            dir.back();
    }

    fn block_with_perspective(
        self: Camera,
        b: Block,
    ) Block {
        return if (b.facing()) |de|
            b.with_facing(self.perspective_de(de))
        else
            b;
    }

    fn is_cursor_inside(self: Camera, cursor: [3]u8) bool {
        return for (0..3) |i| {
            const axis = self.dir[i].axis();
            const is_pos = self.dir[i].is_positive();
            if (is_pos) {
                if (!(self.pos[i] <= cursor[axis] and
                    cursor[axis] - self.pos[i] <= self.dim[i]))
                {
                    break false;
                }
            } else {
                if (!(cursor[axis] <= self.pos[i] and
                    self.pos[i] - self.dim[i] <= cursor[axis]))
                {
                    break false;
                }
            }
        } else true;
    }

    fn mut_follow_cursor(
        self: *Camera,
        cursor: [3]u8,
    ) void {
        if (self.is_cursor_inside(cursor)) {
            // Empty
        } else {
            for (self.dir, 0..3) |d, i| {
                const axis = d.axis();
                const is_pos = self.dir[i].is_positive();
                if (is_pos) {
                    if (cursor[axis] < self.pos[i]) {
                        self.pos[i] = cursor[axis];
                    } else if (self.dim[i] < cursor[axis] - self.pos[i]) {
                        self.pos[i] =
                            @as(isize, cursor[axis]) - self.dim[i];
                    }
                } else {
                    if (self.pos[i] < cursor[axis]) {
                        self.pos[i] = cursor[axis];
                    } else if (cursor[axis] < self.pos[i] - self.dim[i]) {
                        self.pos[i] =
                            cursor[axis] + self.dim[i];
                    }
                }
            }
        }
    }
};

pub const CtlState = struct {
    input_count: usize = 0,
    time_count: usize = 0,
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
    moveCamera: DirectionEnum,
    expandCamera: DirectionEnum,
    retractCamera: DirectionEnum,
    flipCamera: Axis,
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

        fn is_inbounds(pos: [3]Int, bounds: [3]Uint) bool {
            return for (pos, 0..) |x, i| {
                if (x < 0 or bounds[i] <= x) {
                    break false;
                }
            } else true;
        }

        pub const NextMPosError = error{DirPosIterOverflow};

        pub const IB_Pos = struct {
            inbounds: bool,
            pos: [3]Int,

            pub fn uint_pos(self: IB_Pos) [3]Uint {
                var ret = @as([3]Uint, undefined);
                for (self.pos, 0..) |x, i| {
                    ret[i] = @intCast(Uint, x);
                }
                return ret;
            }
        };

        pub fn next_ib_pos(self: *DirPosIter(Int)) NextMPosError!?IB_Pos {
            if (self.count > 0) {
                self.*.count -= 1;
                const ret_pos = .{
                    .inbounds = is_inbounds(
                        self.offset,
                        self.bounds,
                    ),
                    .pos = self.offset,
                };
                self.*.offset = if (self.dir.add_arr(
                    @TypeOf(self.offset[0]),
                    self.offset,
                )) |val|
                    val
                else
                    return NextMPosError.DirPosIterOverflow;
                return ret_pos;
            } else {
                return @as(NextMPosError!?IB_Pos, null);
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
            const input = .step;
            newctl.sim_state =
                try sim.simulation.update(
                ctl.sim_state,
                input,
                alloc,
            );
            newctl.time_count = ctl.time_count +| 1;
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
            newctl.input_count = ctl.input_count +| 1;
            newctl.last_input = input;
        },
        .moveCursor => |de| if (newctl.camera.perspective_de(de)
            .inbounds_arr(
            u8,
            newctl.cursor,
            [_]u8{ sim.depth, sim.height, sim.width },
        )) |npos| {
            newctl.cursor = npos;
            newctl.camera.mut_follow_cursor(newctl.cursor);
        },
        .moveCamera => |de| newctl.camera.pos =
            newctl.camera.perspective_de(de)
            .add_sat_arr(isize, newctl.camera.pos),
        .expandCamera => |de| {
            const dec_val: u1 = switch (de) {
                .Above, .Below => 0,
                .Up, .Left => 1,
                .Down, .Right => 0,
            };
            const i: usize = switch (de) {
                .Above, .Below => 0,
                .Up, .Down => 1,
                .Right, .Left => 2,
            };
            newctl.camera.pos[i] -= dec_val;
            newctl.camera.dim[i] += 1;
        },
        .retractCamera => |de| {
            const inc_val: u1 = switch (de) {
                .Above, .Below => 0,
                .Up, .Left => 0,
                .Down, .Right => 1,
            };
            const i: usize = switch (de) {
                .Above, .Below => 0,
                .Up, .Down => 1,
                .Right, .Left => 2,
            };
            newctl.camera.pos[i] += inc_val;
            newctl.camera.dim[i] -|= 1;
        },
        .flipCamera => |axis| {
            const i = @enumToInt(axis);
            const should_add = switch (newctl.camera.dir[i]) {
                .Above, .Down, .Right => true,
                .Below, .Up, .Left => false,
            };
            newctl.camera.pos[i] = if (should_add)
                newctl.camera.pos[i] + newctl.camera.dim[i]
            else
                newctl.camera.pos[i] - newctl.camera.dim[i];
            newctl.camera.dir[i] = newctl.camera.dir[i].back();
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

fn print_input_ln(writer: anytype, input_count: usize, m_input: ?sim.Input) !void {
    if (m_input) |input| {
        std.debug.assert(input == .putBlock);
        const i = input.putBlock;
        try writer.print("= Input({d}): ", .{input_count});
        try writer.print("Put .{s} at (z: {}, y: {}, x: {})", .{
            @tagName(i.block),
            i.z,
            i.y,
            i.x,
        });
    } else {
        try writer.print("= Start", .{});
    }
    try writer.print("\n", .{});
}

pub fn draw(
    ctl: CtlState,
    alloc: std.mem.Allocator,
    writer: anytype,
) !void {
    const state = ctl.sim_state;

    const camera = ctl.camera;
    const line_width = camera.dim[2] + 1;

    const line_buffer = try alloc.alloc(sim.DrawBlock, line_width);
    defer alloc.free(line_buffer);

    var screen_above_iter = DirPosIter(isize).init(
        camera.dir[0],
        .{ sim.depth, sim.height, sim.width },
        camera.pos,
        camera.dim[0] + 1,
    );

    while (try screen_above_iter.next_ib_pos()) |k_ib_pos| {
        var screen_down_iter = DirPosIter(isize).init(
            camera.dir[1],
            .{ sim.depth, sim.height, sim.width },
            k_ib_pos.pos,
            camera.dim[1] + 1,
        );

        try writer.print("+", .{});
        try print_repeat_ln(writer, "---+", .{}, line_width);

        while (try screen_down_iter.next_ib_pos()) |j_ib_pos| {
            const jpos = [_]isize{
                @as(isize, j_ib_pos.pos[0]),
                @as(isize, j_ib_pos.pos[1]),
                @as(isize, j_ib_pos.pos[2]),
            };
            { // build line_buffer
                var screen_right_iter = DirPosIter(isize).init(
                    camera.dir[2],
                    .{ sim.depth, sim.height, sim.width },
                    jpos,
                    camera.dim[2] + 1,
                );

                var i = @as(usize, 0);
                while (try screen_right_iter.next_ib_pos()) |i_ib_pos| : (i += 1) {
                    line_buffer[i] =
                        if (i_ib_pos.inbounds)
                    blk: {
                        const ipos = i_ib_pos.uint_pos();
                        const b =
                            ctl.camera.block_with_perspective(
                            state.block_grid[ipos[0]][ipos[1]][ipos[2]],
                        );
                        const this_power = state.power_grid[ipos[0]][ipos[1]][ipos[2]];
                        break :blk sim.render_block(b, this_power);
                    } else .{
                        .up_row = "&&&".*,
                        .mid_row = "&&&".*,
                        .bot_row = "&&&".*,
                    };
                }
            }

            try writer.print("|", .{});
            if (jpos[0] == ctl.cursor[0] and jpos[1] == ctl.cursor[1]) {
                var screen_right_iter = DirPosIter(isize).init(
                    camera.dir[2],
                    .{ sim.depth, sim.height, sim.width },
                    jpos,
                    camera.dim[2] + 1,
                );
                for (line_buffer) |x| {
                    const ipos =
                        (screen_right_iter.next_ib_pos() catch unreachable).?.pos;
                    if (ipos[2] == ctl.cursor[2]) {
                        try writer.print("{s: ^2}x|", .{x.up_row[0..2]});
                    } else {
                        try writer.print("{s: ^3}|", .{x.up_row});
                    }
                } else try writer.print("\n", .{});
            } else {
                for (line_buffer) |x| {
                    try writer.print("{s: ^3}|", .{x.up_row});
                } else try writer.print("\n", .{});
            }

            try writer.print("|", .{});
            for (line_buffer) |x| {
                try writer.print("{s: ^3}|", .{x.mid_row});
            } else try writer.print("\n", .{});

            try writer.print("|", .{});
            for (line_buffer) |x| {
                try writer.print("{s: ^3}|", .{x.bot_row});
            } else try writer.print("\n", .{});

            try writer.print("+", .{});
            try print_repeat_ln(writer, "---+", .{}, line_width);
        }

        try print_repeat_ln(writer, "=", .{}, line_width * 4 + 1);
    }

    try print_input_ln(writer, ctl.input_count, ctl.last_input);
    try writer.print(
        "= time: {d: >5} step{s}\n",
        .{
            ctl.time_count,
            if (ctl.time_count == 1) "" else "s",
        },
    );
    try writer.print(
        "= cursor: z: {d:0>3} y: {d:0>3} x: {d:0>3}\n",
        .{ ctl.cursor[0], ctl.cursor[1], ctl.cursor[2] },
    );
    try writer.print("= camera:\n", .{});
    try writer.print(
        "= > pos: z: {d: >3} y: {d: >3} x: {d: >3}\n",
        .{ ctl.camera.pos[0], ctl.camera.pos[1], ctl.camera.pos[2] },
    );
    try writer.print(
        "= > rot: o: {s: <5}({d:0>2}) v: {s: <5}({d:0>2}) >: {s: <5}({d:0>2})\n",
        .{
            @tagName(ctl.camera.dir[0]),
            ctl.camera.dim[0] + 1,
            @tagName(ctl.camera.dir[1]),
            ctl.camera.dim[1] + 1,
            @tagName(ctl.camera.dir[2]),
            ctl.camera.dim[2] + 1,
        },
    );
    const curr_block_state = ctl.camera.block_with_perspective(
        ctl.block_state[ctl.curr_block],
    );
    try writer.print(
        "= curr_block ({d}): {}\n",
        .{ ctl.curr_block, curr_block_state },
    );

    try print_repeat_ln(writer, "=", .{}, line_width * 4 + 1);
}

test "controler compiles!" {
    std.testing.refAllDeclsRecursive(@This());
    std.testing.refAllDeclsRecursive(DirPosIter(isize));
}
