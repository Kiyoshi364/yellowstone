const std = @import("std");
const Allocator = std.mem.Allocator;

const lib_sim = @import("lib_sim");

const block = @import("block.zig");
const Block = block.Block;

const Direction = @import("Direction.zig");
const DirectionEnum = Direction.DirectionEnum;
const directions = Direction.directions;

const Power = @import("Power.zig");

pub const simulation = lib_sim.Sandboxed(State, Input){
    .update = update,
};

pub const width = 16;
pub const height = width / 2;
pub const State = struct {
    block_grid: [height][width]Block,
    power_grid: [height][width]Power,

    pub const Pos = [2]usize;

    const BlockIter = struct {
        y: usize = 0,
        x: usize = 0,

        pub fn next_pos(self: *BlockIter) ?State.Pos {
            if (self.y < height) {
                std.debug.assert(self.x < width);
                const pos = Pos{ self.y, self.x };
                if (self.x < width - 1) {
                    self.x += 1;
                } else {
                    std.debug.assert(self.x == width - 1);
                    self.y += 1;
                    self.x = 1;
                }
                return pos;
            } else {
                return null;
            }
        }

        pub fn next_block(self: *BlockIter, state: State) ?Block {
            return if (self.next_pos()) |pos|
                state.block_grid[pos.y][pos.x]
            else
                null;
        }

        pub fn next_power(self: *BlockIter, state: State) ?Power {
            return if (self.next_pos()) |pos|
                state.power_grid[pos.y][pos.x]
            else
                null;
        }
    };
};

test "State compiles!" {
    std.testing.refAllDeclsRecursive(State);
}

pub const Input = union(enum) {
    empty,
    putBlock: struct { y: u8, x: u8, block: Block },
};

pub const Render = *const [height][width]DrawBlock;

pub const emptyState = @as(State, .{
    .block_grid = .{.{.{ .empty = .{} }} ** width} ** height,
    .power_grid = .{.{.{}} ** width} ** height,
});

pub fn update(
    state: State,
    input: Input,
    alloc: Allocator,
) Allocator.Error!State {
    var newstate = state;

    var mod_stack = std.ArrayList(State.Pos).init(alloc);
    defer mod_stack.deinit();

    { // push "delayed machines" interactions
        // Note: this is before "handle input"
        // because update_list is a stack
        // and this should be handled after
        // (not that it matters)
        var block_it = State.BlockIter{};
        while (block_it.next_pos()) |pos| {
            const y = pos[0];
            const x = pos[1];
            const b = newstate.block_grid[y][x];
            switch (b) {
                .empty,
                .source,
                .wire,
                .block,
                => {},
                .repeater => {
                    // Note: here should be a great place
                    // to "do nothing" if repeater's output
                    // was the same.
                    // But we don't have this information
                    // (only what we will output now)
                    if (b.facing().?.inbounds_arr(
                        usize,
                        pos,
                        height,
                        width,
                    )) |front_pos| {
                        try mod_stack.append(front_pos);
                    } else {
                        // Empty
                    }
                },
            }
        }
    }

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
                    .repeater => |r| blk: {
                        std.debug.assert(r.is_valid());
                        break :blk Power.REPEATER_POWER;
                    },
                };
                for (directions) |d| {
                    if (d.inbounds(usize, i.y, i.x, height, width)) |npos| {
                        try mod_stack.append(npos);
                    }
                }
                const should_update = switch (i.block) {
                    .empty,
                    .source,
                    .repeater,
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
                .wire => try update_wire(
                    &newstate,
                    &mod_stack,
                    y,
                    x,
                    b,
                ),
                .block => try update_block(
                    &newstate,
                    &mod_stack,
                    y,
                    x,
                    b,
                ),
                .repeater => |r| {
                    const repeater_is_ok = std.meta.eql(
                        Power.REPEATER_POWER,
                        newstate.power_grid[y][x],
                    );
                    std.debug.assert(repeater_is_ok);
                    std.debug.assert(r.is_valid());
                },
            }
        }
    }

    { // For each repeater, shift input
        var block_it = State.BlockIter{};
        while (block_it.next_pos()) |pos| {
            const y = pos[0];
            const x = pos[1];
            const b = newstate.block_grid[y][x];
            if (b != .repeater) continue;
            const rep = b.repeater;
            const back_dir = rep.facing.back();
            const curr_in: u1 =
                if (back_dir.inbounds_arr(usize, pos, height, width)) |bpos|
            blk: {
                const power = newstate.power_grid[bpos[0]][bpos[1]];
                break :blk switch (power.power) {
                    0 => 0,
                    1...15 => 1,
                    Power.SOURCE_POWER.power => 1,
                    Power.REPEATER_POWER.power => blk2: {
                        const prev_b_block =
                            state.block_grid[bpos[0]][bpos[1]];
                        break :blk2 if (prev_b_block == .repeater)
                            prev_b_block.repeater.next_out()
                        else
                            0;
                    },
                    else => unreachable,
                };
            } else 0;
            newstate.block_grid[y][x] = .{ .repeater = rep.shift(curr_in) };
        }
    }
    return newstate;
}

fn update_wire(
    newstate: *State,
    mod_stack: *std.ArrayList(State.Pos),
    y: usize,
    x: usize,
    b: Block,
) Allocator.Error!void {
    std.debug.assert(b == .wire);
    var this_power = @as(Power.PowerInt, 0);
    for (directions) |d| {
        if (d.inbounds(usize, y, x, height, width)) |npos| {
            const ny = npos[0];
            const nx = npos[1];
            const that_power =
                newstate.power_grid[ny][nx].power;
            std.debug.assert(0 <= this_power);
            if (that_power < 0) {
                const that_block = newstate.block_grid[ny][nx];
                const is_a_source =
                    that_power == Power.SOURCE_POWER.power;
                const is_a_repeater =
                    that_power == Power.REPEATER_POWER.power;
                if (is_a_source) {
                    std.debug.assert(that_block == .source or
                        that_block == .block);
                    std.debug.assert(this_power <=
                        Power.FROM_SOURCE_POWER.power);
                    this_power = Power.FROM_SOURCE_POWER.power;
                } else if (is_a_repeater) {
                    std.debug.assert(that_block == .repeater);
                    const is_on = that_block.repeater.is_on();
                    const is_facing_me = std.meta.eql(
                        d,
                        that_block.facing().?.back().toDirection(),
                    );
                    if (is_on and is_facing_me) {
                        this_power = Power.FROM_REPEATER_POWER.power;
                    }
                } else {
                    std.debug.print(
                        "this: (y: {}, x: {}) b: {} - that: (y: {}, x: {}) b:{} p: {}\n",
                        .{ y, x, b, ny, nx, that_block, that_power },
                    );
                    unreachable;
                }
            } else if (this_power < that_power) {
                this_power = that_power - 1;
            }
        }
    }
    if (this_power != newstate.power_grid[y][x].power) {
        newstate.power_grid[y][x].power = this_power;
        for (directions) |d| {
            if (d.inbounds(usize, y, x, height, width)) |npos| {
                try mod_stack.append(npos);
            }
        }
    }
}

fn update_block(
    newstate: *State,
    mod_stack: *std.ArrayList(State.Pos),
    y: usize,
    x: usize,
    b: Block,
) Allocator.Error!void {
    std.debug.assert(b == .block);
    var this_power = @as(Power.PowerInt, 0);
    for (directions) |d| {
        if (d.inbounds(usize, y, x, height, width)) |npos| {
            const ny = npos[0];
            const nx = npos[1];
            const that_power =
                newstate.power_grid[ny][nx].power;
            if (that_power < 0) {
                const that_block = newstate.block_grid[ny][nx];
                const is_a_source =
                    that_power == Power.SOURCE_POWER.power;
                const is_a_repeater =
                    that_power == Power.REPEATER_POWER.power;
                if (is_a_source) {
                    std.debug.assert(that_block == .source or
                        that_block == .block);
                    this_power = if (0 <= this_power)
                        Power.FROM_SOURCE_POWER.power
                    else
                        this_power;
                } else if (is_a_repeater) {
                    std.debug.assert(that_block == .repeater);
                    const is_on = that_block.repeater.is_on();
                    const is_facing_me = std.meta.eql(
                        d,
                        that_block.facing().?.back().toDirection(),
                    );
                    if (is_on and is_facing_me) {
                        this_power = Power.SOURCE_POWER.power;
                    }
                } else {
                    std.debug.print(
                        "this: (y: {}, x: {}) b: {} - that: (y: {}, x: {}) b:{} p: {}\n",
                        .{ y, x, b, ny, nx, that_block, that_power },
                    );
                    unreachable;
                }
            } else if (0 <= this_power and
                0 < that_power)
            {
                this_power = Power.BLOCK_MAX_VALUE;
            }
        }
    }
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
            const c_power = if (power_index < char_powers.len)
                char_powers[power_index]
            else blk: {
                std.debug.assert(b == .repeater);
                break :blk char_powers[b.repeater.get_memory()];
            };
            const c_block = switch (b) {
                .empty => @as(u8, ' '),
                .source => @as(u8, 'S'),
                .wire => @as(u8, 'w'),
                .block => @as(u8, 'B'),
                .repeater => @as(u8, 'r'),
            };
            const c_info = switch (b) {
                .empty, .source, .wire, .block => @as(u8, ' '),
                .repeater => |r| "1234"[@enumToInt(r.get_delay())],
            };
            const char_dirs = @as(*const [6]u8, "o^>v<x");
            var c_dirs = @as([5]u8, "     ".*);
            if (b.facing()) |facing| {
                const i = @enumToInt(facing);
                c_dirs[i % c_dirs.len] = char_dirs[i];
            } else {
                // Empty
            }
            // const above = @enumToInt(DirectionEnum.Above);
            const up = @enumToInt(DirectionEnum.Up);
            const right = @enumToInt(DirectionEnum.Right);
            const down = @enumToInt(DirectionEnum.Down);
            const left = @enumToInt(DirectionEnum.Left);
            // const below = @enumToInt(DirectionEnum.Below) % c_dirs.len;
            // std.debug.assert(above == below);
            canvas.*[y][x] = DrawBlock{
                // .up_row = [3]u8{ c_dirs[above], c_dirs[up], ' ' },
                .up_row = [3]u8{ ' ', c_dirs[up], ' ' },
                .mid_row = [3]u8{ c_dirs[left], c_block, c_dirs[right] },
                .bot_row = [3]u8{ c_power, c_dirs[down], c_info },
                // .bot_row = [3]u8{ c_power, c_dirs[down], c_info },
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
