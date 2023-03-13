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

    var ctlstate = ctl.CtlState{
        .sim_state = state,
        .cursor = .{0} ** 2,
    };

    for (inputs) |input| {
        const ctlinput = .{ .step = input };
        ctlstate = try controler.step(ctlstate, ctlinput, alloc);
        try ctl.draw(ctlstate, alloc);

        std.debug.assert(arena.reset(.{ .free_all = {} }));
    }
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
