const std = @import("std");

pub const CommandEnum = enum {
    run,
    replay,
    // Testing
    @"test",
    record,
};

pub const Command = union(CommandEnum) {
    run: struct {},
    replay: struct {},
    // Testing
    @"test": struct {},
    record: struct {},
};

pub fn parseArgs(
    argsIter: *std.process.ArgIterator,
    error_writer: anytype,
) ?Command {
    const opt_arg = argsIter.next();

    const cmd = if (opt_arg) |arg|
        inline for (@typeInfo(CommandEnum).Enum.fields) |tag| {
            if (std.mem.eql(u8, tag.name, arg)) {
                break @unionInit(
                    Command,
                    tag.name,
                    .{},
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
        .run;

    var i = @as(usize, 2);
    while (argsIter.next()) |arg| : (i += 1) {
        std.debug.print("Ignored argument ({d}): \"{s}\"\n", .{ i, arg });
    }
    return cmd;
}