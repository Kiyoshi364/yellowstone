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

const Direction = struct {
    y: i2 = 0,
    x: i2 = 0,

    fn inbounds(
        self: Direction,
        y: usize,
        x: usize,
        h: usize,
        w: usize,
    ) ?[2]usize {
        const iy = @intCast(isize, y) + self.y;
        const ix = @intCast(isize, x) + self.x;
        const y_is_ofb = iy < 0 or h <= iy;
        const x_is_ofb = ix < 0 or w <= ix;
        return if (y_is_ofb or x_is_ofb) null else [_]usize{
            @intCast(usize, iy),
            @intCast(usize, ix),
        };
    }
};

const directions = [_]Direction{
    .{ .x = 1 },
    .{ .x = -1 },
    .{ .y = 1 },
    .{ .y = -1 },
};

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
                newstate.power_grid[i.y][i.x] = .{};
                for (directions) |d| {
                    if (d.inbounds(i.y, i.x, height, width)) |npos| {
                        try mod_stack.append(npos);
                    }
                }
                try mod_stack.append([_]usize{ i.y, i.x });
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
            var this_power = switch (b) {
                .empty => {
                    const empty_is_ok =
                        Power.EMPTY_POWER
                        .isEqual(newstate.power_grid[y][x]);
                    std.debug.assert(empty_is_ok);
                    continue;
                },
                .source => {
                    newstate.power_grid[y][x] = Power.SOURCE_POWER;
                    continue;
                },
                else => @as(u5, 0),
            };
            for (directions) |d| {
                if (d.inbounds(y, x, height, width)) |npos| {
                    const ny = npos[0];
                    const nx = npos[1];
                    const that_power =
                        newstate.power_grid[ny][nx].power;
                    if (this_power < that_power) {
                        this_power = that_power - 1;
                    }
                }
            }
            this_power = switch (b) {
                .empty, .source => unreachable,
                .wire => this_power,
                .block => @min(Power.BLOCK_MAX_VALUE, this_power),
            };
            if (this_power != newstate.power_grid[y][x].power) {
                newstate.power_grid[y][x].power = this_power;
                for (directions) |d| {
                    if (d.inbounds(y, x, height, width)) |npos| {
                        try mod_stack.append(npos);
                    }
                }
            }
        }
    }
    return newstate;
}

pub fn render(
    state: State,
    alloc: Allocator,
) Allocator.Error!Render {
    const canvas: *[height][width]DrawBlock =
        try alloc.create([height][width]DrawBlock);
    for (state.block_grid, 0..) |row, y| {
        for (row, 0..) |b, x| {
            const powers = @as(*const [17]u8, " 123456789abcdef*");
            const c = powers[state.power_grid[y][x].power];
            const b_char = switch (b) {
                .empty => @as(u8, ' '),
                .source => @as(u8, 'S'),
                .wire => @as(u8, 'w'),
                .block => @as(u8, 'B'),
            };
            canvas.*[y][x] = DrawBlock{
                .up_row = @as([3]u8, "   ".*),
                .mid_row = [_]u8{' '} ++ [_]u8{b_char} ++ [_]u8{' '},
                .bot_row = [_]u8{c} ++ @as([2]u8, "  ".*),
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
