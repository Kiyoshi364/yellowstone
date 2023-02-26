const std = @import("std");
const Allocator = std.mem.Allocator;

const lib_sim = @import("lib_sim");
const block = @import("block.zig");

pub const simulation = lib_sim.Sandboxed(
    Model,
    Input,
    Render,
    UpdateError,
    RenderError,
){
    .update = update,
    .render = render,
};

const width = 8;
const height = width / 2;
pub const Model = [height][width]block.Block;
pub const Input = void;
pub const Render = *const [height][width]DrawBlock;
pub const UpdateError = error{};
pub const RenderError = error{OutOfMemory};

pub const emptyModel = @as(Model, .{
    .{.{ .empty = .{} }} ** width,
} ** height);

pub fn update(model: Model, _: Input, _: Allocator) UpdateError!Model {
    return model;
}

pub fn render(model: Model, alloc: Allocator) RenderError!Render {
    const canvas: *[height][width]DrawBlock =
        try alloc.create([height][width]DrawBlock);
    for (model, 0..) |row, y| {
        for (row, 0..) |b, x| {
            canvas.*[y][x] = switch (b) {
                .empty => DrawBlock{
                    .up_row = @as([3]u8, "   ".*),
                    .mid_row = @as([3]u8, "   ".*),
                    .bot_row = @as([3]u8, "   ".*),
                },
                else => DrawBlock{
                    .up_row = @as([3]u8, "   ".*),
                    .mid_row = @as([3]u8, " . ".*),
                    .bot_row = @as([3]u8, "   ".*),
                },
            };
        }
    }
    return canvas;
}

pub const DrawBlock = struct {
    up_row: [3]u8,
    mid_row: [3]u8,
    bot_row: [3]u8,
};
