const std = @import("std");

const char_powers = @as(*const [17]u8, "0123456789abcdef*");
const char_dirs = @as(*const [6]u8, "o^>v<x");
const char_delays = @as(*const [4]u8, "1234");

pub const Separator = enum {
    start_z,
    middle_z,
    end_z,
    start_y,
    middle_y,
    end_y,
    start_x,
    middle_x,
    end_x,
};

fn str_sep(sep: Separator) []const u8 {
    return switch (sep) {
        .start_z => "",
        .middle_z => "\n",
        .end_z => "",
        .start_y => "",
        .middle_y => "\n",
        .end_y => "\n",
        .start_x => "",
        .middle_x => " ",
        .end_x => "",
    };
}

fn parse_hex(comptime Uint: type, buf: []const u8) !Uint {
    var acc = @as(Uint, 0);
    for (buf) |c| {
        if ('0' <= c and c <= '9') {
            acc = (acc * 16) + c - '0';
        } else if ('a' <= c and c <= 'f') {
            acc = (acc * 16) + c - 'a' + 10;
        } else {
            return error.NotAHexDigit;
        }
    }
    return acc;
}

fn read_exact(
    comptime str: []const u8,
    reader: anytype,
) !void {
    var read = @as(usize, undefined);
    var buffer = @as([str.len]u8, undefined);

    read = try reader.readAll(&buffer);
    if (read != str.len) {
        return error.InvalidStr;
    }
    for (str, buffer) |a, b| {
        if (a != b) {
            return error.InvalidStr;
        }
    }
}

const Ubounds = u16;

pub const Header = struct {
    bounds: [3]Ubounds,
};

pub fn read_header(
    reader: anytype,
) !Header {
    try read_exact("v1\n", reader);

    var read = @as(usize, undefined);

    var bz = @as([4]u8, undefined);
    read = try reader.readAll(&bz);
    if (read != 4) {
        return error.InputTruncated;
    }

    try read_exact(" ", reader);

    var by = @as([4]u8, undefined);
    read = try reader.readAll(&by);
    if (read != 4) {
        return error.InputTruncated;
    }

    try read_exact(" ", reader);

    var bx = @as([4]u8, undefined);
    read = try reader.readAll(&bx);
    if (read != 4) {
        return error.InputTruncated;
    }

    try read_exact("\n", reader);

    const bounds = .{
        try parse_hex(Ubounds, &bz),
        try parse_hex(Ubounds, &by),
        try parse_hex(Ubounds, &bx),
    };
    return Header{
        .bounds = bounds,
    };
}

pub fn print_header(
    bounds: [3]Ubounds,
    writer: anytype,
) !void {
    try writer.print(
        "v1\n{x:0>4} {x:0>4} {x:0>4}\n",
        .{ bounds[0], bounds[1], bounds[2] },
    );
}

fn read_sep(
    sep: Separator,
    reader: anytype,
) !void {
    return switch (sep) {
        .start_z => read_exact(str_sep(.start_z), reader),
        .middle_z => read_exact(str_sep(.middle_z), reader),
        .end_z => read_exact(str_sep(.end_z), reader),
        .start_y => read_exact(str_sep(.start_y), reader),
        .middle_y => read_exact(str_sep(.middle_y), reader),
        .end_y => read_exact(str_sep(.end_y), reader),
        .start_x => read_exact(str_sep(.start_x), reader),
        .middle_x => read_exact(str_sep(.middle_x), reader),
        .end_x => read_exact(str_sep(.end_x), reader),
    };
}

fn print_sep(
    sep: Separator,
    writer: anytype,
) !void {
    try writer.print("{s}", .{str_sep(sep)});
}

fn read_data(
    comptime Data: type,
    reader: anytype,
) !Data {
    var read = @as(usize, undefined);
    var buffer = @as([5]u8, undefined);

    read = try reader.readAll(&buffer);
    if (read != 5) {
        return error.InputTruncated;
    }

    var valid_fields = Data.ValidFields.all;

    const block_type = @as(
        Data.BlockType,
        switch (buffer[0]) {
            'e' => .empty,
            'S' => .source,
            'w' => .wire,
            'B' => .block,
            'L' => .led,
            'r' => .repeater,
            'c' => .comparator,
            'n' => .negator,
            else => return error.InvalidBlockType,
        },
    );

    const power = @as(
        Data.PowerUint,
        switch (buffer[1]) {
            '0' => 0,
            '1' => 1,
            '2' => 2,
            '3' => 3,
            '4' => 4,
            '5' => 5,
            '6' => 6,
            '7' => 7,
            '8' => 8,
            '9' => 9,
            'a' => 10,
            'b' => 11,
            'c' => 12,
            'd' => 13,
            'e' => 14,
            'f' => 15,
            '*' => 16,
            else => return error.InvalidPower,
        },
    );

    const dir = @as(
        Data.DirectionEnum,
        switch (buffer[2]) {
            'o' => .Above,
            '^' => .Up,
            '>' => .Right,
            'v' => .Down,
            '<' => .Left,
            'x' => .Below,
            '-' => blk: {
                valid_fields = valid_fields.without(Data.ValidFields.dir);
                break :blk .Above;
            },
            else => return error.InvalidDirection,
        },
    );

    const info = @as(
        u2,
        switch (buffer[4]) {
            '1' => 0,
            '2' => 1,
            '3' => 2,
            '4' => 3,
            '-' => blk: {
                valid_fields = valid_fields.without(Data.ValidFields.info);
                break :blk 0;
            },
            else => return error.InvalidInfo,
        },
    );

    const memory = @as(
        u4,
        switch (buffer[3]) {
            '0' => 0,
            '1' => 1,
            '2' => 2,
            '3' => 3,
            '4' => 4,
            '5' => 5,
            '6' => 6,
            '7' => 7,
            '8' => 8,
            '9' => 9,
            'a' => 10,
            'b' => 11,
            'c' => 12,
            'd' => 13,
            'e' => 14,
            'f' => 15,
            '-' => blk: {
                valid_fields = valid_fields.without(Data.ValidFields.memory);
                break :blk 0;
            },
            else => return error.InvalidMemory,
        },
    );

    return .{
        .power = power,
        .block_type = block_type,
        .memory = memory,
        .info = info,
        .dir = dir,
        .valid_fields = valid_fields,
    };
}

fn print_data(
    comptime Data: type,
    info: Data,
    writer: anytype,
) !void {
    const c_power = char_powers[info.power];
    const c_block = switch (info.block_type) {
        .empty => @as(u8, 'e'),
        .source => @as(u8, 'S'),
        .wire => @as(u8, 'w'),
        .block => @as(u8, 'B'),
        .led => @as(u8, 'L'),
        .repeater => @as(u8, 'r'),
        .comparator => @as(u8, 'c'),
        .negator => @as(u8, 'n'),
    };
    const c_mem = if (info.valid_fields.has(.memory))
        char_powers[info.memory]
    else
        @as(u8, '-');
    const c_dir = if (info.valid_fields.has(.dir))
        char_dirs[@intFromEnum(info.dir)]
    else
        @as(u8, '-');
    const c_info = if (info.valid_fields.has(.info))
        char_delays[info.info]
    else
        @as(u8, '-');
    try writer.print(
        "{c}{c}{c}{c}{c}",
        .{
            c_block,
            c_power,
            c_dir,
            c_mem,
            c_info,
        },
    );
}

pub fn serialize(
    comptime Data: type,
    writer: anytype,
    data: [*]const Data,
    bounds: [3]Ubounds,
) !void {
    var i = @as(usize, 0);
    try print_sep(.start_z, writer);
    while (i < bounds[0]) : (i += 1) {
        const i_inc = i * bounds[1] * bounds[2];
        var j = @as(usize, 0);
        try print_sep(.start_y, writer);
        while (j < bounds[1]) : (j += 1) {
            const j_inc = j * bounds[2];
            var k = @as(usize, 0);
            try print_sep(.start_x, writer);
            while (k < bounds[2]) : (k += 1) {
                const idx = i_inc + j_inc + k;
                const info = data[idx];
                try print_data(Data, info, writer);
                try print_sep(
                    if (k + 1 < bounds[2]) .middle_x else .end_x,
                    writer,
                );
            }
            try print_sep(
                if (j + 1 < bounds[1]) .middle_y else .end_y,
                writer,
            );
        }
        try print_sep(
            if (i + 1 < bounds[0]) .middle_z else .end_z,
            writer,
        );
    }
}

pub fn Deser(comptime Data: type) type {
    return struct {
        data: []Data,
    };
}

pub fn deserialize_alloced(
    comptime Data: type,
    header: Header,
    reader: anytype,
    data: []Data,
) !Deser(Data) {
    const bounds = header.bounds;

    var i = @as(usize, 0);
    try read_sep(.start_z, reader);
    while (i < bounds[0]) : (i += 1) {
        const i_inc = i * bounds[1] * bounds[2];
        var j = @as(usize, 0);
        try read_sep(.start_y, reader);
        while (j < bounds[1]) : (j += 1) {
            const j_inc = j * bounds[2];
            var k = @as(usize, 0);
            try read_sep(.start_x, reader);
            while (k < bounds[2]) : (k += 1) {
                const idx = i_inc + j_inc + k;
                data[idx] = try read_data(Data, reader);
                try read_sep(
                    if (k + 1 < bounds[2]) .middle_x else .end_x,
                    reader,
                );
            }
            try read_sep(
                if (j + 1 < bounds[1]) .middle_y else .end_y,
                reader,
            );
        }
        try read_sep(
            if (i + 1 < bounds[0]) .middle_z else .end_z,
            reader,
        );
    }

    return Deser(Data){
        .data = data,
    };
}

pub fn deserialize(
    comptime Data: type,
    header: Header,
    reader: anytype,
    alloc: std.mem.Allocator,
) !Deser(Data) {
    const bounds = header.bounds;

    const data = try alloc.alloc(
        Data,
        bounds[0] * bounds[1] * bounds[2],
    );
    return deserialize_alloced(Data, header, reader, data);
}
