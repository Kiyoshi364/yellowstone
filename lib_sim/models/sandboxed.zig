const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn Sandboxed(
    comptime State: type,
    comptime Input: type,
    comptime Render: type,
) type {
    return struct {
        update: fn (State, Input, Allocator) Allocator.Error!State,
        render: fn (State, Allocator) Allocator.Error!Render,

        const Self = @This();

        pub fn step(
            comptime self: Self,
            state: State,
            input: Input,
            alloc: Allocator,
        ) Allocator.Error!State {
            return self.update(state, input, alloc);
        }

        pub fn run(
            comptime self: Self,
            state: State,
            inputs: []const Input,
            alloc: Allocator,
        ) Allocator.Error!State {
            var curr_state = state;
            return for (inputs) |input| {
                curr_state = try self.step(curr_state, input, alloc);
            } else curr_state;
        }

        pub fn view(
            comptime self: Self,
            state: State,
            alloc: Allocator,
        ) Allocator.Error!Render {
            return self.render(state, alloc);
        }
    };
}
