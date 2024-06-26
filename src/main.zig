const std = @import("std");
const isWindows = @import("builtin").os.tag == .windows;

const lib_deser = @import("lib_deser");

pub const sim = @import("simulation/simulation.zig");
pub const ctl = @import("controler.zig");

const argsParser = @import("argsParser.zig");

const cmd_line = @import("cmd_line.zig");

var global_term: ?Term = null;

fn serialize(
    state: sim.State,
    writer: anytype,
    alloc: std.mem.Allocator,
) !void {
    const data = try sim.render_grid(state, alloc);

    try lib_deser.print_header(state.bounds, writer);
    try lib_deser.serialize(
        sim.DrawInfo,
        writer,
        data.ptr,
        .{
            state.bounds[0],
            state.bounds[1],
            state.bounds[2],
        },
    );
}

fn deserialize(
    out_grid: []sim.block.Block,
    header: lib_deser.Header,
    reader: anytype,
    alloc: std.mem.Allocator,
) !sim.State {
    const grid_len = header.bounds[0] * header.bounds[1] * header.bounds[2];
    std.debug.assert(out_grid.len == grid_len);
    const deser = try lib_deser.deserialize(
        sim.DrawInfo,
        header,
        reader,
        alloc,
    );

    sim.unrender_grid(deser.data, out_grid);
    return sim.State{
        .grid = out_grid,
        .bounds = header.bounds,
    };
}

const default_state = struct {
    grid: [grid_len]sim.block.Block,
    bounds: sim.State.Pos,

    const grid_len = 2 * 8 * 16;
    const default = blk: {
        var grid = @as([grid_len]sim.block.Block, undefined);

        const initial_buffer = @embedFile("init_state.ys.txt");

        var buf_stream = std.io.fixedBufferStream(initial_buffer);
        const sr = buf_stream.reader();

        const header = lib_deser.read_header(sr) catch unreachable;

        var data = @as([grid_len]sim.DrawInfo, undefined);

        const CR_incr = 6 * (2 + (header.bounds[0] - 1) + (header.bounds[0] * header.bounds[1]));
        @setEvalBranchQuota(0x1F6B + CR_incr);
        const deser = lib_deser.deserialize_alloced(
            sim.DrawInfo,
            header,
            sr,
            &data,
        ) catch unreachable;

        sim.unrender_grid(deser.data, &grid);

        break :blk @This(){
            .grid = grid,
            .bounds = header.bounds,
        };
    };
}.default;

fn check_serde(
    sim_state: sim.State,
    temp_grid: []sim.block.Block,
    alloc: std.mem.Allocator,
) !void {
    const buffer_size = lib_deser.encoding_size(
        sim_state.grid_len(),
        sim_state.bounds[0],
    );

    const buffer = try alloc.alloc(u8, buffer_size);
    defer alloc.free(buffer);
    var buf_stream = std.io.fixedBufferStream(buffer);

    const sw = buf_stream.writer();

    try serialize(sim_state, sw, alloc);

    var buf_stream2 = std.io.fixedBufferStream(
        buf_stream.getWritten(),
    );
    const sr = buf_stream2.reader();

    const header = try lib_deser.read_header(sr);
    const temp_sim_state = try deserialize(temp_grid, header, sr, alloc);

    return if (eq_sim_state(sim_state, temp_sim_state))
        void{}
    else
        error.SerdeFailed;
}

fn eq_sim_state(st1: sim.State, st2: sim.State) bool {
    return for (st1.grid, st2.grid) |b1, b2| {
        if (!std.meta.eql(b1, b2)) break false;
    } else true;
}

pub fn main() !void {
    var arena =
        std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const stdin_file = std.io.getStdIn().reader();
    const stdout_file = std.io.getStdOut().writer();
    const stderr_file = std.io.getStdErr().writer();

    const cmd = blk: { // Parse Args
        var argsIter = try std.process.argsWithAllocator(alloc);
        defer argsIter.deinit();

        break :blk argsParser.parseArgs(
            &argsIter,
            stderr_file,
        ) orelse {
            std.posix.exit(1);
        };
    };

    return switch (cmd) {
        .run => |inputs| run(
            &arena,
            inputs,
            stdin_file,
            stdout_file,
            stderr_file,
        ),
        .replay => command_not_implemented(cmd, stderr_file),
        .@"test" => command_not_implemented(cmd, stderr_file),
        .record => command_not_implemented(cmd, stderr_file),
        .help => |inputs| argsParser.help(inputs, stderr_file),
    };
}

fn command_not_implemented(
    cmd: argsParser.Command,
    error_writer: anytype,
) noreturn {
    error_writer.print(
        "command not implemented: {s}\n",
        .{@tagName(@as(argsParser.CommandEnum, cmd))},
    ) catch {};
    std.posix.exit(1);
}

const RepeatCtlInput = struct { times: u8, ctl: ctl.CtlInput };

const RunInput = union(enum) {
    ctl: ctl.CtlInput,
    repeat: RepeatCtlInput,
    q,
    quit,
};

fn run(
    main_arena: *std.heap.ArenaAllocator,
    inputs: argsParser.Run,
    stdin_file: anytype,
    stdout_file: anytype,
    stderr_file: anytype,
) !void {
    const main_alloc = main_arena.allocator();

    var bwout = std.io.bufferedWriter(stdout_file);
    const stdout = bwout.writer();

    const step_controler = ctl.step_controler;

    var ctlstates = blk: {
        var ctlstates = @as([2]ctl.CtlState, undefined);

        if (inputs.filename) |input_filename| blk2: {
            try stderr_file.print("Initializing with file: \"{s}\"\n", .{input_filename});
            const file = try std.fs.cwd().openFile(input_filename, .{});
            defer file.close();

            const max_bytes = 32 * 1024;
            const file_buffer = file.readToEndAlloc(main_alloc, max_bytes) catch |err| switch (err) {
                error.FileTooBig => {
                    try stderr_file.print(
                        "File is too big (supported size {d} bytes); Using default state instead\n",
                        .{max_bytes},
                    );
                    break :blk2;
                },
                else => return err,
            };
            defer main_alloc.free(file_buffer);

            var buf_stream = std.io.fixedBufferStream(file_buffer);
            const sr = buf_stream.reader();

            const header = try lib_deser.read_header(sr);
            const after_header = try buf_stream.getPos();

            const grid_len = header.bounds[0] * header.bounds[1] * header.bounds[2];
            const grids = try main_alloc.alloc(sim.block.Block, ctlstates.len * grid_len);

            for (0..ctlstates.len) |i| {
                try buf_stream.seekTo(after_header);

                const state = try deserialize(grids[i * grid_len .. (i + 1) * grid_len], header, sr, main_alloc);
                ctlstates[i] = .{
                    .sim_state = state,
                };
            }

            break :blk ctlstates;
        }

        try stderr_file.print("Initializing with default state\n", .{});

        const grid_len = default_state.grid.len;
        const grids = try main_alloc.alloc(sim.block.Block, ctlstates.len * grid_len);

        for (0..ctlstates.len) |i| {
            const grid = grids[i * grid_len .. (i + 1) * grid_len];
            std.mem.copyForwards(sim.block.Block, grid, &default_state.grid);
            const state = .{
                .grid = grid,
                .bounds = default_state.bounds,
            };
            ctlstates[i] = .{
                .sim_state = state,
            };
        }
        break :blk ctlstates;
    };

    var arena = std.heap.ArenaAllocator.init(main_alloc);
    defer arena.deinit();
    const alloc = arena.allocator();

    const term = try config_term();
    defer term.unconfig_term() catch unreachable;
    global_term = term;
    defer global_term = null;

    try ctl.draw(ctlstates[0], alloc, stdout);
    try bwout.flush();

    while (true) {
        const input =
            try read_command(&stdin_file, &stdout_file) orelse {
            break;
        };

        switch (input) {
            .ctl => |ctlinput| {
                try step_controler(&ctlstates[0], ctlinput, alloc);
                try ctl.draw(ctlstates[0], alloc, stdout);
                try bwout.flush();
            },
            .repeat => |rep| {
                for (0..rep.times) |_| {
                    try step_controler(&ctlstates[0], rep.ctl, alloc);
                    try check_serde(ctlstates[0].sim_state, ctlstates[1].sim_state.grid, alloc);
                }
                try ctl.draw(ctlstates[0], alloc, stdout);
                try bwout.flush();
            },
            .q, .quit => break,
        }

        try check_serde(ctlstates[0].sim_state, ctlstates[1].sim_state.grid, alloc);

        std.debug.assert(arena.reset(.{ .free_all = {} }));
    }

    {
        const filename = "dump_state.ys.txt";
        const file = try std.fs.cwd().createFile(filename, .{});
        defer file.close();

        const fw = file.writer();

        try serialize(ctlstates[0].sim_state, fw, alloc);
    }
}

fn read_command(reader: anytype, writer: anytype) !?RunInput {
    var buffer = @as([1]u8, undefined);
    return while (true) {
        const size = try reader.read(&buffer);
        if (size == 0) {
            break null;
        }
        switch (buffer[0]) {
            ' ' => break .{ .ctl = .{ .step = .{} } },
            '\r', '\n' => break .{ .ctl = .{ .putBlock = .{} } },
            'w' => break .{ .ctl = .{ .moveCursor = .Up } },
            's' => break .{ .ctl = .{ .moveCursor = .Down } },
            'a' => break .{ .ctl = .{ .moveCursor = .Left } },
            'd' => break .{ .ctl = .{ .moveCursor = .Right } },
            'z' => break .{ .ctl = .{ .moveCursor = .Above } },
            'x' => break .{ .ctl = .{ .moveCursor = .Below } },
            'h' => break .{ .ctl = .{ .moveCamera = .Left } },
            'j' => break .{ .ctl = .{ .moveCamera = .Down } },
            'k' => break .{ .ctl = .{ .moveCamera = .Up } },
            'l' => break .{ .ctl = .{ .moveCamera = .Right } },
            'u' => break .{ .ctl = .{ .moveCamera = .Above } },
            'i' => break .{ .ctl = .{ .moveCamera = .Below } },
            'H' => break .{ .ctl = .{ .retractCamera = .Right } },
            'J' => break .{ .ctl = .{ .expandCamera = .Down } },
            'K' => break .{ .ctl = .{ .retractCamera = .Down } },
            'L' => break .{ .ctl = .{ .expandCamera = .Right } },
            'U' => break .{ .ctl = .{ .expandCamera = .Above } },
            'I' => break .{ .ctl = .{ .retractCamera = .Above } },
            'f' => break .{ .ctl = .{ .flipCamera = .x } },
            'F' => break .{ .ctl = .{ .flipCamera = .y } },
            'g' => break .{ .ctl = .{ .flipCamera = .z } },
            'c' => break .{ .ctl = .{ .swapDimCamera = .z } },
            'v' => break .{ .ctl = .{ .swapDimCamera = .y } },
            'b' => break .{ .ctl = .{ .swapDimCamera = .x } },
            'n' => break .{ .ctl = .{ .nextBlock = .{} } },
            'p' => break .{ .ctl = .{ .prevBlock = .{} } },
            '.' => break .{ .ctl = .{ .nextRotate = .{} } },
            ',' => break .{ .ctl = .{ .prevRotate = .{} } },
            ':' => if (try command_line(reader, writer)) |input|
                break input
            else {},
            'q' => break null,
            // 0x03: Ctrl-C (End of Text)
            // 0x04: Ctrl-D (End of Transmition)
            // 0x17: Ctrl-W (End of Transmition Block)
            // 0x19: Ctrl-Y (End of Medium)
            0x03, 0x04, 0x17, 0x19 => break null,
            else => {},
        }
    } else unreachable;
}

fn command_line(reader: anytype, writer: anytype) !?RunInput {
    var line_buffer = @as([64]u8, undefined);
    return if (try cmd_line.command_line(&line_buffer, reader, writer, .{})) |line| blk: {
        try writer.print("\n", .{});
        var line_2 = line;
        break :blk switch (try cmd_line.line_parse(
            RunInput,
            &line_2,
            writer,
        )) {
            .MissingArgument => |name| reportMissingArgument(
                name,
                writer,
            ),
            .Ok => |run_input| run_input,
            .NoMatch => switch (try cmd_line.line_parse(
                ctl.CtlInput,
                &line_2,
                writer,
            )) {
                .MissingArgument => |name| reportMissingArgument(
                    name,
                    writer,
                ),
                .Ok => |ctl_input| .{ .ctl = ctl_input },
                .NoMatch => blk2: {
                    try writer.print(
                        "Unrecognized or incomplete command :{s}§\n",
                        .{line},
                    );
                    break :blk2 null;
                },
            },
        };
    } else null;
}

fn reportMissingArgument(name: []const u8, writer: anytype) !?RunInput {
    try writer.print(
        "Command {s}: missing argument\n",
        .{name},
    );
    return null;
}

extern "kernel32" fn SetConsoleMode(
    in_hConsoleHandle: std.os.windows.HANDLE,
    in_dwMode: std.os.windows.DWORD,
) callconv(std.os.windows.WINAPI) std.os.windows.BOOL;

const WindowsTerm = struct {
    // References:
    // https://learn.microsoft.com/en-us/windows/console/console-functions
    // https://learn.microsoft.com/en-us/windows/console/getconsolemode
    // https://learn.microsoft.com/en-us/windows/console/setconsolemode

    stdin: ?TermState,
    stdout: ?TermState,

    const win = std.os.windows;
    const wink32 = win.kernel32;

    const TermState = struct {
        handle: std.os.windows.HANDLE,
        old_mode: std.os.windows.DWORD,

        fn init(handle_num: std.os.windows.DWORD) !?TermState {
            const handle = wink32.GetStdHandle(handle_num) orelse {
                std.debug.print("{}\n", .{wink32.GetLastError()});
                return error.GetStdInHandle;
            };

            if (handle == win.INVALID_HANDLE_VALUE) {
                std.debug.print("{}\n", .{wink32.GetLastError()});
                return error.InvalidStdInHandle;
            }

            var old_mode = @as(win.DWORD, 0);
            if (wink32.GetConsoleMode(handle, &old_mode) == 0) {
                const last_error = wink32.GetLastError();
                switch (last_error) {
                    .INVALID_HANDLE => return null,
                    else => {
                        std.debug.print("{}\n", .{last_error});
                        return error.GetConsoleModeError;
                    },
                }
            }

            return TermState{
                .handle = handle,
                .old_mode = old_mode,
            };
        }

        fn deinit(self: TermState) !void {
            if (SetConsoleMode(self.handle, self.old_mode) == 0) {
                std.debug.print("{}\n", .{wink32.GetLastError()});
                return error.SetConsoleModeError;
            }
        }
    };

    fn config_term() !WindowsTerm {
        const stdin = try TermState.init(win.STD_INPUT_HANDLE);
        if (stdin) |state| {
            const new_inMode = blk2: {
                const ENABLE_ECHO_INPUT = @as(win.DWORD, 0x0004);
                // const ENABLE_INSERT_MODE = @as(win.DWORD, 0x0020);
                const ENABLE_LINE_INPUT = @as(win.DWORD, 0x0002);
                // const ENABLE_MOUSE_INPUT = @as(win.DWORD, 0x0010);
                // const ENABLE_PROCESSED_INPUT = @as(win.DWORD, 0x0001);
                // const ENABLE_QUICK_EDIT_MODE = @as(win.DWORD, 0x0040);
                // const ENABLE_WINDOW_INPUT = @as(win.DWORD, 0x0008);
                const ENABLE_VIRTUAL_TERMINAL_INPUT = @as(win.DWORD, 0x0200);

                var new_inMode = state.old_mode;
                new_inMode &= ~(ENABLE_ECHO_INPUT | ENABLE_LINE_INPUT);
                new_inMode |= ENABLE_VIRTUAL_TERMINAL_INPUT;
                break :blk2 new_inMode;
            };

            if (SetConsoleMode(state.handle, new_inMode) == 0) {
                std.debug.print("{}\n", .{wink32.GetLastError()});
                return error.SetConsoleModeError;
            }
        } else {
            // Empty
        }
        errdefer if (stdin) |t| t.deinit() catch {};

        const stdout = try TermState.init(win.STD_OUTPUT_HANDLE);
        if (stdout) |state| {
            const new_outMode = blk: {
                const ENABLE_PROCESSED_OUTPUT = @as(win.DWORD, 0x0001);
                // const ENABLE_WRAP_AT_EOL_OUTPUT = @as(win.DWORD, 0x0002);
                const ENABLE_VIRTUAL_TERMINAL_PROCESSING = @as(win.DWORD, 0x0004);
                // const DISABLE_NEWLINE_AUTO_RETURN = @as(win.DWORD, 0x0008);
                // const ENABLE_LVB_GRID_WORLDWIDE = @as(win.DWORD, 0x0010);

                var new_outMode = state.old_mode;
                new_outMode |= (ENABLE_PROCESSED_OUTPUT | ENABLE_VIRTUAL_TERMINAL_PROCESSING);
                break :blk new_outMode;
            };

            if (SetConsoleMode(state.handle, new_outMode) == 0) {
                std.debug.print("{}\n", .{wink32.GetLastError()});
                return error.SetConsoleModeError;
            }
        } else {
            // Empty
        }

        return .{
            .stdin = stdin,
            .stdout = stdout,
        };
    }

    fn unconfig_term(self: WindowsTerm) !void {
        if (self.stdin) |state| try state.deinit();
        if (self.stdout) |state| try state.deinit();
    }
};

const LinuxTerm = struct {
    // Termios 3 part Piece of Knowledge (ignoring 3rd):
    // https://blog.nelhage.com/2009/12/a-brief-introduction-to-termios/
    // https://blog.nelhage.com/2009/12/a-brief-introduction-to-termios-termios3-and-stty/
    // Reference:
    // man 3 termios   # Look for c_lflag, (non-)canonical mode and raw mode
    old_term: ?std.posix.termios,

    fn config_term() !LinuxTerm {
        const fd = 0;
        const old_term = std.posix.tcgetattr(fd) catch |err| switch (err) {
            error.NotATerminal => return .{ .old_term = null },
            error.Unexpected => return err,
        };
        var new_term = old_term;
        new_term.lflag.ICANON = false;
        new_term.lflag.ECHO = false;
        try std.posix.tcsetattr(fd, .NOW, new_term);
        return .{
            .old_term = old_term,
        };
    }

    fn unconfig_term(self: LinuxTerm) !void {
        if (self.old_term) |old_term| {
            const fd = 0;
            try std.posix.tcsetattr(fd, .NOW, old_term);
        }
    }
};

const Term = if (isWindows) WindowsTerm else LinuxTerm;

fn config_term() !Term {
    return Term.config_term();
}

const ST = std.builtin.StackTrace;
pub fn panic(msg: []const u8, trace: ?*ST, ret_addr: ?usize) noreturn {
    @setCold(true);
    if (global_term) |term| {
        term.unconfig_term() catch
            std.debug.print(
            "Couldn't restore terminal. Try blindly typing 'reset^J' (^J means Ctrl+J)\n",
            .{},
        );
    }
    std.builtin.default_panic(msg, trace, ret_addr);
}

test "It compiles!" {
    std.testing.refAllDeclsRecursive(@This());
    std.testing.refAllDeclsRecursive(sim);
    std.testing.refAllDeclsRecursive(ctl);
}
