const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn Sandboxed(
    comptime Model: type,
    comptime Input: type,
    comptime Render: type,
    comptime UpdateError: type,
    comptime RenderError: type,
) type {
    return struct {
        update: fn (Model, Input, Allocator) UpdateError!Model,
        render: fn (Model, Allocator) RenderError!Render,

        const Self = @This();

        pub fn step(
            comptime self: Self,
            model: Model,
            input: Input,
            alloc: Allocator,
        ) UpdateError!Model {
            return self.update(model, input, alloc);
        }

        pub fn run(
            comptime self: Self,
            model: Model,
            inputs: []const Input,
            alloc: Allocator,
        ) UpdateError!Model {
            var curr_model = model;
            return for (inputs) |input| {
                curr_model = try self.step(curr_model, input, alloc);
            } else curr_model;
        }

        pub fn view(
            comptime self: Self,
            model: Model,
            alloc: Allocator,
        ) RenderError!Render {
            return self.render(model, alloc);
        }
    };
}
