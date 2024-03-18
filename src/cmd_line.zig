const std = @import("std");
const Type = std.builtin.Type;

pub const Config = struct {
    prompt: []const u8 = ":",
};

const LineState = struct {
    buffer: []u8,
    cursor: u8 = 0,
    size: u8 = 0,

    fn to_slice(self: LineState) []const u8 {
        return self.buffer[0..self.size];
    }

    fn can_backspace(self: LineState) bool {
        return self.cursor > 0;
    }

    fn move_backward(self: *LineState, writer: anytype) !void {
        if (self.cursor == 0) {
            // Nothing
        } else {
            self.*.cursor -= 1;
            try writer.print("\x08", .{});
        }
    }

    fn move_forward(self: *LineState, writer: anytype) !void {
        if (self.cursor >= self.size) {
            std.debug.assert(self.cursor == self.size);
        } else {
            try writer.print(
                "{c}",
                .{self.buffer[self.cursor]},
            );
            self.*.cursor += 1;
        }
    }

    fn del_WORD_backward(self: *LineState, writer: anytype) !void {
        const new_cursor = blk: {
            var new_cursor = self.cursor;
            while (true and
                0 < new_cursor and
                self.buffer[new_cursor - 1] == ' ' and
                true) : (new_cursor -= 1)
            {}
            break :blk while (true and
                0 < new_cursor and
                self.buffer[new_cursor - 1] != ' ' and
                true) : (new_cursor -= 1)
            {} else new_cursor;
        };
        if (new_cursor == self.cursor) {
            // Nothing
            std.debug.assert(new_cursor == 0);
        } else {
            const diff = self.cursor - new_cursor;
            const new_size = self.size - diff;
            { // edit buffer
                for (0..self.size - self.cursor) |i| {
                    self.*.buffer[new_cursor + i] =
                        self.buffer[self.cursor + i];
                }
            }
            { // reprint buffer
                if (self.cursor < new_size) {
                    try writer.print(
                        "{s}",
                        .{self.buffer[self.cursor..new_size]},
                    );
                    for (0..self.size - new_size) |_| {
                        try writer.print(" ", .{});
                    }
                    for (0..self.size - new_cursor) |_| {
                        try writer.print("\x08", .{});
                    }
                    try writer.print(
                        "{s}",
                        .{self.buffer[new_cursor..self.cursor]},
                    );
                    for (0..diff) |_| {
                        try writer.print("\x08", .{});
                    }
                } else {
                    for (0..self.size - self.cursor) |_| {
                        try writer.print(" ", .{});
                    }
                    for (0..self.size - self.cursor) |_| {
                        try writer.print("\x08", .{});
                    }
                    for (0..self.cursor - new_size) |_| {
                        try writer.print("\x08 \x08", .{});
                    }
                    for (0..new_size - new_cursor) |_| {
                        try writer.print("\x08", .{});
                    }
                    try writer.print(
                        "{s}",
                        .{self.buffer[new_cursor..new_size]},
                    );
                    for (0..new_size - new_cursor) |_| {
                        try writer.print("\x08", .{});
                    }
                }
            }
            self.*.size = new_size;
            self.*.cursor = new_cursor;
        }
    }

    fn write(self: *LineState, c: u8, writer: anytype) !void {
        std.debug.assert(self.cursor <= self.buffer.len);
        std.debug.assert(self.size <= self.buffer.len);
        { // shift buffer forward
            var j = @as(
                u8,
                if (self.size < self.buffer.len)
                    self.size
                else
                    @as(u8, @min(self.buffer.len - 1, 0xFF)),
            );
            while (self.cursor < j) : (j -= 1) {
                self.*.buffer[j] = self.buffer[j - 1];
            }
        }
        { // add character
            if (self.cursor < self.buffer.len) {
                self.*.buffer[self.cursor] = c;
                self.*.cursor += 1;
            } else {
                self.*.buffer[self.cursor - 1] = c;
                try writer.print("\x08", .{});
            }
            if (self.size < self.buffer.len) {
                self.*.size += 1;
            } else {
                // Nothing
            }
        }
        { // print char
            try writer.print(
                "{s}",
                .{self.buffer[self.cursor - 1 .. self.size]},
            );
            for (0..self.size - self.cursor) |_| {
                try writer.print("\x08", .{});
            }
        }
    }

    fn backspace(self: *LineState, writer: anytype) !void {
        std.debug.assert(0 < self.cursor);
        std.debug.assert(0 < self.size);
        std.debug.assert(self.cursor <= self.size);
        try writer.print(
            "\x08{s} ",
            .{self.buffer[self.cursor..self.size]},
        );
        for (0..self.size - self.cursor + 1) |_| {
            try writer.print("\x08", .{});
        }
        for (self.cursor..self.size) |i| {
            self.*.buffer[i - 1] = self.buffer[i];
        }
        self.*.cursor -= 1;
        self.*.size -= 1;
    }

    fn clear_after_cursor(self: *LineState, writer: anytype) !void {
        for (0..self.size - self.cursor) |_| {
            try writer.print(" ", .{});
        }
        for (0..self.size - self.cursor) |_| {
            try writer.print("\x08", .{});
        }
    }

    fn clear_before_and_cursor(self: *LineState, writer: anytype) !void {
        for (0..self.cursor) |_| {
            try writer.print("\x08 \x08", .{});
        }
    }

    fn clear(self: *LineState, writer: anytype) !void {
        try self.clear_after_cursor(writer);
        try self.clear_before_and_cursor(writer);
        self.*.cursor = 0;
        self.*.size = 0;
    }

    fn unhandle_clearline(
        self: *LineState,
        writer: anytype,
        comptime prompt_size: comptime_int,
    ) !void {
        for (0..self.size - self.cursor) |_| {
            try writer.print(" ", .{});
        }
        for (0..self.size - self.cursor) |_| {
            try writer.print("\x08", .{});
        }
        for (0..self.cursor) |_| {
            try writer.print("\x08 \x08", .{});
        }
        for (0..prompt_size) |_| {
            try writer.print("\x08 \x08", .{});
        }
    }

    fn unhandle_message(
        self: LineState,
        c: u8,
        writer: anytype,
    ) !void {
        _ = self;
        try writer.print(
            "WARNING: Unhandled character (ignored): 0x{X}\n",
            .{c},
        );
    }

    fn unhandle_unclearline(
        self: *LineState,
        writer: anytype,
        comptime prompt: []const u8,
    ) !void {
        try writer.print(
            "{s}{s}",
            .{ prompt, self.to_slice() },
        );
        for (0..self.size - self.cursor) |_| {
            try writer.print("\x08", .{});
        }
    }

    fn unhandle(
        self: *LineState,
        c: u8,
        writer: anytype,
        comptime prompt: []const u8,
    ) !void {
        try self.unhandle_clearline(writer, prompt.len);
        try self.unhandle_message(c, writer);
        try self.unhandle_unclearline(writer, prompt);
    }

    const ContinueStop = enum {
        stop,
        cont,
    };

    fn escape(
        self: *LineState,
        reader: anytype,
        writer: anytype,
        comptime prompt: []const u8,
    ) !ContinueStop {
        var once = true;
        return while (once) : (once = false) {
            var c = @as(u8, undefined);
            const size = try reader.read(@as(*[1]u8, &c));
            if (size == 0) {
                try self.unhandle('\x1B', writer, prompt);
                break .stop;
            }
            switch (c) {
                // 0x1B: Ctrl-[ (Escape)
                0x1B => {
                    try self.clear(writer);
                    for (0..prompt.len) |_| {
                        try writer.print("\x08 \x08", .{});
                    }
                    break .stop;
                },
                '[' => {
                    const size2 = try reader.read(@as(*[1]u8, &c));
                    if (size2 == 0) {
                        try self.unhandle_clearline(writer, prompt.len);
                        try self.unhandle_message('\x1B', writer);
                        try self.unhandle_message('[', writer);
                        try self.unhandle_unclearline(writer, prompt);
                        break .stop;
                    }
                    switch (c) {
                        'C' => try self.move_forward(writer),
                        'D' => try self.move_backward(writer),
                        else => {
                            try self.unhandle_clearline(writer, prompt.len);
                            try self.unhandle_message('\x1B', writer);
                            try self.unhandle_message('[', writer);
                            try self.unhandle_message(c, writer);
                            try self.unhandle_unclearline(writer, prompt);
                        },
                    }
                },
                // 0x7F: Ctrl-? (Delete)
                0x7F => try self.del_WORD_backward(writer),
                else => {
                    try self.unhandle_clearline(writer, prompt.len);
                    try self.unhandle_message('\x1B', writer);
                    try self.unhandle_message(c, writer);
                    try self.unhandle_unclearline(writer, prompt);
                },
            }
        } else .cont;
    }
};

pub fn command_line(
    line_buffer: []u8,
    reader: anytype,
    writer: anytype,
    comptime config: Config,
) !?[]const u8 {
    try writer.print("{s}", .{config.prompt});

    var state = LineState{ .buffer = line_buffer };
    return while (true) {
        var c = @as(u8, undefined);
        const size = try reader.read(@as(*[1]u8, &c));
        const stop = size == 0 or c == '\r' or c == '\n';
        if (stop) {
            break state.to_slice();
        }
        switch (c) {
            // 0x03: Ctrl-C (End of Text)
            0x03 => {
                try state.clear(writer);
                break null;
            },
            // 0x04: Ctrl-D (End of Transmission)
            0x04 => try state.move_backward(writer),
            // 0x06: Ctrl-F (ACK)
            0x06 => try state.move_forward(writer),
            ' '...'~' => {
                try state.write(c, writer);
            },
            // 0x08: Ctrl-H (Backspace)
            // 0x7F: Ctrl-? (Delete)
            0x08, 0x7F => {
                if (state.can_backspace()) {
                    try state.backspace(writer);
                } else if (0 < state.size) {
                    // Nothing
                } else {
                    for (0..config.prompt.len) |_| {
                        try writer.print("\x08 \x08", .{});
                    }
                    break null;
                }
            },
            // 0x0C: Ctrl-L (Form Feed/New Page)
            0x0C => try state.clear(writer),
            // 0x1B: Ctrl-[ (Escape)
            0x1B => switch (try state.escape(reader, writer, config.prompt)) {
                .stop => break null,
                .cont => {},
            },
            // TODO: add utf8 support
            else => try state.unhandle(c, writer, config.prompt),
        }
    };
}

pub fn LineParse(comptime T: type) type {
    return union(enum) {
        NoMatch,
        MissingArgument: []const u8,
        Ok: T,
    };
}

pub fn line_parse(
    comptime T: type,
    line: *[]const u8,
    writer: anytype,
) !LineParse(T) {
    const line_backup = line.*;
    eat_space(line);
    const ret = try switch (@typeInfo(T)) {
        .Enum => |info| line_parse_enum(T, info, line),
        .Union => |info| blk: {
            inline for (info.fields) |f| {
                switch (@typeInfo(f.type)) {
                    .Void,
                    .Enum,
                    .Union,
                    .Struct,
                    .Int,
                    => {
                        // Implemented!
                    },
                    .Bool => {
                        // To be implemented in the future!
                        @compileError("field " ++ f.name ++
                            " with type " ++ @typeName(f.type) ++
                            " inside type " ++ @typeName(T) ++
                            " is not supported (maybe in the future)");
                    },
                    else => {
                        @compileError("field " ++ f.name ++
                            " with type " ++ @typeName(f.type) ++
                            " inside type " ++ @typeName(T) ++
                            " is not supported");
                    },
                }
            }
            break :blk line_parse_union(T, info, line);
        },
        else => @compileError("expected " ++ @typeName(T) ++ " to be a Union"),
    };
    switch (ret) {
        .NoMatch => line.* = line_backup,
        .MissingArgument => {},
        .Ok => try warn_ignoring_prompt(line, writer),
    }
    return ret;
}

fn line_parse_enum(
    comptime T: type,
    comptime info: Type.Enum,
    line: *[]const u8,
) !LineParse(T) {
    return inline for (info.fields) |f| {
        if (prefix(line.*, f.name)) |i| {
            line.* = line.*[i..];
            break .{ .Ok = @enumFromInt(f.value) };
        } else {
            // Nothing
        }
    } else .NoMatch;
}

fn line_parse_union(
    comptime T: type,
    comptime info: Type.Union,
    line: *[]const u8,
) !LineParse(T) {
    return inline for (info.fields) |f| {
        if (prefix(line.*, f.name)) |i| {
            line.* = line.*[i..];
            eat_space(line);
            break switch (try arg_parse(f.type, line)) {
                .NoMatch => .{ .MissingArgument = f.name },
                .MissingArgument => |name| .{
                    .MissingArgument = name,
                },
                .Ok => |arg| .{
                    .Ok = @unionInit(T, f.name, arg),
                },
            };
        } else {
            // Nothing
        }
    } else .NoMatch;
}

fn line_parse_struct(
    comptime T: type,
    comptime info: Type.Struct,
    line: *[]const u8,
) !LineParse(T) {
    var struct_ = @as(T, undefined);
    return inline for (info.fields) |f| {
        switch (try arg_parse(f.type, line)) {
            .Ok => |arg| @field(struct_, f.name) = arg,
            .MissingArgument => |name| break .{
                .MissingArgument = name,
            },
            .NoMatch => break .{
                .MissingArgument = f.name,
            },
        }
        eat_space(line);
    } else .{ .Ok = struct_ };
}

fn line_parse_int(
    comptime T: type,
    comptime info: Type.Int,
    line: *[]const u8,
) !LineParse(T) {
    comptime std.debug.assert(info.signedness == .unsigned);
    var i = @as(usize, 0);
    while (i < line.len and
        '0' <= line.*[i] and
        line.*[i] <= '9') : (i += 1)
    {}
    if (line.len == i or line.*[i] == ' ') {
        const num = parseInt(T, 10, line.*[0..i]);
        line.* = line.*[i..];
        eat_space(line);
        return if (i <= 0)
            .NoMatch
        else if (i == line.len)
            .{ .Ok = num }
        else blk: {
            if (line.*[0] == ' ') {
                line.* = line.*[1..];
            }
            break :blk .{ .Ok = num };
        };
    } else {
        return .NoMatch;
    }
}

fn warn_ignoring_prompt(line: *[]const u8, writer: anytype) !void {
    eat_space(line);
    if (line.len > 0) {
        try writer.print(
            "WARNING: ignoring end of prompt: \"{s}\"\n",
            .{line.*},
        );
    }
}

fn arg_parse(
    comptime T: type,
    line: *[]const u8,
) !LineParse(T) {
    return switch (@typeInfo(T)) {
        .Void => .{ .Ok = {} },
        .Struct => |info| line_parse_struct(T, info, line),
        .Enum => |info| line_parse_enum(T, info, line),
        .Union => |info| line_parse_union(T, info, line),
        .Int => |info| line_parse_int(T, info, line),
        .Bool => @compileError("unreachable"),
        else => @compileError("unreachable"),
    };
}

fn eat_space(line: *[]const u8) void {
    while (0 < line.len and line.*[0] == ' ') : (line.* = line.*[1..]) {}
}

fn prefix(big: []const u8, small: []const u8) ?usize {
    return if (big.len < small.len)
        null
    else for (big[0..small.len], small) |a, b| {
        if (a != b) {
            break null;
        }
    } else if (big.len == small.len)
        small.len
    else if (big[small.len] == ' ')
        small.len + 1
    else
        null;
}

fn parseInt(
    comptime Int: type,
    comptime base: comptime_int,
    str: []const u8,
) Int {
    comptime std.debug.assert(0 < base);
    var num = @as(Int, 0);
    for (str) |d| {
        std.debug.assert('0' <= d and d <= '9');
        const val = @as(Int, switch (d) {
            '0'...'9' => d - '0',
            else => unreachable,
        });
        num = num * base + val;
    }
    return num;
}
