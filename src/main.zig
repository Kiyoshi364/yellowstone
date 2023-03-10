const std = @import("std");

const lib_sim = @import("lib_sim");

pub const block = @import("block.zig");
pub const sim = @import("simulation.zig");

pub fn main() !void {
    var arena =
        std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const simulation = sim.simulation;

    var state = sim.emptyState;
    state.block_grid[0] = .{.{ .wire = .{} }} ** sim.width;
    state.block_grid[2] = .{.{ .wire = .{} }} ** 8 ++
        .{.empty} ** (sim.width - 8);
    state.block_grid[1][7] = .{ .wire = .{} };
    state.block_grid[1][9] = .{
        .repeater = block.Repeater.init(.Down, .one),
    };
    state.power_grid[1][9] = .{ .power = -15 };
    state.block_grid[2][9] = .{ .block = .{} };
    state.block_grid[3][2] = .{ .wire = .{} };
    state.block_grid[3][3] = .{ .wire = .{} };
    state.block_grid[3][4] = .{ .wire = .{} };
    state.block_grid[3][7] = .{ .wire = .{} };
    state.block_grid[3][9] = .{ .wire = .{} };
    state.block_grid[3][10] = .{
        .repeater = block.Repeater.init(.Right, .two),
    };
    state.power_grid[3][10] = .{ .power = -15 };
    state.block_grid[3][11] = .{ .block = .{} };

    const inputs = [_]sim.Input{
        .empty,
        .{ .putBlock = .{
            .y = 0,
            .x = 0,
            .block = .{ .source = .{} },
        } },
        .{ .putBlock = .{
            .y = 0,
            .x = 8,
            .block = .{ .block = .{} },
        } },
        .{ .putBlock = .{
            .y = 2,
            .x = 4,
            .block = .{ .block = .{} },
        } },
        .{ .putBlock = .{
            .y = 3,
            .x = 5,
            .block = .{ .wire = .{} },
        } },
    };

    for (inputs) |input| {
        state = try simulation.step(state, input, alloc);
        try draw(state, input, alloc);

        std.debug.assert(arena.reset(.{ .free_all = {} }));
    }
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

fn print_input_ln(writer: anytype, input: sim.Input) !void {
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
    try writer.print("\n", .{});
}

fn draw(state: sim.State, input: sim.Input, alloc: std.mem.Allocator) !void {
    const render = try sim.render(state, alloc);
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    try print_repeat_ln(stdout, "=", .{}, render[0].len * 4 + 1);

    try print_input_ln(stdout, input);

    try print_repeat_ln(stdout, "=", .{}, render[0].len * 4 + 1);

    try stdout.print("+", .{});
    try print_repeat_ln(stdout, "---+", .{}, render[0].len);

    for (render) |row| {
        try stdout.print("|", .{});
        for (row) |x| {
            try stdout.print("{s: ^3}|", .{x.up_row});
        } else try stdout.print("\n", .{});

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

test "It compiles!" {
    std.testing.refAllDeclsRecursive(@This());
    std.testing.refAllDeclsRecursive(block);
    std.testing.refAllDeclsRecursive(sim);
}

test "lib_sim.counter" {
    const counter = lib_sim.examples.counter_example;
    const state = @as(counter.State, 1);
    const input = .Dec;
    const new_state = counter.sim.step(state, input);
    try std.testing.expectEqual(@as(counter.State, 0), new_state);
}
