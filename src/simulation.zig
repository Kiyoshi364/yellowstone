const std = @import("std");
const Allocator = std.mem.Allocator;

const lib_sim = @import("lib_sim");

const block = @import("block.zig");
const Block = block.Block;

const Power = @import("Power.zig");

pub const simulation = lib_sim.Sandboxed(State, Input, Render){
    .update = update,
    .render = render,
};

pub const width = 8;
pub const height = width / 2;
pub const State = struct {
    block_grid: [height][width]Block,
    power_grid: [height][width]Power,
};

pub const Input = union(enum) {
    empty,
    putBlock: struct { y: u8, x: u8, block: Block },
};

pub const Render = *const [height][width]DrawBlock;

pub const emptyState = @as(State, .{
    .block_grid = .{.{.{ .empty = .{} }} ** width} ** height,
    .power_grid = .{.{.{}} ** width} ** height,
});

const Direction = @import("Direction.zig");
const DirectionEnum = Direction.DirectionEnum;
const directions = Direction.directions;

pub fn update(
    state: State,
    input: Input,
    alloc: Allocator,
) Allocator.Error!State {
    var newstate = state;

    const Pos = [2]usize;
    var mod_stack = std.ArrayList(Pos).init(alloc);
    defer mod_stack.deinit();

    { // handle input
        switch (input) {
            .empty => {},
            .putBlock => |i| {
                newstate.block_grid[i.y][i.x] = i.block;
                newstate.power_grid[i.y][i.x] = switch (i.block) {
                    .empty => Power.EMPTY_POWER,
                    .source => Power.SOURCE_POWER,
                    .wire,
                    .block,
                    => Power.BLOCK_OFF_POWER,
                };
                for (directions) |d| {
                    if (d.inbounds(usize, i.y, i.x, height, width)) |npos| {
                        try mod_stack.append(npos);
                    }
                }
                const should_update = switch (i.block) {
                    .empty,
                    .source,
                    => false,
                    .wire,
                    .block,
                    => true,
                };
                if (should_update) {
                    try mod_stack.append([_]usize{ i.y, i.x });
                }
            },
        }
    }

    { // update marked power
        // Note: a block may be marked many times
        // leading to unnecessary updates
        while (mod_stack.popOrNull()) |pos| {
            const y = pos[0];
            const x = pos[1];
            const b = newstate.block_grid[y][x];
            switch (b) {
                .empty => {
                    const empty_is_ok = std.meta.eql(
                        Power.EMPTY_POWER,
                        newstate.power_grid[y][x],
                    );
                    std.debug.assert(empty_is_ok);
                },
                .source => {
                    const source_is_ok = std.meta.eql(
                        Power.SOURCE_POWER,
                        newstate.power_grid[y][x],
                    );
                    std.debug.assert(source_is_ok);
                },
                .wire, .block => try update_wire_or_block(
                    &newstate,
                    &mod_stack,
                    y,
                    x,
                    b,
                ),
            }
        }
    }
    return newstate;
}

fn update_wire_or_block(
    newstate: *State,
    mod_stack: *std.ArrayList([2]usize),
    y: usize,
    x: usize,
    b: Block,
) Allocator.Error!void {
    std.debug.assert(b == .wire or b == .block);
    var this_power = @as(Power.PowerInt, 0);
    for (directions) |d| {
        if (d.inbounds(usize, y, x, height, width)) |npos| {
            const ny = npos[0];
            const nx = npos[1];
            const that_power =
                newstate.power_grid[ny][nx].power;
            if (that_power < 0) {
                const is_a_source =
                    that_power == Power.SOURCE_POWER.power;
                std.debug.assert(is_a_source);
                this_power = Power.FROM_SOURCE_POWER.power;
            } else if (this_power < that_power) {
                this_power = that_power - 1;
            }
        }
    }
    this_power = switch (b) {
        .empty,
        .source,
        => unreachable,
        .wire => this_power,
        .block => @min(Power.BLOCK_MAX_VALUE, this_power),
    };
    if (this_power != newstate.power_grid[y][x].power) {
        newstate.power_grid[y][x].power = this_power;
        for (directions) |d| {
            if (d.inbounds(usize, y, x, height, width)) |npos| {
                try mod_stack.append(npos);
            }
        }
    }
}

pub fn render(
    state: State,
    alloc: Allocator,
) Allocator.Error!Render {
    const canvas: *[height][width]DrawBlock =
        try alloc.create([height][width]DrawBlock);
    for (state.block_grid, 0..) |row, y| {
        for (row, 0..) |b, x| {
            const char_powers = @as(*const [17]u8, " 123456789abcdef*");
            const power_index = state.power_grid[y][x].to_index();
            const c_power = char_powers[power_index];
            const c_block = switch (b) {
                .empty => @as(u8, ' '),
                .source => @as(u8, 'S'),
                .wire => @as(u8, 'w'),
                .block => @as(u8, 'B'),
            };
            const char_dirs = @as(*const [6]u8, "o^>v<x");
            var c_dirs = @as([6]u8, "      ".*);
            if (b.facing()) |facing| {
                const i = @enumToInt(facing);
                c_dirs[i] = char_dirs[i];
            } else {
                // Empty
            }
            // const above = @enumToInt(DirectionEnum.Above);
            const up = @enumToInt(DirectionEnum.Up);
            const right = @enumToInt(DirectionEnum.Right);
            const down = @enumToInt(DirectionEnum.Down);
            const left = @enumToInt(DirectionEnum.Left);
            // const below = @enumToInt(DirectionEnum.Below);
            canvas.*[y][x] = DrawBlock{
                // .up_row = [3]u8{ c_dirs[above], c_dirs[up], ' ' },
                .up_row = [3]u8{ ' ', c_dirs[up], ' ' },
                .mid_row = [3]u8{ c_dirs[left], c_block, c_dirs[right] },
                .bot_row = [3]u8{ c_power, c_dirs[down], ' ' },
                // .bot_row = [3]u8{ c_power, c_dirs[down], c_dirs[below] },
            };
        }
    }
    return canvas;
}

pub const DrawBlock = struct {
    up_row: [3]u8,
    mid_row: [3]u8,
    bot_row: [3]u8,
};
