const std = @import("std");
const Allocator = std.mem.Allocator;

const lib_sim = @import("lib_sim");

const Direction = @import("Direction.zig");
const DirectionEnum = Direction.DirectionEnum;

const sim = @import("simulation.zig");
const SimState = sim.State;
const SimInput = sim.Input;

pub const controler = lib_sim.Sandboxed(CtlState, CtlInput){
    .update = update,
};

pub const CtlState = struct {
    sim_state: SimState,
    last_input: ?SimInput = null,
    cursor: SimState.Pos,
};

pub const CtlInput = union(enum) {
    step: SimInput,
    moveCursor: DirectionEnum,
};

pub fn update(
    ctl: CtlState,
    cinput: CtlInput,
    alloc: Allocator,
) Allocator.Error!CtlState {
    var newctl = ctl;
    switch (cinput) {
        .step => |input| {
            newctl.sim_state =
                try sim.simulation.update(
                ctl.sim_state,
                input,
                alloc,
            );
            newctl.last_input = input;
        },
        .moveCursor => |de| newctl.cursor =
            if (de.inbounds_arr(
            usize,
            newctl.cursor,
            sim.height,
            sim.width,
        )) |npos|
            npos
        else
            newctl.cursor,
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

fn print_input_ln(writer: anytype, m_input: ?sim.Input) !void {
    if (m_input) |input| {
        try writer.print("= Input: ", .{});
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

    try print_input_ln(stdout, ctl.last_input);
    try stdout.print(
        "= y: {d:0>3} x: {d:0>3}\n",
        .{ ctl.cursor[0], ctl.cursor[1] },
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
