const std = @import("std");

const Direction = @import("Direction.zig");
const DirectionEnum = Direction.DirectionEnum;

pub const Repeater = @import("repeater.zig").Repeater;
pub const Comparator = @import("comparator.zig").Comparator;
pub const Negator = @import("negator.zig").Negator;

pub const BlockType = enum(u4) {
    empty = 0,
    source,
    wire,
    block,
    led,
    repeater,
    comparator,
    negator,
};

pub const Block = union(BlockType) {
    empty: struct {},
    source: struct {},
    wire: struct {},
    block: struct {},
    led: struct {},
    repeater: Repeater,
    comparator: Comparator,
    negator: Negator,

    pub fn facing(self: Block) ?DirectionEnum {
        return switch (self) {
            .empty,
            .source,
            .wire,
            .block,
            .led,
            => null,
            .repeater => |r| r.facing,
            .comparator => |c| c.facing,
            .negator => |n| n.facing,
        };
    }

    pub fn with_facing(self: Block, de: DirectionEnum) Block {
        return switch (self) {
            .empty,
            .source,
            .wire,
            .block,
            .led,
            => self,
            .repeater => |r| .{ .repeater = r.with_facing(de) },
            .comparator => |c| .{ .comparator = c.with_facing(de) },
            .negator => |n| .{ .negator = n.with_facing(de) },
        };
    }

    pub fn nextRotate(self: Block) Block {
        return switch (self) {
            .empty, .source, .wire, .block, .led => self,
            .repeater => |r| .{
                .repeater = r.with_facing(r.facing.next()),
            },
            .comparator => |c| .{
                .comparator = c.with_facing(c.facing.next()),
            },
            .negator => |n| .{
                .negator = n.with_facing(n.facing.next()),
            },
        };
    }

    pub fn prevRotate(self: Block) Block {
        return switch (self) {
            .empty, .source, .wire, .block, .led => self,
            .repeater => |r| .{
                .repeater = r.with_facing(r.facing.prev()),
            },
            .comparator => |c| .{
                .comparator = c.with_facing(c.facing.prev()),
            },
            .negator => |n| .{
                .negator = n.with_facing(n.facing.prev()),
            },
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
            .led => fmt(writer, "L", .{}),
            .repeater => |r| fmt(writer, "r{c}{c}{c}", .{
                "1234"[@intFromEnum(r.get_delay())],
                "o^>v<x"[@intFromEnum(r.facing)],
                "0123456789abcdef"[r.get_memory()],
            }),
            .comparator => |c| fmt(writer, "c{c}{c}", .{
                "o^>v<x"[@intFromEnum(c.facing)],
                "0123456789abcdef"[c.memory],
            }),
            .negator => |n| fmt(writer, "n{c}{c}", .{
                "o^>v<x"[@intFromEnum(n.facing)],
                "01"[n.memory],
            }),
        };
    }
};
