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
};
