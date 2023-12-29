const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn SandboxedMut(
    comptime State: type,
    comptime Input: type,
) type {
    return struct {
        update: fn (*State, Input, Allocator) Allocator.Error!void,

        const Self = @This();

        pub fn step(
            comptime self: Self,
            state: *State,
            input: Input,
            alloc: Allocator,
        ) Allocator.Error!void {
            try self.update(state, input, alloc);
        }

        pub fn run(
            comptime self: Self,
            state: *State,
            inputs: []const Input,
            alloc: Allocator,
        ) Allocator.Error!void {
            for (inputs) |input| {
                try self.step(state, input, alloc);
            }
        }
    };
}
