const std = @import("std");
const Allocator = std.mem.Allocator;

const block = @import("block.zig");
pub const Block = block.Block;

const Direction = @import("Direction.zig");
const DirectionEnum = Direction.DirectionEnum;
const directions = DirectionEnum.directions;

const power = @import("power.zig");
pub const Power = power.Power;

pub const step_simulation = update;

pub const State = struct {
    grid: []Block,
    bounds: Pos,

    pub const Upos = u16;
    pub const Pos = [3]Upos;

    pub fn init(
        grid: []Block,
        bounds: Pos,
    ) State {
        const total = bounds[0] * bounds[1] * bounds[2];
        std.debug.assert(total <= grid.len);
        return .{
            .grid = grid,
            .bounds = bounds,
        };
    }

    pub fn get_pos(self: State, i: usize) Pos {
        const x: Upos = @intCast(i % self.bounds[2]);
        const y: Upos = @intCast((i / self.bounds[2]) % self.bounds[1]);
        const z: Upos = @intCast((i / self.bounds[2]) / self.bounds[1]);
        return .{ z, y, x };
    }

    pub fn get_index(self: State, pos: Pos) usize {
        std.debug.assert(pos[0] < self.bounds[0]);
        std.debug.assert(pos[1] < self.bounds[1]);
        std.debug.assert(pos[2] < self.bounds[2]);

        const zoff = pos[0] * self.bounds[1] * self.bounds[2];
        const yoff = pos[1] * self.bounds[2];
        const xoff = pos[2];
        const index = zoff + yoff + xoff;
        return index;
    }

    pub fn get_block(self: State, pos: Pos) Block {
        return self.grid[self.get_index(pos)];
    }

    pub fn get_power(self: State, pos: Pos) Power {
        return self.get_block(pos).power();
    }

    pub fn grid_len(self: State) usize {
        return self.bounds[0] * self.bounds[1] * self.bounds[2];
    }
};

test "State compiles!" {
    std.testing.refAllDeclsRecursive(State);
}

pub const MachineOut = enum { old_out, new_out };
pub const PutBlock = struct { pos: State.Pos, block: Block };
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
        for (state.grid, 0..) |b, i| {
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
                            State.Upos,
                            pos,
                            state.bounds,
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
                            State.Upos,
                            pos,
                            state.bounds,
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
                                State.Upos,
                                pos,
                                state.bounds,
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
        for (state.grid, 0..) |b, i| {
            const pos = state.get_pos(i);
            if (b != .repeater) continue;
            const rep = b.repeater;
            const back_dir = rep.facing.back();
            const curr_in: u1 =
                if (back_dir.inbounds_arr(State.Upos, pos, state.bounds)) |bpos|
            blk: {
                const that_power = look_at_power(
                    .new_out,
                    back_dir,
                    state.get_block(bpos),
                ) catch |err| switch (err) {
                    error.InvalidPower => {
                        std.debug.print(
                            "this: (z: {}, y: {}, x: {}) b: {} - that: (z: {}, y: {}, x: {}) b:{} p: {}\n",
                            .{ pos[0], pos[1], pos[2], b, bpos[0], bpos[1], bpos[2], state.get_block(bpos), state.get_power(bpos) },
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
            state.grid[i] = .{ .repeater = rep.shift(curr_in) };
        }
    }

    { // For each comparator, shift input
        for (state.grid, 0..) |b, i| {
            const pos = state.get_pos(i);
            if (b != .comparator) continue;
            const comp = b.comparator;
            const back_dir = comp.facing.back();
            const curr_in: u4 =
                if (back_dir.inbounds_arr(State.Upos, pos, state.bounds)) |bpos|
            blk: {
                const that_power = look_at_power(
                    .new_out,
                    back_dir,
                    state.get_block(bpos),
                ) catch |err| switch (err) {
                    error.InvalidPower => {
                        std.debug.print(
                            "this: (z: {}, y: {}, x: {}) b: {} - that: (z: {}, y: {}, x: {}) b:{} p: {}\n",
                            .{ pos[0], pos[1], pos[2], b, bpos[0], bpos[1], bpos[2], state.get_block(bpos), state.get_power(bpos) },
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
                    if (de.inbounds_arr(State.Upos, pos, state.bounds)) |bpos| {
                        const that_power = look_at_power(
                            .new_out,
                            de,
                            state.get_block(bpos),
                        ) catch |err| switch (err) {
                            error.InvalidPower => {
                                std.debug.print(
                                    "this: (z: {}, y: {}, x: {}) b: {} - that: (z: {}, y: {}, x: {}) b:{} p: {}\n",
                                    .{ pos[0], pos[1], pos[2], b, bpos[0], bpos[1], bpos[2], state.get_block(bpos), state.get_power(bpos) },
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
            state.grid[i] = .{ .comparator = comp.shift(curr_in, highest_side) };
        }
    }

    { // For each negator, shift input
        for (state.grid, 0..) |b, i| {
            const pos = state.get_pos(i);
            if (b != .negator) continue;
            const neg = b.negator;
            const back_dir = neg.facing.back();
            const curr_in: u1 =
                if (back_dir.inbounds_arr(State.Upos, pos, state.bounds)) |bpos|
            blk: {
                const that_power = look_at_power(
                    .new_out,
                    back_dir,
                    state.get_block(bpos),
                ) catch |err| switch (err) {
                    error.InvalidPower => {
                        std.debug.print(
                            "this: (z: {}, y: {}, x: {}) b: {} - that: (z: {}, y: {}, x: {}) b:{} p: {}\n",
                            .{ pos[0], pos[1], pos[2], b, bpos[0], bpos[1], bpos[2], state.get_block(bpos), state.get_power(bpos) },
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
            state.grid[i] = .{ .negator = neg.shift(curr_in) };
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
        state.grid[idx] = put.block;
        for (directions) |de| {
            if (de.inbounds_arr(State.Upos, pos, state.bounds)) |npos| {
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
        const b = state.get_block(pos);
        switch (b) {
            .empty => {},
            .source => {},
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
            .repeater => {},
            .comparator => {},
            .negator => {},
        }
    }
}

fn update_wire(
    comptime Stack: type,
    state: *State,
    mod_stack: *Stack,
    choose_output: MachineOut,
    pos: State.Pos,
    b: Block,
) Allocator.Error!void {
    std.debug.assert(b == .wire);
    var this_power = Power.empty;
    for (directions) |de| {
        std.debug.assert(0 <= @intFromEnum(this_power));
        if (de.inbounds_arr(State.Upos, pos, state.bounds)) |npos| {
            const that_block = state.get_block(npos);
            const that_power = look_at_power(
                choose_output,
                de,
                that_block,
            ) catch |err| switch (err) {
                error.InvalidPower => {
                    std.debug.print(
                        "this: (z: {}, y: {}, x: {}) b: {} - that: (z: {}, y: {}, x: {}) b:{} p: {}\n",
                        .{ pos[0], pos[1], pos[2], b, npos[0], npos[1], npos[2], that_block, that_block.power() },
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
    if (this_power != b.power()) {
        state.grid[state.get_index(pos)].wire.power = this_power;
        for (directions) |de| {
            if (de.inbounds_arr(State.Upos, pos, state.bounds)) |npos| {
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
    pos: State.Pos,
    b: Block,
) Allocator.Error!void {
    std.debug.assert(b == .block or b == .led);
    var this_power = power.BLOCK_OFF_POWER;
    for (directions) |de| {
        std.debug.assert(this_power == power.BLOCK_OFF_POWER or
            this_power == power.BLOCK_ON_POWER or
            this_power == power.SOURCE_POWER);
        if (de.inbounds_arr(State.Upos, pos, state.bounds)) |npos| {
            const that_block = state.get_block(npos);
            const that_power = look_at_power(
                choose_output,
                de,
                that_block,
            ) catch |err| switch (err) {
                error.InvalidPower => {
                    std.debug.print(
                        "this: (z: {}, y: {}, x: {}) b: {} - that: (z: {}, y: {}, x: {}) b:{} p: {}\n",
                        .{ pos[0], pos[1], pos[2], b, npos[0], npos[1], npos[2], that_block, that_block.power() },
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
    if (this_power != state.get_power(pos)) {
        switch (b) {
            .block => state.grid[state.get_index(pos)].block.power = this_power,
            .led => state.grid[state.get_index(pos)].led.power = this_power,
            else => {
                std.debug.print(
                    "this: (z: {}, y: {}, x: {}) b: {}\n",
                    .{ pos[0], pos[1], pos[2], b },
                );
                unreachable;
            },
        }
        for (directions) |de| {
            if (de.inbounds_arr(State.Upos, pos, state.bounds)) |npos| {
                try mod_stack.append(npos);
            }
        }
    }
}

fn look_at_power(
    choose_output: MachineOut,
    from_de: DirectionEnum,
    b: Block,
) power.InvalidPowerError!Power {
    const p = b.power();
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
    const len = state.bounds[0] * state.bounds[1] * state.bounds[2];
    const canvas: []DrawInfo = try alloc.alloc(DrawInfo, len);
    for (state.grid, 0..) |b, i| {
        canvas[i] = DrawInfo.init(b, b.power());
    }
    return canvas;
}

pub fn unrender_grid(
    data_slice: []const DrawInfo,
    grid: []Block,
) void {
    for (data_slice, 0..) |data, i| {
        grid[i] = data.to_block();
    }
}

// Note: it is packed to be able to run at comptime
pub const DrawInfo = packed struct {
    pub const PowerUint = power.PowerUint;
    pub const BlockType = block.BlockType;
    pub const DirectionEnum = Direction.DirectionEnum;
    pub const ValidFields = enum(u3) {
        none = 0x0,
        memory = 0x1,
        info = 0x2,
        dir = 0x4,
        all = 0x7,
        _,

        pub fn has(self: ValidFields, other: ValidFields) bool {
            return @intFromEnum(self) & @intFromEnum(other) ==
                @intFromEnum(other);
        }

        pub fn with(self: ValidFields, other: ValidFields) ValidFields {
            return @enumFromInt(@intFromEnum(self) | @intFromEnum(other));
        }

        pub fn without(self: ValidFields, other: ValidFields) ValidFields {
            return @enumFromInt(@intFromEnum(self) & ~@intFromEnum(other));
        }
    };

    power: DrawInfo.PowerUint,
    block_type: DrawInfo.BlockType,
    memory: u4,
    info: u2,
    dir: DrawInfo.DirectionEnum,
    valid_fields: ValidFields,

    pub fn init(b: Block, this_power: Power) DrawInfo {
        var valid_fields = ValidFields.all;
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
            .empty, .source, .wire, .block, .led => blk: {
                valid_fields = valid_fields.without(.memory);
                break :blk 0;
            },
            .repeater => |r| r.get_memory(),
            .comparator => |c| c.memory,
            .negator => |n| n.memory,
        };
        const info = switch (b) {
            .empty, .source, .wire, .block, .led, .comparator, .negator => blk: {
                valid_fields = valid_fields.without(.info);
                break :blk 0;
            },
            .repeater => |r| @intFromEnum(r.get_delay()),
        };

        const dir = if (b.facing()) |de| de else blk: {
            valid_fields = valid_fields.without(.dir);
            break :blk .Above;
        };
        return DrawInfo{
            .power = pwr,
            .block_type = @as(BlockType, b),
            .memory = memory,
            .info = info,
            .dir = dir,
            .valid_fields = valid_fields,
        };
    }

    pub fn to_block(data: DrawInfo) Block {
        return switch (data.block_type) {
            .empty => blk: {
                std.debug.assert(data.valid_fields == ValidFields.none);
                break :blk .{ .empty = .{} };
            },
            .source => blk: {
                std.debug.assert(data.valid_fields == ValidFields.none);
                break :blk .{ .source = .{} };
            },
            .wire => blk: {
                std.debug.assert(data.valid_fields == ValidFields.none);
                break :blk .{ .wire = .{ .power = @enumFromInt(data.power) } };
            },
            .block => blk: {
                std.debug.assert(data.valid_fields == ValidFields.none);
                break :blk .{ .block = .{ .power = @enumFromInt(data.power) } };
            },
            .led => blk: {
                std.debug.assert(data.valid_fields == ValidFields.none);
                break :blk .{ .led = .{ .power = @enumFromInt(data.power) } };
            },
            .repeater => blk: {
                std.debug.assert(@intFromEnum(data.valid_fields) ==
                    @intFromEnum(ValidFields.all));
                const rep = block.Repeater.init_all(
                    data.dir,
                    @enumFromInt(data.info),
                    @intCast(data.memory),
                    @intCast(data.power),
                );
                break :blk .{ .repeater = rep };
            },
            .comparator => blk: {
                std.debug.assert(@intFromEnum(data.valid_fields) ==
                    @intFromEnum(ValidFields.all.without(ValidFields.info)));
                break :blk .{ .comparator = .{
                    .facing = data.dir,
                    .memory = data.memory,
                    .last_out = @intCast(data.power),
                } };
            },
            .negator => blk: {
                std.debug.assert(@intFromEnum(data.valid_fields) ==
                    @intFromEnum(ValidFields.all.without(ValidFields.info)));
                break :blk .{ .negator = .{
                    .facing = data.dir,
                    .memory = @intCast(data.memory),
                    .last_out = @intCast(data.power),
                } };
            },
        };
    }
};
