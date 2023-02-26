const std = @import("std");
const Allocator = std.mem.Allocator;

const Simulation = @import("simulation.zig");

pub const Model = usize;
pub const Input = enum {
    Inc,
    Dec,
};
pub const Render = Model;

pub const sim = Simulation.SandboxedNoAlloc(
    Model,
    Input,
    Render,
){
    .update = update,
    .render = render,
};

pub const init = @as(Model, 0);

pub fn update(model: Model, input: Input) Model {
    return switch (input) {
        .Inc => model +| 1,
        .Dec => model -| 1,
    };
}

pub fn render(model: Model) Render {
    return model;
}

test "sizeof simulation is 0" {
    try std.testing.expectEqual(
        @as(usize, 0),
        @sizeOf(@TypeOf(sim)),
    );
}

test "step .Inc" {
    const model = @as(Model, 0);
    const input = .Inc;
    const new_model = sim.step(model, input);
    try std.testing.expectEqual(@as(Model, 1), new_model);
}

test "step .Dec" {
    const model = @as(Model, 1);
    const input = .Dec;
    const new_model = sim.step(model, input);
    try std.testing.expectEqual(@as(Model, 0), new_model);
}

test "run" {
    const model = @as(Model, 0);
    const inputs = &[_]Input{
        .Inc, .Inc, .Inc, .Dec, .Inc, .Dec,
    };
    const new_model = sim.run(model, inputs);
    try std.testing.expectEqual(@as(Model, 2), new_model);
}

test "view" {
    const model = @as(Model, 0);
    const view = sim.view(model);
    // Note: in this simulation ( Model == Render )
    try std.testing.expectEqual(model, view);
}
