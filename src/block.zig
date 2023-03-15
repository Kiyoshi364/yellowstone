const std = @import("std");

const Direction = @import("Direction.zig");
const DirectionEnum = Direction.DirectionEnum;

pub const Repeater = @import("repeater.zig").Repeater;

pub const BlockType = enum(u4) {
    empty = 0,
    source,
    wire,
    block,
    repeater,
};

pub const Block = union(BlockType) {
    empty: struct {},
    source: struct {},
    wire: struct {},
    block: struct {},
    repeater: Repeater,

    pub fn facing(self: Block) ?DirectionEnum {
        return switch (self) {
            .empty, .source, .wire, .block => null,
            .repeater => |r| r.facing,
        };
    }

    pub fn format(
        block: Block,
        _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        const fmt = std.fmt.format;
        return switch (block) {
            .empty => fmt(writer, " ", .{}),
            .source => fmt(writer, "S", .{}),
            .wire => fmt(writer, "w", .{}),
            .block => fmt(writer, "B", .{}),
            .repeater => |r| fmt(writer, "r{c}{c}{c}", .{
                "o^>v<x"[@enumToInt(r.facing)],
                "1234"[@enumToInt(r.get_delay())],
                "0123456789abcdef"[r.get_memory()],
            }),
        };
    }
};
