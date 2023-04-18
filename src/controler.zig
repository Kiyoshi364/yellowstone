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
    .{ .led = .{} },
    .{ .repeater = Repeater.init(.Up, .one) },
    .{ .repeater = Repeater.init(.Up, .two) },
    .{ .repeater = Repeater.init(.Up, .three) },
    .{ .repeater = Repeater.init(.Up, .four) },
    .{ .negator = .{} },
};

const Camera = struct {
    pos: [3]isize = .{ 0, 0, 0 },
    dim: [2]usize = .{ 7, 15 },

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
    ) void {
        if (self.is_cursor_inside(cursor)) {
            // Empty
        } else {
            if (cursor[0] < self.pos[0]) {
                self.pos[0] = cursor[0];
            } else if (0 <= cursor[0] - self.pos[0]) {
                self.pos[0] = cursor[0] - 0;
            }
            for (1..3) |i| {
                if (cursor[i] < self.pos[i]) {
                    self.pos[i] = cursor[i];
                } else if (self.dim[i - 1] <= cursor[i] - self.pos[i]) {
                    self.pos[i] =
                        cursor[i] - @intCast(isize, self.dim[i - 1]);
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

        pub fn next_m_pos(self: *DirPosIter(Int)) NextMPosError!?IB_Pos {
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
        .moveCursor => |de| if (de.inbounds_arr(
            u8,
            newctl.cursor,
            [_]u8{ sim.depth, sim.height, sim.width },
        )) |npos| {
            newctl.cursor = npos;
            newctl.camera.mut_follow_cursor(newctl.cursor);
        },
        .moveCamera => |de| newctl.camera.pos =
            de.add_sat_arr(isize, newctl.camera.pos),
        .expandCamera => |de| {
            const dec_val: u1 = switch (de) {
                .Above, .Below => 0,
                .Up, .Left => 1,
                .Down, .Right => 0,
            };
            switch (de) {
                .Above, .Below => {},
                .Up, .Down => {
                    newctl.camera.pos[1] -= dec_val;
                    newctl.camera.dim[0] += 1;
                },
                .Right, .Left => {
                    newctl.camera.pos[2] -= dec_val;
                    newctl.camera.dim[1] += 1;
                },
            }
        },
        .retractCamera => |de| {
            const inc_val: u1 = switch (de) {
                .Above, .Below => 0,
                .Up, .Left => 0,
                .Down, .Right => 1,
            };
            switch (de) {
                .Above, .Below => {},
                .Up, .Down => {
                    newctl.camera.pos[1] += inc_val;
                    newctl.camera.dim[0] -|= 1;
                },
                .Right, .Left => {
                    newctl.camera.pos[2] += inc_val;
                    newctl.camera.dim[1] -|= 1;
                },
            }
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
    const line_width = camera.dim[1] + 1;

    const line_buffer = try alloc.alloc(sim.DrawBlock, line_width);
    defer alloc.free(line_buffer);

    var screen_down_iter = DirPosIter(isize).init(
        DirectionEnum.Down,
        .{ sim.depth, sim.height, sim.width },
        camera.pos,
        camera.dim[0] + 1,
    );

    try writer.print("+", .{});
    try print_repeat_ln(writer, "---+", .{}, line_width);

    while (try screen_down_iter.next_m_pos()) |m_pos| {
        const pos = [_]isize{
            @as(isize, m_pos.pos[0]),
            @as(isize, m_pos.pos[1]),
            @as(isize, m_pos.pos[2]),
        };
        { // build line_buffer
            var screen_right_iter = DirPosIter(isize).init(
                DirectionEnum.Right,
                .{ sim.depth, sim.height, sim.width },
                pos,
                camera.dim[1] + 1,
            );

            var i = @as(usize, 0);
            while (try screen_right_iter.next_m_pos()) |m_lpos| : (i += 1) {
                line_buffer[i] =
                    if (m_lpos.inbounds)
                blk: {
                    const lpos = m_lpos.uint_pos();
                    const b = state.block_grid[lpos[0]][lpos[1]][lpos[2]];
                    const this_power = state.power_grid[lpos[0]][lpos[1]][lpos[2]];
                    break :blk sim.render_block(b, this_power);
                } else .{
                    .up_row = "&&&".*,
                    .mid_row = "&&&".*,
                    .bot_row = "&&&".*,
                };
            }
        }

        try writer.print("|", .{});
        if (pos[0] == ctl.cursor[0] and pos[1] == ctl.cursor[1]) {
            for (line_buffer, 0..) |x, i| {
                if (pos[2] + @intCast(isize, i) == ctl.cursor[2]) {
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
        "= > rot: v: down ({d:0>2}) >: right({d:0>2})\n",
        .{ ctl.camera.dim[0] + 1, ctl.camera.dim[1] + 1 },
    );
    try writer.print(
        "= curr_block ({d}): {}\n",
        .{ ctl.curr_block, ctl.block_state[ctl.curr_block] },
    );

    try print_repeat_ln(writer, "=", .{}, line_width * 4 + 1);
}

test "controler compiles!" {
    std.testing.refAllDeclsRecursive(@This());
    std.testing.refAllDeclsRecursive(DirPosIter(isize));
}
