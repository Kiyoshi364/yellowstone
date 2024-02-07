const std = @import("std");

pub const CommandEnum = enum {
    run,
    replay,
    // Testing
    @"test",
    record,
};

pub const Run = struct { filename: ?[]const u8 = null };

pub const Command = union(CommandEnum) {
    run: Run,
    replay: struct {},
    // Testing
    @"test": struct {},
    record: struct {},
};

pub fn parseArgs(
    argsIter: *std.process.ArgIterator,
    error_writer: anytype,
) ?Command {
    std.debug.assert(argsIter.skip());

    const opt_arg = argsIter.next();

    const cmd = if (opt_arg) |arg|
        inline for (@typeInfo(CommandEnum).Enum.fields) |tag| {
            if (std.mem.eql(u8, tag.name, arg)) {
                break @unionInit(
                    Command,
                    tag.name,
                    switch (@as(CommandEnum, @enumFromInt(tag.value))) {
                        .run => parseRun(argsIter),
                        else => .{},
                    },
                );
            }
        } else {
            error_writer.print(
                "error: invalid command: \"{s}\"\n",
                .{arg},
            ) catch {};
            return null;
        }
    else
        Command{ .run = .{} };

    while (argsIter.next()) |arg| {
        std.debug.print("Ignored argument ({d}): \"{s}\"\n", .{ argsIter.inner.index - 1, arg });
    }
    return cmd;
}

fn parseRun(
    argsIter: *std.process.ArgIterator,
) Run {
    const filename = argsIter.next() orelse null;
    return .{
        .filename = filename,
    };
}
