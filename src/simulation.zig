const std = @import("std");
const Allocator = std.mem.Allocator;

const lib_sim = @import("lib_sim");

const block = @import("block.zig");
const Block = block.Block;

const Direction = @import("Direction.zig");
const DirectionEnum = Direction.DirectionEnum;
const directions = DirectionEnum.directions;

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

pub const MachineOut = enum { old_out, new_out };
pub const PutBlock = struct { z: u8, y: u8, x: u8, block: Block };
pub const Input = union(enum) {
    step,
    putBlock: PutBlock,
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
    return switch (input) {
        .step => update_step(state, alloc),
        .putBlock => |put| update_putBlock(state, put, alloc),
    };
}

pub fn update_step(
    state: State,
    alloc: Allocator,
) Allocator.Error!State {
    var newstate = state;

    var mod_stack = std.ArrayList(State.Pos).init(alloc);
    defer mod_stack.deinit();

    { // push "delayed machines" interactions
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
                .led,
                => {},
                .repeater,
                .comparator,
                => {
                    // TODO: The following can be done!
                    // Note: here should be a great place
                    // to "do nothing" if the machine's
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
                    // TODO: The following can be done!
                    // Note: here should be a great place
                    // to "do nothing" if negator's
                    // output was the same.
                    // But we don't have this information
                    // (only what we will output now)
                    var buffer = @as([DirectionEnum.count]DirectionEnum, undefined);
                    for (b.facing().?.back().others(&buffer)) |d| {
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

    try inner_update(
        @TypeOf(mod_stack),
        &newstate,
        &mod_stack,
        .new_out,
    );

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
                const that_power = look_at_power(
                    .new_out,
                    back_dir,
                    newstate.block_grid[bpos[0]][bpos[1]][bpos[2]],
                    newstate.power_grid[bpos[0]][bpos[1]][bpos[2]],
                ) catch |err| switch (err) {
                    error.InvalidPower => {
                        std.debug.print(
                            "this: (z: {}, y: {}, x: {}) b: {} - that: (z: {}, y: {}, x: {}) b:{} p: {}\n",
                            .{ z, y, x, b, bpos[0], bpos[1], bpos[2], newstate.block_grid[bpos[0]][bpos[1]][bpos[2]], newstate.power_grid[bpos[0]][bpos[1]][bpos[2]] },
                        );
                        unreachable;
                    },
                };
                break :blk switch (that_power) {
                    .empty => 0,
                    .one, .two, .three, .four, .five, .six, .seven, .eight, .nine, .ten, .eleven, .twelve, .thirteen, .fourteen, .fifteen => 1,
                    .source, .repeater, .comparator, .negator => 1,
                    _ => unreachable,
                };
            } else 0;
            newstate.block_grid[z][y][x] = .{ .repeater = rep.shift(curr_in) };
        }
    }

    { // For each comparator, shift input
        var block_it = State.BlockIter{};
        while (block_it.next_pos()) |pos| {
            const z = pos[0];
            const y = pos[1];
            const x = pos[2];
            const b = newstate.block_grid[z][y][x];
            if (b != .comparator) continue;
            const comp = b.comparator;
            const back_dir = comp.facing.back();
            const curr_in: u4 =
                if (back_dir.inbounds_arr(usize, pos, bounds)) |bpos|
            blk: {
                const that_power = look_at_power(
                    .new_out,
                    back_dir,
                    newstate.block_grid[bpos[0]][bpos[1]][bpos[2]],
                    newstate.power_grid[bpos[0]][bpos[1]][bpos[2]],
                ) catch |err| switch (err) {
                    error.InvalidPower => {
                        std.debug.print(
                            "this: (z: {}, y: {}, x: {}) b: {} - that: (z: {}, y: {}, x: {}) b:{} p: {}\n",
                            .{ z, y, x, b, bpos[0], bpos[1], bpos[2], newstate.block_grid[bpos[0]][bpos[1]][bpos[2]], newstate.power_grid[bpos[0]][bpos[1]][bpos[2]] },
                        );
                        unreachable;
                    },
                };
                break :blk @intCast(switch (that_power) {
                    .empty, .one, .two, .three, .four, .five, .six, .seven, .eight, .nine, .ten, .eleven, .twelve, .thirteen, .fourteen, .fifteen => @intFromEnum(that_power),
                    .source, .repeater, .negator => 15,
                    .comparator => unreachable,
                    _ => unreachable,
                });
            } else 0;
            const highest_side: u4 = blk: {
                var h = @as(u4, 0);
                var buffer = @as([DirectionEnum.count]DirectionEnum, undefined);
                for (back_dir.others(&buffer)) |de| {
                    if (std.meta.eql(de, comp.facing)) {
                        continue;
                    }
                    if (de.inbounds_arr(usize, pos, bounds)) |bpos| {
                        const that_power = look_at_power(
                            .new_out,
                            de,
                            newstate.block_grid[bpos[0]][bpos[1]][bpos[2]],
                            newstate.power_grid[bpos[0]][bpos[1]][bpos[2]],
                        ) catch |err| switch (err) {
                            error.InvalidPower => {
                                std.debug.print(
                                    "this: (z: {}, y: {}, x: {}) b: {} - that: (z: {}, y: {}, x: {}) b:{} p: {}\n",
                                    .{ z, y, x, b, bpos[0], bpos[1], bpos[2], newstate.block_grid[bpos[0]][bpos[1]][bpos[2]], newstate.power_grid[bpos[0]][bpos[1]][bpos[2]] },
                                );
                                unreachable;
                            },
                        };
                        const side: u4 = @intCast(switch (that_power) {
                            .empty, .one, .two, .three, .four, .five, .six, .seven, .eight, .nine, .ten, .eleven, .twelve, .thirteen, .fourteen, .fifteen => @intFromEnum(that_power),
                            .source, .repeater, .negator => 15,
                            .comparator => unreachable,
                            _ => unreachable,
                        });
                        if (h < side) {
                            h = side;
                        }
                    }
                }
                break :blk h;
            };
            newstate.block_grid[z][y][x] = .{ .comparator = comp.shift(curr_in, highest_side) };
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
                const that_power = look_at_power(
                    .new_out,
                    back_dir,
                    newstate.block_grid[bpos[0]][bpos[1]][bpos[2]],
                    newstate.power_grid[bpos[0]][bpos[1]][bpos[2]],
                ) catch |err| switch (err) {
                    error.InvalidPower => {
                        std.debug.print(
                            "this: (z: {}, y: {}, x: {}) b: {} - that: (z: {}, y: {}, x: {}) b:{} p: {}\n",
                            .{ z, y, x, b, bpos[0], bpos[1], bpos[2], newstate.block_grid[bpos[0]][bpos[1]][bpos[2]], newstate.power_grid[bpos[0]][bpos[1]][bpos[2]] },
                        );
                        unreachable;
                    },
                };
                break :blk switch (that_power) {
                    .empty => 0,
                    .one, .two, .three, .four, .five, .six, .seven, .eight, .nine, .ten, .eleven, .twelve, .thirteen, .fourteen, .fifteen => 1,
                    .source, .repeater, .comparator, .negator => 1,
                    else => unreachable,
                };
            } else 0;
            newstate.block_grid[z][y][x] = .{ .negator = neg.shift(curr_in) };
        }
    }
    return newstate;
}

pub fn update_putBlock(
    state: State,
    put: PutBlock,
    alloc: Allocator,
) Allocator.Error!State {
    var newstate = state;

    var mod_stack = std.ArrayList(State.Pos).init(alloc);
    defer mod_stack.deinit();

    { // handle putBlock
        const i = put;
        newstate.block_grid[i.z][i.y][i.x] = i.block;
        newstate.power_grid[i.z][i.y][i.x] = switch (i.block) {
            .empty => power.EMPTY_POWER,
            .source => power.SOURCE_POWER,
            .wire,
            .block,
            .led,
            => power.BLOCK_OFF_POWER,
            .repeater => |r| blk: {
                std.debug.assert(r.is_valid());
                break :blk power.REPEATER_POWER;
            },
            .comparator => power.COMPARATOR_POWER,
            .negator => power.NEGATOR_POWER,
        };
        for (directions) |de| {
            if (de.inbounds(usize, i.z, i.y, i.x, bounds)) |npos| {
                try mod_stack.append(npos);
            }
        }
        const should_update = switch (i.block) {
            .empty,
            .source,
            .repeater,
            .comparator,
            .negator,
            => false,
            .wire,
            .block,
            .led,
            => true,
        };
        if (should_update) {
            try mod_stack.append(State.Pos{ i.z, i.y, i.x });
        }
    }

    try inner_update(
        @TypeOf(mod_stack),
        &newstate,
        &mod_stack,
        .old_out,
    );
    return newstate;
}

/// update marked power
/// Note: a block may be marked many times
/// leading to unnecessary updates
fn inner_update(
    comptime Stack: type,
    newstate: *State,
    mod_stack: *Stack,
    choose_output: MachineOut,
) Allocator.Error!void {
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
                Stack,
                newstate,
                mod_stack,
                choose_output,
                z,
                y,
                x,
                b,
            ),
            .block, .led => try update_block_or_led(
                Stack,
                newstate,
                mod_stack,
                choose_output,
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
            .comparator => {
                const comparator_is_ok = std.meta.eql(
                    power.COMPARATOR_POWER,
                    newstate.power_grid[z][y][x],
                );
                std.debug.assert(comparator_is_ok);
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

fn update_wire(
    comptime Stack: type,
    newstate: *State,
    mod_stack: *Stack,
    choose_output: MachineOut,
    z: usize,
    y: usize,
    x: usize,
    b: Block,
) Allocator.Error!void {
    std.debug.assert(b == .wire);
    var this_power = Power.empty;
    for (directions) |de| {
        std.debug.assert(0 <= @intFromEnum(this_power));
        if (de.inbounds(usize, z, y, x, bounds)) |npos| {
            const nz = npos[0];
            const ny = npos[1];
            const nx = npos[2];
            const that_block = newstate.block_grid[nz][ny][nx];
            const that_power = look_at_power(
                choose_output,
                de,
                that_block,
                newstate.power_grid[nz][ny][nx],
            ) catch |err| switch (err) {
                error.InvalidPower => {
                    std.debug.print(
                        "this: (z: {}, y: {}, x: {}) b: {} - that: (z: {}, y: {}, x: {}) b:{} p: {}\n",
                        .{ z, y, x, b, nz, ny, nx, that_block, newstate.power_grid[nz][ny][nx] },
                    );
                    unreachable;
                },
            };
            this_power = switch (that_power) {
                .source => power.FROM_SOURCE_POWER,
                .repeater => power.FROM_REPEATER_POWER,
                .negator => power.FROM_NEGATOR_POWER,
                .empty => this_power,
                .one,
                .two,
                .three,
                .four,
                .five,
                .six,
                .seven,
                .eight,
                .nine,
                .ten,
                .eleven,
                .twelve,
                .thirteen,
                .fourteen,
                .fifteen,
                => if (@intFromEnum(this_power) < @intFromEnum(that_power))
                    @enumFromInt(@intFromEnum(that_power) - 1)
                else
                    this_power,
                .comparator => unreachable,
                _ => unreachable,
            };
        }
    }
    if (this_power != newstate.power_grid[z][y][x]) {
        newstate.power_grid[z][y][x] = this_power;
        for (directions) |de| {
            if (de.inbounds(usize, z, y, x, bounds)) |npos| {
                try mod_stack.append(npos);
            }
        }
    }
}

fn update_block_or_led(
    comptime Stack: type,
    newstate: *State,
    mod_stack: *Stack,
    choose_output: MachineOut,
    z: usize,
    y: usize,
    x: usize,
    b: Block,
) Allocator.Error!void {
    std.debug.assert(b == .block or b == .led);
    var this_power = power.BLOCK_OFF_POWER;
    for (directions) |de| {
        std.debug.assert(this_power == power.BLOCK_OFF_POWER or
            this_power == power.BLOCK_ON_POWER or
            this_power == power.SOURCE_POWER);
        if (de.inbounds(usize, z, y, x, bounds)) |npos| {
            const nz = npos[0];
            const ny = npos[1];
            const nx = npos[2];
            const that_block = newstate.block_grid[nz][ny][nx];
            const that_power = look_at_power(
                choose_output,
                de,
                that_block,
                newstate.power_grid[nz][ny][nx],
            ) catch |err| switch (err) {
                error.InvalidPower => {
                    std.debug.print(
                        "this: (z: {}, y: {}, x: {}) b: {} - that: (z: {}, y: {}, x: {}) b:{} p: {}\n",
                        .{ z, y, x, b, nz, ny, nx, that_block, newstate.power_grid[nz][ny][nx] },
                    );
                    unreachable;
                },
            };
            this_power = switch (that_power) {
                .source => if (0 <= @intFromEnum(this_power))
                    power.BLOCK_ON_POWER
                else
                    this_power,
                .repeater => power.SOURCE_POWER,
                .negator => power.SOURCE_POWER,
                .empty => this_power,
                .one => blk: {
                    std.debug.assert(that_block == .wire or
                        that_block == .block or
                        that_block == .led or
                        that_block == .comparator);
                    break :blk if (this_power == power.BLOCK_OFF_POWER)
                        if (that_block == .block or
                            that_block == .led)
                            power.BLOCK_OFF_POWER
                        else
                            power.BLOCK_ON_POWER
                    else
                        this_power;
                },
                .two, .three, .four, .five, .six, .seven, .eight, .nine, .ten, .eleven, .twelve, .thirteen, .fourteen, .fifteen => blk: {
                    std.debug.assert(0 < @intFromEnum(that_power));
                    break :blk if (this_power == power.BLOCK_OFF_POWER)
                        power.BLOCK_ON_POWER
                    else
                        this_power;
                },
                .comparator => unreachable,
                _ => unreachable,
            };
        }
    }
    if (this_power != newstate.power_grid[z][y][x]) {
        newstate.power_grid[z][y][x] = this_power;
        for (directions) |de| {
            if (de.inbounds(usize, z, y, x, bounds)) |npos| {
                try mod_stack.append(npos);
            }
        }
    }
}

fn look_at_power(
    choose_output: MachineOut,
    from_de: DirectionEnum,
    b: Block,
    p: Power,
) power.InvalidPowerError!Power {
    return switch (p) {
        .empty, .one, .two, .three, .four, .five, .six, .seven, .eight, .nine, .ten, .eleven, .twelve, .thirteen, .fourteen, .fifteen => p,
        .source => blk: {
            std.debug.assert(b == .source or
                b == .block or
                b == .led);
            break :blk p;
        },
        .repeater => blk: {
            std.debug.assert(b == .repeater);
            const is_on = switch (choose_output) {
                .old_out => b.repeater.last_out == 1,
                .new_out => b.repeater.is_on(),
            };
            const is_facing_me = std.meta.eql(
                from_de,
                b.facing().?.back(),
            );
            break :blk if (is_on and is_facing_me)
                p
            else
                Power.zero;
        },
        .comparator => blk: {
            std.debug.assert(b == .comparator);
            const next_out = switch (choose_output) {
                .old_out => b.comparator.last_out,
                .new_out => b.comparator.next_out(),
            };
            const is_facing_me = std.meta.eql(
                from_de,
                b.facing().?.back(),
            );
            break :blk if (next_out > 0 and is_facing_me)
                @enumFromInt(
                    @as(i5, next_out) +% 1,
                )
            else
                Power.zero;
        },
        .negator => blk: {
            std.debug.assert(b == .negator);
            const is_on = switch (choose_output) {
                .old_out => b.negator.last_out == 1,
                .new_out => b.negator.is_on(),
            };
            const is_backing_me = std.meta.eql(
                from_de,
                b.facing().?,
            );
            break :blk if (is_on and !is_backing_me)
                p
            else
                Power.zero;
        },
        _ => error.InvalidPower,
    };
}

fn default_render_block(b: Block, this_power: Power) DrawBlock {
    const char_powers = @as(*const [17]u8, " 123456789abcdef*");
    const power_index = this_power.to_index();
    const c_power = if (power_index < char_powers.len)
        char_powers[power_index]
    else blk: {
        if (power_index == power.REPEATER_POWER.to_index()) {
            std.debug.assert(b == .repeater);
            break :blk char_powers[b.repeater.last_out];
        } else if (power_index == power.COMPARATOR_POWER.to_index()) {
            std.debug.assert(b == .comparator);
            break :blk char_powers[b.comparator.last_out];
        } else if (power_index == power.NEGATOR_POWER.to_index()) {
            std.debug.assert(b == .negator);
            break :blk char_powers[b.negator.last_out];
        } else {
            unreachable;
        }
    };
    const c_block = switch (b) {
        .empty => @as(u8, ' '),
        .source => @as(u8, 'S'),
        .wire => @as(u8, 'w'),
        .block => @as(u8, 'B'),
        .led => @as(u8, 'L'),
        .repeater => @as(u8, 'r'),
        .comparator => @as(u8, 'c'),
        .negator => @as(u8, 'n'),
    };
    const c_mem = switch (b) {
        .empty, .source, .wire, .block, .led => @as(u8, ' '),
        .repeater => |r| char_powers[r.get_memory()],
        .comparator => |c| char_powers[c.memory],
        .negator => |n| char_powers[n.memory],
    };
    const c_info = switch (b) {
        .empty, .source, .wire, .block, .led, .comparator, .negator => @as(u8, ' '),
        .repeater => |r| "1234"[@intFromEnum(r.get_delay())],
    };
    const char_dirs = @as(*const [6]u8, "o^>v<x");
    var c_dirs = @as([5]u8, "     ".*);
    if (b.facing()) |facing| {
        const i = @intFromEnum(facing);
        c_dirs[i % c_dirs.len] = char_dirs[i];
    } else {
        // Empty
    }
    const above = @intFromEnum(DirectionEnum.Above);
    const up = @intFromEnum(DirectionEnum.Up);
    const right = @intFromEnum(DirectionEnum.Right);
    const down = @intFromEnum(DirectionEnum.Down);
    const left = @intFromEnum(DirectionEnum.Left);
    const below = @intFromEnum(DirectionEnum.Below) % c_dirs.len;
    std.debug.assert(above == below);
    return DrawBlock{
        .up_row = [3]u8{ c_dirs[above], c_dirs[up], c_info },
        .mid_row = [3]u8{ c_dirs[left], c_block, c_dirs[right] },
        .bot_row = [3]u8{ c_power, c_dirs[down], c_mem },
    };
}

pub fn render_block(b: Block, this_power: Power) DrawBlock {
    return if (b == .led)
        if (this_power == power.SOURCE_POWER)
            DrawBlock{
                .up_row = "***".*,
                .mid_row = "***".*,
                .bot_row = "***".*,
            }
        else if (this_power == power.BLOCK_ON_POWER)
            DrawBlock{
                .up_row = "***".*,
                .mid_row = "*L*".*,
                .bot_row = "***".*,
            }
        else
            default_render_block(b, this_power)
    else
        default_render_block(b, this_power);
}

pub fn render_grid(
    state: State,
    alloc: Allocator,
) Allocator.Error!Render {
    const canvas: *[depth][height][width]DrawBlock =
        try alloc.create([depth][height][width]DrawBlock);
    for (state.block_grid, 0..) |plane, z| {
        for (plane, 0..) |row, y| {
            for (row, 0..) |b, x| {
                const this_power = state.power_grid[z][y][x];
                canvas.*[z][y][x] = render_block(b, this_power);
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
