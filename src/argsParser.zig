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
pub const Help = struct { program: []const u8, command: ?[]const u8 = null };

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

    fn print_invalid_command(command: []const u8, error_writer: anytype) void {
        return error_writer.print(
            "error: invalid command: \"{s}\"\n",
            .{command},
        ) catch {};
    }

    fn is_equal(comptime tag: EnumField, arg: []const u8) bool {
        return (comptime is_implemented(tag)) and
            std.mem.eql(u8, tag.name, arg);
    }

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

    const big_description_table = .{
        .run = bd_run,
        .help = bd_help,
    };
    fn big_description(comptime tag: EnumField, program: []const u8, error_writer: anytype) void {
        if (comptime !is_implemented(tag)) {
            @compileError("command \"" ++ tag.name ++ "\" is not implemented");
        }
        return @field(big_description_table, tag.name)(program, error_writer);
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
            if (commands_info.is_equal(tag, arg)) {
                break @unionInit(
                    Command,
                    tag.name,
                    switch (@field(CommandEnum, tag.name)) {
                        .run => parseRun(argsIter),
                        .help => parseHelp(argsIter, program),
                        else => .{},
                    },
                );
            }
        } else {
            commands_info.print_invalid_command(arg, error_writer);
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
    const command = argsIter.next();
    return .{
        .program = program,
        .command = command,
    };
}

pub fn help(inputs: Help, error_writer: anytype) void {
    return if (inputs.command) |command|
        inline for (info_CommandEnum.fields) |tag| {
            if ((comptime commands_info.is_implemented(tag)) and
                commands_info.is_equal(tag, command))
            {
                break commands_info.big_description(tag, inputs.program, error_writer);
            }
        } else blk: {
            commands_info.print_invalid_command(command, error_writer);
            break :blk commands_info.big_description_table.help(inputs.program, error_writer);
        }
    else
        commands_info.big_description_table.help(inputs.program, error_writer);
}

fn bd_run(program: []const u8, error_writer: anytype) void {
    error_writer.print(
        \\usage: {[program]s} run [initial_state_file]
        \\
        \\Start a simulation.
        \\When exit, writes last state to dump_state.ys.txt
        \\
        \\arguments:
        \\
        \\state_filename      file to load initial state.
        \\                    If invalid or not provided default state is loaded.
        \\
    ,
        .{ .program = program },
    ) catch {};
    return;
}

fn bd_help(program: []const u8, error_writer: anytype) void {
    error_writer.print(
        \\usage: {[program]s} <command> <command specific arguments>
        \\
        \\To learn more about a specific <command> try:
        \\$ {[program]s} help <command>
        \\
        \\=== list of valid commands ===
        \\
    ,
        .{ .program = program },
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
