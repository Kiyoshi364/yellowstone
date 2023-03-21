const std = @import("std");
const Allocator = std.mem.Allocator;

const lib_sim = @import("lib_sim");

const block = @import("block.zig");
const Block = block.Block;

const Direction = @import("Direction.zig");
const DirectionEnum = Direction.DirectionEnum;
const directions = Direction.directions;

const power = @import("power.zig");
const Power = power.Power;

pub const simulation = lib_sim.Sandboxed(State, Input){
    .update = update,
};

pub const width = 16;
pub const height = width / 2;
pub const depth = 2;
pub const bounds = [_]usize{ depth, height, width };
pub const State = struct {
    block_grid: [depth][height][width]Block,
    power_grid: [depth][height][width]Power,

    pub const Pos = [3]usize;

    const BlockIter = struct {
        z: usize = 0,
        y: usize = 0,
        x: usize = 0,

        pub fn next_pos(self: *BlockIter) ?State.Pos {
            if (self.z < depth) {
                std.debug.assert(self.y < height);
                std.debug.assert(self.x < width);
                const pos = State.Pos{ self.z, self.y, self.x };
                if (self.x < width - 1) {
                    self.*.x += 1;
                } else {
                    std.debug.assert(self.x == width - 1);
                    self.*.x = 0;
                    if (self.y < height - 1) {
                        self.*.y += 1;
                    } else {
                        std.debug.assert(self.y == height - 1);
                        self.*.y = 0;
                        self.*.z += 1;
                    }
                }
                return pos;
            } else {
                return null;
            }
        }

        pub fn next_block(self: *BlockIter, state: State) ?Block {
            return if (self.next_pos()) |pos|
                state.block_grid[pos[0]][pos[1]][pos[2]]
            else
                null;
        }

        pub fn next_power(self: *BlockIter, state: State) ?Power {
            return if (self.next_pos()) |pos|
                state.power_grid[pos[0]][pos[1]][pos[2]]
            else
                null;
        }
    };
};

test "State compiles!" {
    std.testing.refAllDeclsRecursive(State);
    std.testing.refAllDeclsRecursive(State.BlockIter);
}

pub const Input = union(enum) {
    empty,
    putBlock: struct { z: u8, y: u8, x: u8, block: Block },
};

pub const Render = *const [depth][height][width]DrawBlock;

pub const emptyState = @as(State, .{
    .block_grid = .{.{.{.{ .empty = .{} }} ** width} ** height} ** depth,
    .power_grid = .{.{.{.empty} ** width} ** height} ** depth,
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
            const z = pos[0];
            const y = pos[1];
            const x = pos[2];
            const b = newstate.block_grid[z][y][x];
            switch (b) {
                .empty,
                .source,
                .wire,
                .block,
                => {},
                .repeater => {
                    // Note: here should be a great place
                    // to "do nothing" if repeater's
                    // output was the same.
                    // But we don't have this information
                    // (only what we will output now)
                    if (b.facing().?.inbounds_arr(
                        usize,
                        pos,
                        bounds,
                    )) |front_pos| {
                        try mod_stack.append(front_pos);
                    } else {
                        // Empty
                    }
                },
                .negator => {
                    // Note: here should be a great place
                    // to "do nothing" if negator's
                    // output was the same.
                    // But we don't have this information
                    // (only what we will output now)
                    var buffer = @as([DirectionEnum.count]Direction, undefined);
                    for (b.facing().?.back().toDirection().others(&buffer)) |d| {
                        if (d.inbounds_arr(
                            usize,
                            pos,
                            bounds,
                        )) |npos| {
                            try mod_stack.append(npos);
                        } else {
                            // Empty
                        }
                    }
                },
            }
        }
    }

    { // handle input
        switch (input) {
            .empty => {},
            .putBlock => |i| {
                newstate.block_grid[i.z][i.y][i.x] = i.block;
                newstate.power_grid[i.z][i.y][i.x] = switch (i.block) {
                    .empty => power.EMPTY_POWER,
                    .source => power.SOURCE_POWER,
                    .wire,
                    .block,
                    => power.BLOCK_OFF_POWER,
                    .repeater => |r| blk: {
                        std.debug.assert(r.is_valid());
                        break :blk power.REPEATER_POWER;
                    },
                    .negator => power.NEGATOR_POWER,
                };
                for (directions) |d| {
                    if (d.inbounds(usize, i.z, i.y, i.x, bounds)) |npos| {
                        try mod_stack.append(npos);
                    }
                }
                const should_update = switch (i.block) {
                    .empty,
                    .source,
                    .repeater,
                    .negator,
                    => false,
                    .wire,
                    .block,
                    => true,
                };
                if (should_update) {
                    try mod_stack.append(State.Pos{ i.z, i.y, i.x });
                }
            },
        }
    }

    { // update marked power
        // Note: a block may be marked many times
        // leading to unnecessary updates
        while (mod_stack.popOrNull()) |pos| {
            const z = pos[0];
            const y = pos[1];
            const x = pos[2];
            const b = newstate.block_grid[z][y][x];
            switch (b) {
                .empty => {
                    const empty_is_ok = std.meta.eql(
                        power.EMPTY_POWER,
                        newstate.power_grid[z][y][x],
                    );
                    std.debug.assert(empty_is_ok);
                },
                .source => {
                    const source_is_ok = std.meta.eql(
                        power.SOURCE_POWER,
                        newstate.power_grid[z][y][x],
                    );
                    std.debug.assert(source_is_ok);
                },
                .wire => try update_wire(
                    &newstate,
                    &mod_stack,
                    z,
                    y,
                    x,
                    b,
                ),
                .block => try update_block(
                    &newstate,
                    &mod_stack,
                    z,
                    y,
                    x,
                    b,
                ),
                .repeater => |r| {
                    const repeater_is_ok = std.meta.eql(
                        power.REPEATER_POWER,
                        newstate.power_grid[z][y][x],
                    );
                    std.debug.assert(repeater_is_ok);
                    std.debug.assert(r.is_valid());
                },
                .negator => {
                    const negator_is_ok = std.meta.eql(
                        power.NEGATOR_POWER,
                        newstate.power_grid[z][y][x],
                    );
                    std.debug.assert(negator_is_ok);
                },
            }
        }
    }

    { // For each repeater, shift input
        var block_it = State.BlockIter{};
        while (block_it.next_pos()) |pos| {
            const z = pos[0];
            const y = pos[1];
            const x = pos[2];
            const b = newstate.block_grid[z][y][x];
            if (b != .repeater) continue;
            const rep = b.repeater;
            const back_dir = rep.facing.back();
            const curr_in: u1 =
                if (back_dir.inbounds_arr(usize, pos, bounds)) |bpos|
            blk: {
                const that_power = newstate.power_grid[bpos[0]][bpos[1]][bpos[2]];
                break :blk switch (that_power) {
                    .empty => 0,
                    .one, .two, .three, .four, .five, .six, .seven, .eight, .nine, .ten, .eleven, .twelve, .thirteen, .fourteen, .fifteen => 1,
                    .source => 1,
                    .repeater => blk2: {
                        const prev_b_block =
                            state.block_grid[bpos[0]][bpos[1]][bpos[2]];
                        std.debug.assert(prev_b_block == .repeater);
                        break :blk2 prev_b_block.repeater.next_out();
                    },
                    .negator => blk2: {
                        const prev_b_block =
                            state.block_grid[bpos[0]][bpos[1]][bpos[2]];
                        std.debug.assert(prev_b_block == .negator);
                        break :blk2 prev_b_block.negator.next_out();
                    },
                    _ => unreachable,
                };
            } else 0;
            newstate.block_grid[z][y][x] = .{ .repeater = rep.shift(curr_in) };
        }
    }

    { // For each negator, shift input
        var block_it = State.BlockIter{};
        while (block_it.next_pos()) |pos| {
            const z = pos[0];
            const y = pos[1];
            const x = pos[2];
            const b = newstate.block_grid[z][y][x];
            if (b != .negator) continue;
            const neg = b.negator;
            const back_dir = neg.facing.back();
            const curr_in: u1 =
                if (back_dir.inbounds_arr(usize, pos, bounds)) |bpos|
            blk: {
                const that_power = newstate.power_grid[bpos[0]][bpos[1]][bpos[2]];
                break :blk switch (that_power) {
                    .empty => 0,
                    .one, .two, .three, .four, .five, .six, .seven, .eight, .nine, .ten, .eleven, .twelve, .thirteen, .fourteen, .fifteen => 1,
                    .source => 1,
                    .repeater => blk2: {
                        const prev_b_block =
                            state.block_grid[bpos[0]][bpos[1]][bpos[2]];
                        std.debug.assert(prev_b_block == .repeater);
                        break :blk2 prev_b_block.repeater.next_out();
                    },
                    .negator => blk2: {
                        const prev_b_block =
                            state.block_grid[bpos[0]][bpos[1]][bpos[2]];
                        std.debug.assert(prev_b_block == .negator);
                        break :blk2 prev_b_block.negator.next_out();
                    },
                    else => unreachable,
                };
            } else 0;
            newstate.block_grid[z][y][x] = .{ .negator = neg.shift(curr_in) };
        }
    }
    return newstate;
}

fn update_wire(
    newstate: *State,
    mod_stack: *std.ArrayList(State.Pos),
    z: usize,
    y: usize,
    x: usize,
    b: Block,
) Allocator.Error!void {
    std.debug.assert(b == .wire);
    var this_power = Power.empty;
    for (directions) |d| {
        if (d.inbounds(usize, z, y, x, bounds)) |npos| {
            const nz = npos[0];
            const ny = npos[1];
            const nx = npos[2];
            const that_power = newstate.power_grid[nz][ny][nx];
            const that_block = newstate.block_grid[nz][ny][nx];
            std.debug.assert(0 <= @enumToInt(this_power));
            switch (that_power) {
                .source => {
                    std.debug.assert(that_block == .source or
                        that_block == .block);
                    std.debug.assert(@enumToInt(this_power) <=
                        @enumToInt(power.FROM_SOURCE_POWER));
                    this_power = power.FROM_SOURCE_POWER;
                },
                .repeater => {
                    std.debug.assert(that_block == .repeater);
                    const is_on = that_block.repeater.is_on();
                    const is_facing_me = std.meta.eql(
                        d,
                        that_block.facing().?.back().toDirection(),
                    );
                    if (is_on and is_facing_me) {
                        this_power = power.FROM_REPEATER_POWER;
                    }
                },
                .negator => {
                    std.debug.assert(that_block == .negator);
                    const is_on = that_block.negator.is_on();
                    const is_backing_me = std.meta.eql(
                        d,
                        that_block.facing().?.toDirection(),
                    );
                    if (is_on and !is_backing_me) {
                        this_power = power.FROM_SOURCE_POWER;
                    }
                },
                .empty, .one, .two, .three, .four, .five, .six, .seven, .eight, .nine, .ten, .eleven, .twelve, .thirteen, .fourteen, .fifteen => {
                    std.debug.assert(0 <= @enumToInt(that_power));
                    if (@enumToInt(this_power) < @enumToInt(that_power)) {
                        this_power = @intToEnum(
                            Power,
                            @enumToInt(that_power) - 1,
                        );
                    }
                },
                _ => {
                    std.debug.print(
                        "this: (z: {}, y: {}, x: {}) b: {} - that: (z: {}, y: {}, x: {}) b:{} p: {}\n",
                        .{ z, y, x, b, nz, ny, nx, that_block, that_power },
                    );
                    unreachable;
                },
            }
        }
    }
    if (this_power != newstate.power_grid[z][y][x]) {
        newstate.power_grid[z][y][x] = this_power;
        for (directions) |d| {
            if (d.inbounds(usize, z, y, x, bounds)) |npos| {
                try mod_stack.append(npos);
            }
        }
    }
}

fn update_block(
    newstate: *State,
    mod_stack: *std.ArrayList(State.Pos),
    z: usize,
    y: usize,
    x: usize,
    b: Block,
) Allocator.Error!void {
    std.debug.assert(b == .block);
    var this_power = Power.empty;
    for (directions) |d| {
        if (d.inbounds(usize, z, y, x, bounds)) |npos| {
            const nz = npos[0];
            const ny = npos[1];
            const nx = npos[2];
            const that_power = newstate.power_grid[nz][ny][nx];
            const that_block = newstate.block_grid[nz][ny][nx];
            switch (that_power) {
                .source => {
                    std.debug.assert(that_block == .source or
                        that_block == .block);
                    this_power = if (0 <= @enumToInt(this_power))
                        power.FROM_SOURCE_POWER
                    else
                        this_power;
                },
                .repeater => {
                    std.debug.assert(that_block == .repeater);
                    const is_on = that_block.repeater.is_on();
                    const is_facing_me = std.meta.eql(
                        d,
                        that_block.facing().?.back().toDirection(),
                    );
                    if (is_on and is_facing_me) {
                        this_power = power.SOURCE_POWER;
                    }
                },
                .negator => {
                    std.debug.assert(that_block == .negator);
                    const is_on = that_block.negator.is_on();
                    const is_backing_me = std.meta.eql(
                        d,
                        that_block.facing().?.toDirection(),
                    );
                    if (is_on and !is_backing_me) {
                        this_power = power.SOURCE_POWER;
                    }
                },
                .empty => {},
                .one => {
                    std.debug.assert(@enumToInt(that_power) == 1);
                    if (0 <= @enumToInt(this_power)) {
                        std.debug.assert(that_block == .wire or
                            that_block == .block);
                        this_power = if (that_block == .block)
                            power.BLOCK_OFF_POWER
                        else
                            power.BLOCK_ON_POWER;
                    }
                },
                .two, .three, .four, .five, .six, .seven, .eight, .nine, .ten, .eleven, .twelve, .thirteen, .fourteen, .fifteen => {
                    std.debug.assert(0 < @enumToInt(that_power));
                    if (0 <= @enumToInt(this_power)) {
                        this_power = power.BLOCK_ON_POWER;
                    }
                },
                _ => {
                    std.debug.print(
                        "this: (y: {}, x: {}) b: {} - that: (y: {}, x: {}) b:{} p: {}\n",
                        .{ y, x, b, ny, nx, that_block, that_power },
                    );
                    unreachable;
                },
            }
        }
    }
    if (this_power != newstate.power_grid[z][y][x]) {
        newstate.power_grid[z][y][x] = this_power;
        for (directions) |d| {
            if (d.inbounds(usize, z, y, x, bounds)) |npos| {
                try mod_stack.append(npos);
            }
        }
    }
}

pub fn render(
    state: State,
    alloc: Allocator,
) Allocator.Error!Render {
    const canvas: *[depth][height][width]DrawBlock =
        try alloc.create([depth][height][width]DrawBlock);
    for (state.block_grid, 0..) |plane, z| {
        for (plane, 0..) |row, y| {
            for (row, 0..) |b, x| {
                const char_powers = @as(*const [17]u8, " 123456789abcdef*");
                const power_index = state.power_grid[z][y][x].to_index();
                const c_power = if (power_index < char_powers.len)
                    char_powers[power_index]
                else blk: {
                    if (power_index == power.REPEATER_POWER.to_index()) {
                        std.debug.assert(b == .repeater);
                        break :blk char_powers[b.repeater.get_memory()];
                    } else if (power_index == power.NEGATOR_POWER.to_index()) {
                        std.debug.assert(b == .negator);
                        break :blk char_powers[b.negator.memory];
                    } else {
                        unreachable;
                    }
                };
                const c_block = switch (b) {
                    .empty => @as(u8, ' '),
                    .source => @as(u8, 'S'),
                    .wire => @as(u8, 'w'),
                    .block => @as(u8, 'B'),
                    .repeater => @as(u8, 'r'),
                    .negator => @as(u8, 'n'),
                };
                const c_info = switch (b) {
                    .empty, .source, .wire, .block, .negator => @as(u8, ' '),
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
                const above = @enumToInt(DirectionEnum.Above);
                const up = @enumToInt(DirectionEnum.Up);
                const right = @enumToInt(DirectionEnum.Right);
                const down = @enumToInt(DirectionEnum.Down);
                const left = @enumToInt(DirectionEnum.Left);
                const below = @enumToInt(DirectionEnum.Below) % c_dirs.len;
                std.debug.assert(above == below);
                canvas.*[z][y][x] = DrawBlock{
                    .up_row = [3]u8{ c_dirs[above], c_dirs[up], ' ' },
                    .mid_row = [3]u8{ c_dirs[left], c_block, c_dirs[right] },
                    .bot_row = [3]u8{ c_power, c_dirs[down], c_info },
                };
            }
        }
    }
    return canvas;
}

pub const DrawBlock = struct {
    up_row: [3]u8,
    mid_row: [3]u8,
    bot_row: [3]u8,
};
