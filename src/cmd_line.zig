const std = @import("std");

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
            // TODO: add utf8 support
            else => try state.unhandle(c, writer, config.prompt),
        }
    };
}
