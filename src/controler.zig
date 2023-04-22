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
    const max_dim = .{ 15, 31, 31 };

    pos: [3]isize = .{ 0, 0, 0 },
    dim: [3]Uisize = .{ 0, 7, 15 },
    axi: [3]struct { axis: Axis, is_p: bool } = .{
        .{ .axis = .z, .is_p = true },
        .{ .axis = .y, .is_p = true },
        .{ .axis = .x, .is_p = true },
    },

    fn dir_i(
        camera: Camera,
        i: @TypeOf(@enumToInt(Axis.z)),
    ) DirectionEnum {
        const ca = camera.axi[i];
        return ca.axis.to_de(ca.is_p);
    }

    fn dir(camera: Camera, axis: Axis) DirectionEnum {
        return camera.dir_i(@enumToInt(axis));
    }

    fn perspective_de(camera: Camera, de: DirectionEnum) DirectionEnum {
        const cam_de = camera.dir(de.toAxis());
        return if (de.is_positive())
            cam_de
        else
            cam_de.back();
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

    fn is_cursor_inside(camera: Camera, cursor: [3]u8) bool {
        return for (0..3) |i| {
            if (!(camera.pos[i] <= cursor[i] and
                cursor[i] - camera.pos[i] <= camera.dim[i]))
            {
                break false;
            }
        } else true;
    }

    fn mut_follow_cursor(
        camera: *Camera,
        cursor: [3]u8,
    ) void {
        if (camera.is_cursor_inside(cursor))
            void{}
        else for (0..3) |i| {
            if (cursor[i] < camera.pos[i]) {
                camera.pos[i] = cursor[i];
            } else if (camera.dim[i] < cursor[i] - camera.pos[i]) {
                camera.pos[i] =
                    @as(isize, cursor[i]) - camera.dim[i];
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
        .expandCamera => |de| if (de.inbounds_arr(
            Uisize,
            newctl.camera.dim,
            Camera.max_dim,
        )) |_| {
            const dec_val: u1 = @boolToInt(
                newctl.camera.perspective_de(de).is_negative(),
            );
            const i: usize = de.axis();
            newctl.camera.pos[i] -= dec_val;
            newctl.camera.dim[i] += 1;
        },
        .retractCamera => |de| if (de.back().inbounds_arr(
            Uisize,
            newctl.camera.dim,
            Camera.max_dim,
        )) |_| {
            const inc_val: u1 = @boolToInt(
                newctl.camera.perspective_de(de).is_negative(),
            );
            const i: usize = de.axis();
            newctl.camera.pos[i] += inc_val;
            newctl.camera.dim[i] -= 1;
        },
        .flipCamera => |axis| {
            newctl.camera.axi[@enumToInt(axis)].is_p =
                !newctl.camera.axi[@enumToInt(axis)].is_p;
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

    var screen_above_iter = blk: {
        const pos = blk2: {
            var pos = camera.pos;
            break :blk2 for (camera.axi) |ca| {
                const i = @enumToInt(ca.axis);
                if (ca.is_p) {
                    // Empty
                } else {
                    pos[i] += camera.dim[i];
                }
            } else pos;
        };
        break :blk DirPosIter(isize).init(
            camera.dir(.z),
            .{ sim.depth, sim.height, sim.width },
            pos,
            camera.dim[0] + 1,
        );
    };

    while (try screen_above_iter.next_ib_pos()) |k_ib_pos| {
        var screen_down_iter = DirPosIter(isize).init(
            camera.dir(.y),
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
                    camera.dir(.x),
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
                            camera.block_with_perspective(
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

            const zi = @enumToInt(camera.axi[0].axis);
            const yi = @enumToInt(camera.axi[1].axis);
            const xi = @enumToInt(camera.axi[2].axis);
            const is_cursor_in_this_line =
                jpos[zi] == ctl.cursor[zi] and
                jpos[yi] == ctl.cursor[yi];
            if (is_cursor_in_this_line) {
                var screen_right_iter = DirPosIter(isize).init(
                    camera.dir(.x),
                    .{ sim.depth, sim.height, sim.width },
                    jpos,
                    camera.dim[2] + 1,
                );
                for (line_buffer) |x| {
                    const ipos =
                        (screen_right_iter.next_ib_pos() catch unreachable).?.pos;
                    std.debug.assert(ipos[zi] == ctl.cursor[zi]);
                    std.debug.assert(ipos[yi] == ctl.cursor[yi]);
                    if (ipos[xi] == ctl.cursor[xi]) {
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
        .{ camera.pos[0], camera.pos[1], camera.pos[2] },
    );
    try writer.print(
        "= > rot: o: {s: <5}({d:0>2}) v: {s: <5}({d:0>2}) >: {s: <5}({d:0>2})\n",
        .{
            @tagName(camera.dir_i(0)),
            camera.dim[0] + 1,
            @tagName(camera.dir_i(1)),
            camera.dim[1] + 1,
            @tagName(camera.dir_i(2)),
            camera.dim[2] + 1,
        },
    );
    const curr_block_state = camera.block_with_perspective(
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
