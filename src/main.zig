const std = @import("std");

const lib_sim = @import("lib_sim");

pub const block = @import("block.zig");
pub const sim = @import("simulation.zig");
pub const ctl = @import("controler.zig");

pub fn main() !void {
    var arena =
        std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const controler = ctl.controler;

    const state = blk: {
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
        break :blk state;
    };

    var ctlstate = ctl.CtlState{
        .sim_state = state,
        .cursor = .{0} ** 2,
    };

    const stdin_file = std.io.getStdIn().reader();
    var br = std.io.bufferedReader(stdin_file);
    const stdin = br.reader();

    const term = try config_term();
    defer term.unconfig_term() catch unreachable;

    try ctl.draw(ctlstate, alloc);
    while (true) {
        const ctlinput = try read_ctlinput(&stdin) orelse {
            break;
        };

        ctlstate = try controler.step(ctlstate, ctlinput, alloc);
        try ctl.draw(ctlstate, alloc);

        std.debug.assert(arena.reset(.{ .free_all = {} }));
    }
}

fn read_ctlinput(reader: anytype) !?ctl.CtlInput {
    var buffer = @as([1]u8, undefined);
    var loop = true;
    return while (loop) {
        const size = try reader.read(&buffer);
        if (size == 0) continue;
        switch (buffer[0]) {
            ' ' => break .{ .step = .{} },
            '\n' => break .{ .putBlock = .{} },
            'w' => break .{ .moveCursor = .Up },
            's' => break .{ .moveCursor = .Down },
            'a' => break .{ .moveCursor = .Left },
            'd' => break .{ .moveCursor = .Right },
            'n' => break .{ .nextBlock = .{} },
            'p' => break .{ .prevBlock = .{} },
            'q' => break null,
            else => {},
        }
    } else unreachable;
}

const Term = struct {
    old_term: std.os.termios,

    fn unconfig_term(self: Term) !void {
        const fd = 0;
        try std.os.tcsetattr(fd, .NOW, self.old_term);
    }
};

fn config_term() !Term {
    const fd = 0;
    const old_term = try std.os.tcgetattr(fd);
    var new_term = old_term;
    new_term.lflag &= ~(std.os.linux.ICANON | std.os.linux.ECHO);
    try std.os.tcsetattr(fd, .NOW, new_term);
    return .{
        .old_term = old_term,
    };
}

test "It compiles!" {
    std.testing.refAllDeclsRecursive(@This());
    std.testing.refAllDeclsRecursive(block);
    std.testing.refAllDeclsRecursive(sim);
    std.testing.refAllDeclsRecursive(ctl);
}

test "lib_sim.counter" {
    const counter = lib_sim.examples.counter_example;
    const state = @as(counter.State, 1);
    const input = .Dec;
    const new_state = counter.sim.step(state, input);
    try std.testing.expectEqual(@as(counter.State, 0), new_state);
}
