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

pub const Run = struct {
    filename: ?[]const u8 = null,

    const small_description = "Run yellowstone";
    const big_description = bd_run;
};
pub const Help = struct {
    program: []const u8,
    command: ?[]const u8 = null,

    const small_description = "Display information on commands";
    const big_description = bd_help;
};

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

    fn ensure_is_implemented(comptime T: type, comptime tag: EnumField) void {
        comptime {
            if (!@hasDecl(T, "small_description")) {
                @compileError("Command " ++ tag.name ++
                    "'s implementation " ++ @typeName(T) ++
                    " does not have small_description");
            }
            if (!std.meta.trait.isZigString(@TypeOf(@field(T, "small_description")))) {
                @compileError("Command " ++ tag.name ++
                    "'s implementation " ++ @typeName(T) ++
                    ".small_description must be a zig string" ++
                    ", but has type " ++ @typeName(@TypeOf(@field(T, "small_description"))));
            }

            if (!@hasDecl(T, "big_description")) {
                @compileError("Command " ++ tag.name ++
                    "'s implementation " ++ @typeName(T) ++
                    " does not have big_description");
            }
            if (@TypeOf(@field(T, "big_description")) != fn ([]const u8, anytype) void) {
                @compileError("Command " ++ tag.name ++
                    "'s implementation " ++ @typeName(T) ++
                    ".big_description must be a fn ([]const u8, anytype) void" ++
                    ", but has type " ++ @typeName(@TypeOf(@field(T, "small_description"))));
            }
        }
    }

    const implementations_table = .{
        .run = Run,
        .replay = null,
        .@"test" = null,
        .record = null,
        .help = Help,
    };
    fn impl(comptime tag: EnumField) @TypeOf(@field(implementations_table, tag.name)) {
        return @field(implementations_table, tag.name);
    }

    fn is_implemented(comptime tag: EnumField) bool {
        return comptime blk: {
            const T = impl(tag);

            if (@TypeOf(T) != type) break :blk false;
            ensure_is_implemented(T, tag);
            break :blk true;
        };
    }

    fn small_description(comptime tag: EnumField) []const u8 {
        return comptime blk: {
            if (!is_implemented(tag)) {
                @compileError("command \"" ++ tag.name ++ "\" is not implemented");
            }
            break :blk impl(tag).small_description;
        };
    }

    // Note: this need inline
    // References:
    // https://github.com/ziglang/zig/issues/17445
    // https://github.com/ziglang/zig/issues/17636
    inline fn big_description(comptime tag: EnumField) fn (program: []const u8, error_writer: anytype) void {
        return comptime blk: {
            if (!is_implemented(tag)) {
                @compileError("command \"" ++ tag.name ++ "\" is not implemented");
            }
            break :blk impl(tag).big_description;
        };
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
                break commands_info.big_description(tag)(inputs.program, error_writer);
            }
        } else blk: {
            commands_info.print_invalid_command(command, error_writer);
            break :blk commands_info.implementations_table.help.big_description(inputs.program, error_writer);
        }
    else
        commands_info.implementations_table.help.big_description(inputs.program, error_writer);
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
                    commands_info.small_description(tag),
                },
            ) catch {};
        } else {
            // Empty
        }
    }
}
