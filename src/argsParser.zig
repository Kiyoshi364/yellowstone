const std = @import("std");

pub const CommandEnum = enum {
    run,
    replay,
    // Testing
    @"test",
    record,
    // Help
    help,
};

pub const Run = struct { filename: ?[]const u8 = null };
pub const Help = struct { program: []const u8 };

pub const Command = union(CommandEnum) {
    run: Run,
    replay: struct {},
    // Testing
    @"test": struct {},
    record: struct {},
    // Help
    help: Help,
};

const info_CommandEnum = @typeInfo(CommandEnum).Enum;

const commands_info = struct {
    const EnumField = std.builtin.Type.EnumField;
    const command_count = info_CommandEnum.fields.len;

    const is_implemented_table = .{
        .run = true,
        .replay = false,
        .@"test" = false,
        .record = false,
        .help = true,
    };
    fn is_implemented(comptime tag: EnumField) bool {
        return @field(is_implemented_table, tag.name);
    }

    const small_description_table = .{
        .run = "Run yellowstone",
        .help = "Display information on commands",
    };
    fn small_description(comptime tag: EnumField) []const u8 {
        if (comptime !is_implemented(tag)) {
            @compileError("command \"" ++ tag.name ++ "\" is not implemented");
        }
        return @field(small_description_table, tag.name);
    }
};

pub fn parseArgs(
    argsIter: *std.process.ArgIterator,
    error_writer: anytype,
) ?Command {
    const program = argsIter.next().?;

    const opt_arg = argsIter.next();

    const cmd = if (opt_arg) |arg|
        inline for (info_CommandEnum.fields) |tag| {
            if (std.mem.eql(u8, tag.name, arg)) {
                break @unionInit(
                    Command,
                    tag.name,
                    switch (@as(CommandEnum, @enumFromInt(tag.value))) {
                        .run => parseRun(argsIter),
                        .help => parseHelp(argsIter, program),
                        else => .{},
                    },
                );
            }
        } else {
            error_writer.print(
                "error: invalid command: \"{s}\"\n",
                .{arg},
            ) catch {};
            return Command{ .help = .{ .program = program } };
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
fn parseHelp(
    argsIter: *std.process.ArgIterator,
    program: []const u8,
) Help {
    _ = argsIter.next();
    return .{
        .program = program,
    };
}

pub fn help(inputs: Help, error_writer: anytype) void {
    error_writer.print(
        \\usage: {[program]s} <command> <command specific arguments>
        \\
        \\=== list of valid commands ===
        \\
    ,
        .{ .program = inputs.program },
    ) catch {};
    inline for (info_CommandEnum.fields) |tag| {
        if (comptime commands_info.is_implemented(tag)) {
            error_writer.print(
                "{s: <15} {s}\n",
                .{
                    tag.name,
                    comptime commands_info.small_description(tag),
                },
            ) catch {};
        } else {
            // Empty
        }
    }
}
