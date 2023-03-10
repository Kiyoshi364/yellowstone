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
};
