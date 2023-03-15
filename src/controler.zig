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

pub const controler = lib_sim.Sandboxed(CtlState, CtlInput){
    .update = update,
};

const starting_block_state =
    std.enums.directEnumArray(BlockType, Block, 0, .{
    .empty = .{ .empty = .{} },
    .source = .{ .source = .{} },
    .wire = .{ .wire = .{} },
    .block = .{ .block = .{} },
    .repeater = .{ .repeater = .{} },
});

pub const CtlState = struct {
    update_count: usize = 0,
    sim_state: SimState,
    last_input: ?SimInput = null,
    cursor: [2]u8,
    block_state: @TypeOf(starting_block_state) = starting_block_state,
    curr_block: @typeInfo(BlockType).Enum.tag_type = 0,

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
};

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
                .y = ctl.cursor[0],
                .x = ctl.cursor[1],
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
        .moveCursor => |de| newctl.cursor =
            if (de.inbounds_arr(
            u8,
            newctl.cursor,
            sim.height,
            sim.width,
        )) |npos|
            npos
        else
            newctl.cursor,
        .nextBlock => newctl.curr_block =
            (newctl.curr_block +% 1) % CtlState.blks_len,
        .prevBlock => newctl.curr_block =
            (newctl.curr_block +% CtlState.blks_len -% 1) % CtlState.blks_len,
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
    const render = try sim.render(state, alloc);
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    try print_repeat_ln(stdout, "=", .{}, render[0].len * 4 + 1);

    try print_input_ln(stdout, ctl.update_count, ctl.last_input);
    try stdout.print(
        "= y: {d:0>3} x: {d:0>3}\n",
        .{ ctl.cursor[0], ctl.cursor[1] },
    );
    try stdout.print(
        "= curr_block ({d}): {}\n",
        .{ ctl.curr_block, ctl.block_state[ctl.curr_block] },
    );

    try print_repeat_ln(stdout, "=", .{}, render[0].len * 4 + 1);

    try stdout.print("+", .{});
    try print_repeat_ln(stdout, "---+", .{}, render[0].len);

    for (render, 0..) |row, j| {
        try stdout.print("|", .{});
        if (j == ctl.cursor[0]) {
            for (row, 0..) |x, i| {
                if (i == ctl.cursor[1]) {
                    try stdout.print("{s: ^2}x|", .{x.up_row[0..2]});
                } else {
                    try stdout.print("{s: ^3}|", .{x.up_row});
                }
            } else try stdout.print("\n", .{});
        } else {
            for (row) |x| {
                try stdout.print("{s: ^3}|", .{x.up_row});
            } else try stdout.print("\n", .{});
        }

        try stdout.print("|", .{});
        for (row) |x| {
            try stdout.print("{s: ^3}|", .{x.mid_row});
        } else try stdout.print("\n", .{});

        try stdout.print("|", .{});
        for (row) |x| {
            try stdout.print("{s: ^3}|", .{x.bot_row});
        } else try stdout.print("\n", .{});

        try stdout.print("+", .{});
        try print_repeat_ln(stdout, "---+", .{}, render[0].len);
    }
    try bw.flush();
}
