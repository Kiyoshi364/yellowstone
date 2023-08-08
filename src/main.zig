const std = @import("std");
const isWindows = @import("builtin").os.tag == .windows;

const lib_sim = @import("lib_sim");

pub const block = @import("block.zig");
pub const sim = @import("simulation.zig");
pub const ctl = @import("controler.zig");

var global_term: ?Term = null;

pub fn main() !void {
    var arena =
        std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const controler = ctl.controler;

    const state = blk: {
        var state = sim.emptyState;
        state.block_grid[0][5][0] = .{ .wire = .{} };
        state.block_grid[0][6][0] = .{
            .repeater = block.Repeater.init(.Up, .two),
        };
        state.power_grid[0][6][0] = .repeater;
        state.block_grid[0][7][0] = .{ .wire = .{} };

        state.block_grid[1][0] = .{.{ .wire = .{} }} ** sim.width;
        state.block_grid[1][2] = .{.{ .wire = .{} }} ** 8 ++
            .{.empty} ** (sim.width - 8);
        state.block_grid[1][1][7] = .{ .wire = .{} };
        state.block_grid[1][1][9] = .{
            .comparator = .{ .facing = .Down },
        };
        state.power_grid[1][1][9] = .comparator;
        state.block_grid[1][2][9] = .{ .wire = .{} };
        state.block_grid[1][3][2] = .{ .wire = .{} };
        state.block_grid[1][3][3] = .{ .wire = .{} };
        state.block_grid[1][3][4] = .{ .wire = .{} };
        state.block_grid[1][3][7] = .{ .wire = .{} };
        state.block_grid[1][3][9] = .{ .wire = .{} };
        state.block_grid[1][3][10] = .{
            .repeater = block.Repeater.init(.Right, .two),
        };
        state.power_grid[1][3][10] = .repeater;
        state.block_grid[1][3][11] = .{ .block = .{} };
        state.block_grid[1][4][4] = .{ .led = .{} };
        state.block_grid[1][5][0] = .{
            .negator = .{ .facing = .Above },
        };
        state.power_grid[1][5][0] = .negator;
        state.block_grid[1][6] = .{.{ .led = .{} }} ** sim.width;
        state.block_grid[1][6][0] = .{ .block = .{} };
        state.block_grid[1][6][1] = .{ .wire = .{} };
        state.block_grid[1][6][2] = .{
            .comparator = .{ .facing = .Right },
        };
        state.power_grid[1][6][2] = .comparator;
        state.block_grid[1][6][3] = .{ .wire = .{} };
        state.block_grid[1][7] = .{.{ .wire = .{} }} ** sim.width;
        state.block_grid[1][7][2] = .{
            .comparator = .{ .facing = .Left },
        };
        state.power_grid[1][7][2] = .comparator;
        break :blk state;
    };

    var ctlstate = ctl.CtlState{
        .sim_state = state,
        .cursor = .{0} ** 2,
    };

    const stdin_file = std.io.getStdIn().reader();
    var br = std.io.bufferedReader(stdin_file);
    const stdin = br.reader();

    const term = try config_term();
    defer term.unconfig_term() catch unreachable;
    global_term = term;
    defer global_term = null;

    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    try ctl.draw(ctlstate, alloc, stdout);
    try bw.flush();
    while (true) {
        const ctlinput = try read_ctlinput(&stdin) orelse {
            break;
        };

        ctlstate = try controler.step(ctlstate, ctlinput, alloc);
        try ctl.draw(ctlstate, alloc, stdout);
        try bw.flush();

        std.debug.assert(arena.reset(.{ .free_all = {} }));
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

const Term = if (isWindows) WindowsTerm else LinuxTerm;

extern "kernel32" fn SetConsoleMode(
    in_hConsoleHandle: std.os.windows.HANDLE,
    in_dwMode: std.os.windows.DWORD,
) callconv(std.os.windows.WINAPI) std.os.windows.BOOL;

const WindowsTerm = struct {
    stdinHandle: std.os.windows.HANDLE,
    old_inMode: std.os.windows.DWORD,
    stdoutHandle: std.os.windows.HANDLE,
    old_outMode: std.os.windows.DWORD,

    fn unconfig_term(self: Term) !void {
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

    fn unconfig_term(self: Term) !void {
        const fd = 0;
        try std.os.tcsetattr(fd, .NOW, self.old_term);
    }
};

fn config_term() !Term {
    if (isWindows) {
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
    } else {
        const fd = 0;
        const old_term = try std.os.tcgetattr(fd);
        var new_term = old_term;
        new_term.lflag &= ~(std.os.linux.ICANON | std.os.linux.ECHO);
        try std.os.tcsetattr(fd, .NOW, new_term);
        return .{
            .old_term = old_term,
        };
    }
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

test "lib_sim.counter" {
    const counter = lib_sim.examples.counter_example;
    const state = @as(counter.State, 1);
    const input = .Dec;
    const new_state = counter.sim.step(state, input);
    try std.testing.expectEqual(@as(counter.State, 0), new_state);
}
