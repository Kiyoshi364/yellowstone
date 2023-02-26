const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn Sandboxed(
    comptime State: type,
    comptime Input: type,
    comptime Render: type,
    comptime UpdateError: type,
    comptime RenderError: type,
) type {
    return struct {
        update: fn (State, Input, Allocator) UpdateError!State,
        render: fn (State, Allocator) RenderError!Render,

        const Self = @This();

        pub fn step(
            comptime self: Self,
            state: State,
            input: Input,
            alloc: Allocator,
        ) UpdateError!State {
            return self.update(state, input, alloc);
        }

        pub fn run(
            comptime self: Self,
            state: State,
            inputs: []const Input,
            alloc: Allocator,
        ) UpdateError!State {
            var curr_state = state;
            return for (inputs) |input| {
                curr_state = try self.step(curr_state, input, alloc);
            } else curr_state;
        }

        pub fn view(
            comptime self: Self,
            state: State,
            alloc: Allocator,
        ) RenderError!Render {
            return self.render(state, alloc);
        }
    };
}
