const std = @import("std");

const Simulation = @import("simulation.zig");

pub const State = usize;
pub const Input = enum {
    Inc,
    Dec,
};

pub const sim = Simulation.SandboxedNoAlloc(State, Input){
    .update = update,
};

pub const init = @as(State, 0);

pub fn update(state: State, input: Input) State {
    return switch (input) {
        .Inc => state +| 1,
        .Dec => state -| 1,
    };
}

test "sizeof simulation is 0" {
    try std.testing.expectEqual(
        @as(usize, 0),
        @sizeOf(@TypeOf(sim)),
    );
}

test "step .Inc" {
    const state = @as(State, 0);
    const input = .Inc;
    const new_state = sim.step(state, input);
    try std.testing.expectEqual(@as(State, 1), new_state);
}

test "step .Dec" {
    const state = @as(State, 1);
    const input = .Dec;
    const new_state = sim.step(state, input);
    try std.testing.expectEqual(@as(State, 0), new_state);
}

test "run" {
    const state = @as(State, 0);
    const inputs = &[_]Input{
        .Inc, .Inc, .Inc, .Dec, .Inc, .Dec,
    };
    const new_state = sim.run(state, inputs);
    try std.testing.expectEqual(@as(State, 2), new_state);
}
