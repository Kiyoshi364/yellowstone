const std = @import("std");
const isWindows = @import("builtin").os.tag == .windows;

const lib_deser = @import("lib_deser");

pub const block = @import("block.zig");
pub const sim = @import("simulation.zig");
pub const ctl = @import("controler.zig");

const argsParser = @import("argsParser.zig");

var global_term: ?Term = null;

fn serialize(
    comptime Writer: type,
    state: sim.State,
    writer: Writer,
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
    comptime Reader: type,
    out_state: *sim.State,
    header: lib_deser.Header,
    reader: Reader,
    alloc: std.mem.Allocator,
) !void {
    const deser = try lib_deser.deserialize(
        sim.DrawInfo,
        header,
        reader,
        alloc,
    );
    // TODO: alloc out_state buffers
    std.debug.assert(deser.bounds[0] == out_state.bounds[0]);
    std.debug.assert(deser.bounds[1] == out_state.bounds[1]);
    std.debug.assert(deser.bounds[2] == out_state.bounds[2]);

    return sim.unrender_grid(deser.data, out_state);
}

const hardcoded_width = @as(sim.State.Upos, 16);
const hardcoded_height = @as(sim.State.Upos, hardcoded_width / 2);
const hardcoded_depth = @as(sim.State.Upos, 2);
const hardcoded_size = hardcoded_depth * hardcoded_height * hardcoded_width;

fn initial_sim_state(grid: []sim.Block) sim.State {
    std.debug.assert(grid.len == hardcoded_size);

    const state = sim.State{
        .grid = grid,
        .bounds = .{
            hardcoded_depth,
            hardcoded_height,
            hardcoded_width,
        },
    };

    for (grid) |*b| b.* = .empty;

    state.grid[state.get_index(.{ 0, 0, 6 })] = .{ .wire = .{} };
    state.grid[state.get_index(.{ 0, 0, 7 })] = .{
        .repeater = block.Repeater.init(.Right, .one),
    };
    state.grid[state.get_index(.{ 0, 0, 8 })] = .{ .wire = .{} };
    state.grid[state.get_index(.{ 0, 5, 0 })] = .{ .wire = .{} };
    state.grid[state.get_index(.{ 0, 6, 0 })] = .{
        .repeater = block.Repeater.init(.Up, .two),
    };
    state.grid[state.get_index(.{ 0, 7, 0 })] = .{ .wire = .{} };

    for (0..state.bounds[2]) |ui| {
        const i = @as(u16, @intCast(ui));
        state.grid[state.get_index(.{ 1, 0, i })] = .{ .wire = .{} };
        state.grid[state.get_index(.{ 1, 2, i })] =
            if (i < 8)
            .{ .wire = .{} }
        else
            .empty;
    }
    state.grid[state.get_index(.{ 1, 0, 8 })] = .{
        .comparator = .{ .facing = .Right },
    };
    state.grid[state.get_index(.{ 1, 1, 7 })] = .{ .wire = .{} };
    state.grid[state.get_index(.{ 1, 1, 9 })] = .{
        .comparator = .{ .facing = .Down },
    };
    state.grid[state.get_index(.{ 1, 1, 11 })] = .{ .led = .{} };
    state.grid[state.get_index(.{ 1, 2, 9 })] = .{ .wire = .{} };
    state.grid[state.get_index(.{ 1, 2, 11 })] = .{
        .repeater = .{ .facing = .Up },
    };
    state.grid[state.get_index(.{ 1, 3, 0 })] = .{ .wire = .{} };
    state.grid[state.get_index(.{ 1, 3, 2 })] = .{ .wire = .{} };
    state.grid[state.get_index(.{ 1, 3, 3 })] = .{ .wire = .{} };
    state.grid[state.get_index(.{ 1, 3, 4 })] = .{ .wire = .{} };
    state.grid[state.get_index(.{ 1, 3, 7 })] = .{ .wire = .{} };
    state.grid[state.get_index(.{ 1, 3, 9 })] = .{ .wire = .{} };
    state.grid[state.get_index(.{ 1, 3, 10 })] = .{
        .repeater = block.Repeater.init(.Right, .two),
    };
    state.grid[state.get_index(.{ 1, 3, 11 })] = .{ .block = .{} };
    state.grid[state.get_index(.{ 1, 4, 4 })] = .{ .led = .{} };
    state.grid[state.get_index(.{ 1, 5, 0 })] = .{
        .negator = .{ .facing = .Above },
    };
    for (0..state.bounds[2]) |ui| {
        const i = @as(u16, @intCast(ui));
        state.grid[state.get_index(.{ 1, 6, i })] = .{ .led = .{} };
    }
    state.grid[state.get_index(.{ 1, 6, 0 })] = .{ .block = .{} };
    state.grid[state.get_index(.{ 1, 6, 1 })] = .{ .wire = .{} };
    state.grid[state.get_index(.{ 1, 6, 2 })] = .{
        .comparator = .{ .facing = .Right },
    };
    state.grid[state.get_index(.{ 1, 6, 3 })] = .{ .wire = .{} };
    for (0..state.bounds[2]) |ui| {
        const i = @as(u16, @intCast(ui));
        state.grid[state.get_index(.{ 1, 7, i })] = .{ .wire = .{} };
    }
    state.grid[state.get_index(.{ 1, 7, 2 })] = .{
        .comparator = .{ .facing = .Left },
    };
    return state;
}

fn check_serde(
    sim_state: sim.State,
    temp_sim_state: *sim.State,
    alloc: std.mem.Allocator,
) !void {
    const buffer = try alloc.alloc(u8, 2000);
    defer alloc.free(buffer);
    var buf_stream = std.io.fixedBufferStream(buffer);

    const sw = buf_stream.writer();

    try serialize(@TypeOf(sw), sim_state, sw, alloc);

    var buf_stream2 = std.io.fixedBufferStream(
        buf_stream.getWritten(),
    );
    const sr = buf_stream2.reader();

    const header = try lib_deser.read_header(sr);
    try deserialize(@TypeOf(sr), temp_sim_state, header, sr, alloc);

    return if (eq_sim_state(sim_state, temp_sim_state.*))
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
        std.debug.assert(argsIter.skip());

        break :blk argsParser.parseArgs(
            &argsIter,
            stderr_file,
        ) orelse {
            std.os.exit(1);
        };
    };

    return switch (cmd) {
        .run => run(
            &arena,
            stdin_file,
            stdout_file,
            stderr_file,
        ),
        .replay => command_not_implemented(cmd, stderr_file),
        .@"test" => command_not_implemented(cmd, stderr_file),
        .record => command_not_implemented(cmd, stderr_file),
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
    std.os.exit(1);
}

fn run(
    main_arena: *std.heap.ArenaAllocator,
    stdin_file: anytype,
    stdout_file: anytype,
    stderr_file: anytype,
) !void {
    const main_alloc = main_arena.allocator();

    var brin = std.io.bufferedReader(stdin_file);
    const stdin = brin.reader();

    var bwout = std.io.bufferedWriter(stdout_file);
    const stdout = bwout.writer();

    var bwerr = std.io.bufferedWriter(stderr_file);
    const stderr = bwerr.writer();
    _ = stderr;

    const step_controler = ctl.step_controler;

    var ctlstates = blk: {
        var ctlstates = @as([2]ctl.CtlState, undefined);

        for (0..ctlstates.len) |i| {
            const state =
                initial_sim_state(
                try main_alloc.alloc(sim.Block, hardcoded_size),
            );
            ctlstates[i] = .{
                .sim_state = state,
                .cursor = .{ 1, 0, 0 },
                .camera = .{ .pos = .{ 1, 0, 0 } },
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
        const ctlinput = try read_ctlinput(&stdin) orelse {
            break;
        };

        try step_controler(&ctlstates[0], ctlinput, alloc);
        try ctl.draw(ctlstates[0], alloc, stdout);
        try bwout.flush();

        try check_serde(ctlstates[0].sim_state, &ctlstates[1].sim_state, alloc);

        std.debug.assert(arena.reset(.{ .free_all = {} }));
    }

    {
        const filename = "dump_state.ys.txt";
        const file = try std.fs.cwd().createFile(filename, .{});
        defer file.close();

        const fw = file.writer();

        try serialize(@TypeOf(fw), ctlstates[0].sim_state, fw, alloc);
    }
}

fn read_ctlinput(reader: anytype) !?ctl.CtlInput {
    var buffer = @as([1]u8, undefined);
    var loop = true;
    return while (loop) {
        const size = try reader.read(&buffer);
        if (size == 0) continue;
        switch (buffer[0]) {
            ' ' => break .{ .step = .{} },
            '\r', '\n' => break .{ .putBlock = .{} },
            'w' => break .{ .moveCursor = .Up },
            's' => break .{ .moveCursor = .Down },
            'a' => break .{ .moveCursor = .Left },
            'd' => break .{ .moveCursor = .Right },
            'z' => break .{ .moveCursor = .Above },
            'x' => break .{ .moveCursor = .Below },
            'h' => break .{ .moveCamera = .Left },
            'j' => break .{ .moveCamera = .Down },
            'k' => break .{ .moveCamera = .Up },
            'l' => break .{ .moveCamera = .Right },
            'u' => break .{ .moveCamera = .Above },
            'i' => break .{ .moveCamera = .Below },
            'H' => break .{ .retractCamera = .Right },
            'J' => break .{ .expandCamera = .Down },
            'K' => break .{ .retractCamera = .Down },
            'L' => break .{ .expandCamera = .Right },
            'U' => break .{ .expandCamera = .Above },
            'I' => break .{ .retractCamera = .Above },
            'f' => break .{ .flipCamera = .x },
            'F' => break .{ .flipCamera = .y },
            'g' => break .{ .flipCamera = .z },
            'c' => break .{ .swapDimCamera = .z },
            'v' => break .{ .swapDimCamera = .y },
            'b' => break .{ .swapDimCamera = .x },
            'n' => break .{ .nextBlock = .{} },
            'p' => break .{ .prevBlock = .{} },
            '.' => break .{ .nextRotate = .{} },
            ',' => break .{ .prevRotate = .{} },
            'q' => break null,
            else => {},
        }
    } else unreachable;
}

extern "kernel32" fn SetConsoleMode(
    in_hConsoleHandle: std.os.windows.HANDLE,
    in_dwMode: std.os.windows.DWORD,
) callconv(std.os.windows.WINAPI) std.os.windows.BOOL;

const WindowsTerm = struct {
    stdinHandle: std.os.windows.HANDLE,
    old_inMode: std.os.windows.DWORD,
    stdoutHandle: std.os.windows.HANDLE,
    old_outMode: std.os.windows.DWORD,

    fn config_term() !WindowsTerm {
        // References:
        // https://learn.microsoft.com/en-us/windows/console/console-functions
        // https://learn.microsoft.com/en-us/windows/console/getconsolemode
        // https://learn.microsoft.com/en-us/windows/console/setconsolemode
        const win = std.os.windows;
        const wink32 = win.kernel32;

        const stdinHandle = wink32.GetStdHandle(win.STD_INPUT_HANDLE) orelse {
            std.debug.print("{}\n", .{wink32.GetLastError()});
            return error.GetStdInHandle;
        };

        if (stdinHandle == win.INVALID_HANDLE_VALUE) {
            std.debug.print("{}\n", .{wink32.GetLastError()});
            return error.InvalidStdInHandle;
        }

        const inMode = blk: {
            var inMode = @as(win.DWORD, 0);
            if (wink32.GetConsoleMode(stdinHandle, &inMode) == 0) {
                std.debug.print("{}\n", .{wink32.GetLastError()});
                return error.GetConsoleModeError;
            }
            break :blk inMode;
        };

        const new_inMode = blk: {
            const ENABLE_ECHO_INPUT = @as(win.DWORD, 0x0004);
            // const ENABLE_INSERT_MODE = @as(win.DWORD, 0x0020);
            const ENABLE_LINE_INPUT = @as(win.DWORD, 0x0002);
            // const ENABLE_MOUSE_INPUT = @as(win.DWORD, 0x0010);
            // const ENABLE_PROCESSED_INPUT = @as(win.DWORD, 0x0001);
            // const ENABLE_QUICK_EDIT_MODE = @as(win.DWORD, 0x0040);
            // const ENABLE_WINDOW_INPUT = @as(win.DWORD, 0x0008);
            const ENABLE_VIRTUAL_TERMINAL_INPUT = @as(win.DWORD, 0x0200);

            var new_inMode = inMode;
            new_inMode &= ~(ENABLE_ECHO_INPUT | ENABLE_LINE_INPUT);
            new_inMode |= ENABLE_VIRTUAL_TERMINAL_INPUT;
            break :blk new_inMode;
        };

        if (SetConsoleMode(stdinHandle, new_inMode) == 0) {
            std.debug.print("{}\n", .{wink32.GetLastError()});
            return error.SetConsoleModeError;
        }

        const stdoutHandle = wink32.GetStdHandle(win.STD_OUTPUT_HANDLE) orelse {
            std.debug.print("{}\n", .{wink32.GetLastError()});
            return error.GetStdInHandle;
        };
        if (stdoutHandle == win.INVALID_HANDLE_VALUE) {
            std.debug.print("{}\n", .{wink32.GetLastError()});
            return error.InvalidStdOutHandle;
        }
        const outMode = blk: {
            var outMode = @as(win.DWORD, 0);
            if (wink32.GetConsoleMode(stdoutHandle, &outMode) == 0) {
                std.debug.print("{}\n", .{wink32.GetLastError()});
                return error.GetConsoleModeError;
            }
            break :blk outMode;
        };

        const new_outMode = blk: {
            const ENABLE_PROCESSED_OUTPUT = @as(win.DWORD, 0x0001);
            // const ENABLE_WRAP_AT_EOL_OUTPUT = @as(win.DWORD, 0x0002);
            const ENABLE_VIRTUAL_TERMINAL_PROCESSING = @as(win.DWORD, 0x0004);
            // const DISABLE_NEWLINE_AUTO_RETURN = @as(win.DWORD, 0x0008);
            // const ENABLE_LVB_GRID_WORLDWIDE = @as(win.DWORD, 0x0010);

            var new_outMode = outMode;
            new_outMode |= (ENABLE_PROCESSED_OUTPUT | ENABLE_VIRTUAL_TERMINAL_PROCESSING);
            break :blk new_outMode;
        };

        if (SetConsoleMode(stdoutHandle, new_outMode) == 0) {
            std.debug.print("{}\n", .{wink32.GetLastError()});
            return error.SetConsoleModeError;
        }

        return .{
            .stdinHandle = stdinHandle,
            .old_inMode = inMode,
            .stdoutHandle = stdoutHandle,
            .old_outMode = outMode,
        };
    }

    fn unconfig_term(self: WindowsTerm) !void {
        const wink32 = std.os.windows.kernel32;

        if (SetConsoleMode(self.stdinHandle, self.old_inMode) == 0) {
            std.debug.print("{}\n", .{wink32.GetLastError()});
            return error.SetConsoleModeError;
        }

        if (SetConsoleMode(self.stdinHandle, self.old_inMode) == 0) {
            std.debug.print("{}\n", .{wink32.GetLastError()});
            return error.SetConsoleModeError;
        }
    }
};

const LinuxTerm = struct {
    old_term: std.os.termios,

    fn config_term() !LinuxTerm {
        const fd = 0;
        const old_term = try std.os.tcgetattr(fd);
        var new_term = old_term;
        new_term.lflag &= ~(std.os.linux.ICANON | std.os.linux.ECHO);
        try std.os.tcsetattr(fd, .NOW, new_term);
        return .{
            .old_term = old_term,
        };
    }

    fn unconfig_term(self: LinuxTerm) !void {
        const fd = 0;
        try std.os.tcsetattr(fd, .NOW, self.old_term);
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
    std.testing.refAllDeclsRecursive(block);
    std.testing.refAllDeclsRecursive(sim);
    std.testing.refAllDeclsRecursive(ctl);
}
