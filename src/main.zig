const std = @import("std");

const lib_sim = @import("lib_sim");

const block = @import("block.zig");
const sim = @import("simulation.zig");

fn draw(render: sim.Render) !void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    try stdout.print("+", .{});
    for (render[0]) |_| {
        try stdout.print("---+", .{});
    } else try stdout.print("\n", .{});
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
        for (row) |_| {
            try stdout.print("---+", .{});
        } else try stdout.print("\n", .{});
    }
    try bw.flush();
}

pub fn main() !void {
    var arena =
        std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const simulation = sim.simulation;

    var state = sim.emptyState;
    state[3][4] = .{ .wire = .{ .power = 0 } };

    var i = @as(u8, 0);
    while (i < 1) : (i += 1) {
        const input = void{};
        state = try simulation.step(state, input, alloc);
        const render = try simulation.view(state, alloc);
        try draw(render);

        std.debug.assert(arena.reset(.{ .free_all = {} }));
    }
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
