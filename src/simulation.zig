const std = @import("std");
const Allocator = std.mem.Allocator;

const lib_sim = @import("lib_sim");

const block = @import("block.zig");
pub const Block = block.Block;

const Direction = @import("Direction.zig");
const DirectionEnum = Direction.DirectionEnum;
const directions = DirectionEnum.directions;

const power = @import("power.zig");
pub const Power = power.Power;

pub const simulation = lib_sim.SandboxedMut(State, Input){
    .update = update,
};

pub const width = 16;
pub const height = width / 2;
pub const depth = 2;
pub const bounds = [_]usize{ depth, height, width };
pub const State = struct {
    block_grid: []Block,
    power_grid: []Power,

    pub const Pos = [3]usize;

    pub fn get_pos(self: State, i: usize) Pos {
        _ = self;
        const x = i % bounds[2];
        const y = (i / bounds[2]) % bounds[1];
        const z = (i / bounds[2]) / bounds[1];
        return .{ z, y, x };
    }

    pub fn get_index(self: State, pos: Pos) usize {
        _ = self;
        std.debug.assert(pos[0] < bounds[0]);
        std.debug.assert(pos[1] < bounds[1]);
        std.debug.assert(pos[2] < bounds[2]);

        const zoff = pos[0] * bounds[1] * bounds[2];
        const yoff = pos[1] * bounds[2];
        const xoff = pos[2];
        const index = zoff + yoff + xoff;
        return index;
    }

    pub fn get_block_grid(self: State, pos: Pos) Block {
        return self.block_grid[self.get_index(pos)];
    }

    pub fn get_power_grid(self: State, pos: Pos) Power {
        return self.power_grid[self.get_index(pos)];
    }
};

test "State compiles!" {
    std.testing.refAllDeclsRecursive(State);
    std.testing.refAllDeclsRecursive(State.BlockIter);
}

pub const MachineOut = enum { old_out, new_out };
pub const PutBlock = struct { pos: [3]u16, block: Block };
pub const Input = union(enum) {
    step,
    putBlock: PutBlock,
};

fn update(
    state: *State,
    input: Input,
    alloc: Allocator,
) Allocator.Error!void {
    return switch (input) {
        .step => update_step(state, alloc),
        .putBlock => |put| update_putBlock(state, put, alloc),
    };
}

fn update_step(
    state: *State,
    alloc: Allocator,
) Allocator.Error!void {
    var mod_stack = std.ArrayList(State.Pos).init(alloc);
    defer mod_stack.deinit();

    { // push "delayed machines" interactions
        for (state.block_grid, 0..) |b, i| {
            const pos = state.get_pos(i);
            switch (b) {
                .empty,
                .source,
                .wire,
                .block,
                .led,
                => {},
                .repeater => |r| {
                    if (r.next_out() != r.last_out) {
                        if (r.facing.inbounds_arr(
                            usize,
                            pos,
                            bounds,
                        )) |front_pos| {
                            try mod_stack.append(front_pos);
                        } else {
                            // Empty
                        }
                    } else {
                        // Empty
                    }
                },
                .comparator => |c| {
                    if (c.next_out() != c.last_out) {
                        if (c.facing.inbounds_arr(
                            usize,
                            pos,
                            bounds,
                        )) |front_pos| {
                            try mod_stack.append(front_pos);
                        } else {
                            // Empty
                        }
                    } else {
                        // Empty
                    }
                },
                .negator => |n| {
                    if (n.next_out() != n.last_out) {
                        var buffer = @as([DirectionEnum.count]DirectionEnum, undefined);
                        for (n.facing.back().others(&buffer)) |d| {
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
                    } else {
                        // Empty
                    }
                },
            }
        }
    }

    try inner_update(
        @TypeOf(mod_stack),
        state,
        &mod_stack,
        .new_out,
    );

    { // For each repeater, shift input
        for (state.block_grid, 0..) |b, i| {
            const pos = state.get_pos(i);
            if (b != .repeater) continue;
            const rep = b.repeater;
            const back_dir = rep.facing.back();
            const curr_in: u1 =
                if (back_dir.inbounds_arr(usize, pos, bounds)) |bpos|
            blk: {
                const that_power = look_at_power(
                    .new_out,
                    back_dir,
                    state.get_block_grid(bpos),
                    state.get_power_grid(bpos),
                ) catch |err| switch (err) {
                    error.InvalidPower => {
                        std.debug.print(
                            "this: (z: {}, y: {}, x: {}) b: {} - that: (z: {}, y: {}, x: {}) b:{} p: {}\n",
                            .{ pos[0], pos[1], pos[2], b, bpos[0], bpos[1], bpos[2], state.get_block_grid(bpos), state.get_power_grid(bpos) },
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
            state.block_grid[i] = .{ .repeater = rep.shift(curr_in) };
        }
    }

    { // For each comparator, shift input
        for (state.block_grid, 0..) |b, i| {
            const pos = state.get_pos(i);
            if (b != .comparator) continue;
            const comp = b.comparator;
            const back_dir = comp.facing.back();
            const curr_in: u4 =
                if (back_dir.inbounds_arr(usize, pos, bounds)) |bpos|
            blk: {
                const that_power = look_at_power(
                    .new_out,
                    back_dir,
                    state.get_block_grid(bpos),
                    state.get_power_grid(bpos),
                ) catch |err| switch (err) {
                    error.InvalidPower => {
                        std.debug.print(
                            "this: (z: {}, y: {}, x: {}) b: {} - that: (z: {}, y: {}, x: {}) b:{} p: {}\n",
                            .{ pos[0], pos[1], pos[2], b, bpos[0], bpos[1], bpos[2], state.get_block_grid(bpos), state.get_power_grid(bpos) },
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
                            state.get_block_grid(bpos),
                            state.get_power_grid(bpos),
                        ) catch |err| switch (err) {
                            error.InvalidPower => {
                                std.debug.print(
                                    "this: (z: {}, y: {}, x: {}) b: {} - that: (z: {}, y: {}, x: {}) b:{} p: {}\n",
                                    .{ pos[0], pos[1], pos[2], b, bpos[0], bpos[1], bpos[2], state.get_block_grid(bpos), state.get_power_grid(bpos) },
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
            state.block_grid[i] = .{ .comparator = comp.shift(curr_in, highest_side) };
        }
    }

    { // For each negator, shift input
        for (state.block_grid, 0..) |b, i| {
            const pos = state.get_pos(i);
            if (b != .negator) continue;
            const neg = b.negator;
            const back_dir = neg.facing.back();
            const curr_in: u1 =
                if (back_dir.inbounds_arr(usize, pos, bounds)) |bpos|
            blk: {
                const that_power = look_at_power(
                    .new_out,
                    back_dir,
                    state.get_block_grid(bpos),
                    state.get_power_grid(bpos),
                ) catch |err| switch (err) {
                    error.InvalidPower => {
                        std.debug.print(
                            "this: (z: {}, y: {}, x: {}) b: {} - that: (z: {}, y: {}, x: {}) b:{} p: {}\n",
                            .{ pos[0], pos[1], pos[2], b, bpos[0], bpos[1], bpos[2], state.get_power_grid(bpos), state.get_power_grid(bpos) },
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
            state.block_grid[i] = .{ .negator = neg.shift(curr_in) };
        }
    }
}

fn update_putBlock(
    state: *State,
    put: PutBlock,
    alloc: Allocator,
) Allocator.Error!void {
    var mod_stack = std.ArrayList(State.Pos).init(alloc);
    defer mod_stack.deinit();

    { // handle putBlock
        const pos = .{ put.pos[0], put.pos[1], put.pos[2] };
        const idx = state.get_index(pos);
        state.block_grid[idx] = put.block;
        state.power_grid[idx] = switch (put.block) {
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
            if (de.inbounds_arr(usize, pos, bounds)) |npos| {
                try mod_stack.append(npos);
            }
        }
        const should_update = switch (put.block) {
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
            try mod_stack.append(pos);
        }
    }

    try inner_update(
        @TypeOf(mod_stack),
        state,
        &mod_stack,
        .old_out,
    );
}

/// update marked power
/// Note: a block may be marked many times
/// leading to unnecessary updates
fn inner_update(
    comptime Stack: type,
    state: *State,
    mod_stack: *Stack,
    choose_output: MachineOut,
) Allocator.Error!void {
    while (mod_stack.popOrNull()) |pos| {
        const b = state.get_block_grid(pos);
        switch (b) {
            .empty => {
                const empty_is_ok = std.meta.eql(
                    power.EMPTY_POWER,
                    state.get_power_grid(pos),
                );
                std.debug.assert(empty_is_ok);
            },
            .source => {
                const source_is_ok = std.meta.eql(
                    power.SOURCE_POWER,
                    state.get_power_grid(pos),
                );
                std.debug.assert(source_is_ok);
            },
            .wire => try update_wire(
                Stack,
                state,
                mod_stack,
                choose_output,
                pos,
                b,
            ),
            .block, .led => try update_block_or_led(
                Stack,
                state,
                mod_stack,
                choose_output,
                pos,
                b,
            ),
            .repeater => |r| {
                const repeater_is_ok = std.meta.eql(
                    power.REPEATER_POWER,
                    state.get_power_grid(pos),
                );
                std.debug.assert(repeater_is_ok);
                std.debug.assert(r.is_valid());
            },
            .comparator => {
                const comparator_is_ok = std.meta.eql(
                    power.COMPARATOR_POWER,
                    state.get_power_grid(pos),
                );
                std.debug.assert(comparator_is_ok);
            },
            .negator => {
                const negator_is_ok = std.meta.eql(
                    power.NEGATOR_POWER,
                    state.get_power_grid(pos),
                );
                std.debug.assert(negator_is_ok);
            },
        }
    }
}

fn update_wire(
    comptime Stack: type,
    state: *State,
    mod_stack: *Stack,
    choose_output: MachineOut,
    pos: [3]usize,
    b: Block,
) Allocator.Error!void {
    std.debug.assert(b == .wire);
    var this_power = Power.empty;
    for (directions) |de| {
        std.debug.assert(0 <= @intFromEnum(this_power));
        if (de.inbounds_arr(usize, pos, bounds)) |npos| {
            const that_block = state.get_block_grid(npos);
            const that_power = look_at_power(
                choose_output,
                de,
                that_block,
                state.get_power_grid(npos),
            ) catch |err| switch (err) {
                error.InvalidPower => {
                    std.debug.print(
                        "this: (z: {}, y: {}, x: {}) b: {} - that: (z: {}, y: {}, x: {}) b:{} p: {}\n",
                        .{ pos[0], pos[1], pos[2], b, npos[0], npos[1], npos[2], that_block, state.get_power_grid(npos) },
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
    if (this_power != state.get_power_grid(pos)) {
        state.power_grid[state.get_index(pos)] = this_power;
        for (directions) |de| {
            if (de.inbounds_arr(usize, pos, bounds)) |npos| {
                try mod_stack.append(npos);
            }
        }
    }
}

fn update_block_or_led(
    comptime Stack: type,
    state: *State,
    mod_stack: *Stack,
    choose_output: MachineOut,
    pos: [3]usize,
    b: Block,
) Allocator.Error!void {
    std.debug.assert(b == .block or b == .led);
    var this_power = power.BLOCK_OFF_POWER;
    for (directions) |de| {
        std.debug.assert(this_power == power.BLOCK_OFF_POWER or
            this_power == power.BLOCK_ON_POWER or
            this_power == power.SOURCE_POWER);
        if (de.inbounds_arr(usize, pos, bounds)) |npos| {
            const that_block = state.get_block_grid(npos);
            const that_power = look_at_power(
                choose_output,
                de,
                that_block,
                state.get_power_grid(npos),
            ) catch |err| switch (err) {
                error.InvalidPower => {
                    std.debug.print(
                        "this: (z: {}, y: {}, x: {}) b: {} - that: (z: {}, y: {}, x: {}) b:{} p: {}\n",
                        .{ pos[0], pos[1], pos[2], b, npos[0], npos[1], npos[2], that_block, state.get_power_grid(npos) },
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
    if (this_power != state.get_power_grid(pos)) {
        state.power_grid[state.get_index(pos)] = this_power;
        for (directions) |de| {
            if (de.inbounds_arr(usize, pos, bounds)) |npos| {
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

pub fn render_grid(
    state: State,
    alloc: Allocator,
) Allocator.Error![]DrawInfo {
    const canvas: []DrawInfo =
        try alloc.alloc(DrawInfo, depth * height * width);
    for (state.block_grid, 0..) |b, i| {
        const this_power = state.power_grid[i];
        canvas[i] = DrawInfo.init(b, this_power);
    }
    return canvas;
}

pub fn unrender_grid(
    data_slice: []DrawInfo,
    out_state: *State,
) void {
    for (data_slice, 0..) |data, i| {
        const pair = data.to_block_power();
        out_state.block_grid[i] = pair.b;
        out_state.power_grid[i] = pair.p;
    }
}

pub const DrawInfo = struct {
    pub const PowerUint = power.PowerUint;
    pub const BlockType = block.BlockType;
    pub const DirectionEnum = Direction.DirectionEnum;

    power: DrawInfo.PowerUint,
    block_type: DrawInfo.BlockType,
    memory: ?u4,
    info: ?u2,
    dir: ?DrawInfo.DirectionEnum,

    pub fn init(b: Block, this_power: Power) DrawInfo {
        const pwr = switch (this_power) {
            .empty, .one, .two, .three, .four, .five, .six, .seven, .eight, .nine, .ten, .eleven, .twelve, .thirteen, .fourteen, .fifteen, .source => this_power.to_index(),
            .repeater => blk: {
                std.debug.assert(b == .repeater);
                break :blk b.repeater.last_out;
            },
            .comparator => blk: {
                std.debug.assert(b == .comparator);
                break :blk b.comparator.last_out;
            },
            .negator => blk: {
                std.debug.assert(b == .negator);
                break :blk b.negator.last_out;
            },
            _ => unreachable,
        };
        const memory = switch (b) {
            .empty, .source, .wire, .block, .led => null,
            .repeater => |r| r.get_memory(),
            .comparator => |c| c.memory,
            .negator => |n| n.memory,
        };
        const info = switch (b) {
            .empty, .source, .wire, .block, .led, .comparator, .negator => null,
            .repeater => |r| @intFromEnum(r.get_delay()),
        };
        return DrawInfo{
            .power = pwr,
            .block_type = @as(BlockType, b),
            .memory = memory,
            .info = info,
            .dir = b.facing(),
        };
    }

    const Pair = struct { b: Block, p: Power };
    pub fn to_block_power(data: DrawInfo) Pair {
        const b = @as(Block, switch (data.block_type) {
            .empty => .{ .empty = .{} },
            .source => .{ .source = .{} },
            .wire => .{ .wire = .{} },
            .block => .{ .block = .{} },
            .led => .{ .led = .{} },
            .repeater => blk: {
                const rep = block.Repeater.init_all(
                    data.dir.?,
                    @enumFromInt(data.info.?),
                    @intCast(data.memory.?),
                    @intCast(data.power),
                );
                break :blk .{ .repeater = rep };
            },
            .comparator => .{ .comparator = .{
                .facing = data.dir.?,
                .memory = data.memory.?,
                .last_out = @intCast(data.power),
            } },
            .negator => .{ .negator = .{
                .facing = data.dir.?,
                .memory = @intCast(data.memory.?),
                .last_out = @intCast(data.power),
            } },
        });
        const this_power = @as(Power, switch (data.block_type) {
            .empty,
            .source,
            .wire,
            .block,
            .led,
            => @enumFromInt(data.power),
            .repeater => power.Power.repeater,
            .comparator => power.Power.comparator,
            .negator => power.Power.negator,
        });
        return .{
            .b = b,
            .p = this_power,
        };
    }
};
