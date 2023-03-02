const Direction = @import("Direction.zig");
const DirectionEnum = Direction.DirectionEnum;

pub const BlockType = enum(u4) {
    empty = 0,
    source,
    wire,
    block,
};

pub const Block = union(BlockType) {
    empty: struct {},
    source: struct {},
    wire: struct {},
    block: struct {},

    pub fn facing(self: Block) ?DirectionEnum {
        return switch (self) {
            .empty, .source, .wire, .block => null,
        };
    }
};
