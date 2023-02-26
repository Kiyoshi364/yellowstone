const std = @import("std");

const lib_sim = @import("lib_sim");

pub fn main() !void {
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "lib_sim.counter" {
    const counter = lib_sim.examples.counter_example;
    const model = @as(counter.Model, 1);
    const input = .Dec;
    var fa = std.testing.FailingAllocator.init(
        std.testing.allocator,
        0,
    );
    const alloc = fa.allocator();
    const new_model = counter.sim.step(model, input, alloc);
    try std.testing.expectEqual(@as(counter.Model, 0), new_model);
}
