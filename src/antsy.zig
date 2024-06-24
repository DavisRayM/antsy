const std = @import("std");
const terminal = @import("terminal.zig");
const process = std.process;

pub const ExitCode = enum(u8) {
    Success,
    Failure,
};

pub fn processKeyPress() void {
    const key: u8 = terminal.readKey();

    switch (key) {
        ctrlKey('q') => {
            terminal.disableRawMode() catch |err| {
                handlePanic("disableRawMode", err);
            };
            refreshScreen();
            process.exit(@intFromEnum(ExitCode.Success));
        },
        else => {},
    }
}

pub fn enableRawMode() void {
    terminal.enableRawMode() catch |err| {
        handlePanic("enableRawMode", err);
    };
}

fn handlePanic(comptime failurePoint: []const u8, err: anyerror) noreturn {
    defer process.exit(@intFromEnum(ExitCode.Failure));
    terminal.disableRawMode() catch {};
    refreshScreen();

    const stderr = std.io.getStdErr();
    var bw = std.io.bufferedWriter(stderr.writer());
    try std.fmt.format(bw.writer(), "{s}: {s}\r\n", .{ failurePoint, @errorName(err) });
    try bw.flush();
}

fn ctrlKey(k: u8) u8 {
    // Same as using 0b00011111
    // Performs the same bitmasking done when a user presses the CTRL key
    return (k & 0x1f);
}

pub fn drawRows(writer: anytype) void {
    for (0..24) |_| {
        writer.writeAll("~\r\n") catch |err| {
            handlePanic("drawRows", err);
        };
    }
}

/// Refreshes the terminal screen using an escape sequence.
/// Uses VT100 Escape sequence: https://en.wikipedia.org/wiki/VT100
/// READ MORE: https://vt100.net/docs/vt100-ug/chapter3.html
/// NOTE: For more compatability checkout implementing `ncurses` which
///       queries the current capabilities of the terminal and sends the
///       appropriate escape sequence.
pub fn refreshScreen() void {
    const clearSequence: [4]u8 = .{ 27, '[', '2', 'J' };
    const cursorPositionSequence: [3]u8 = .{ 27, '[', 'H' };
    const stdout = std.io.getStdOut();

    var bw = std.io.bufferedWriter(stdout.writer());
    var writer = bw.writer();

    // Uses the escape sequence (27 = Escape or \x1b) 2J;
    // J tells the terminal to clear the screen and takes an argument
    // in this case we pass 2 which tells it to clear the entire screen.
    // 0: clear from the cursor up to the end of the screen
    // 1: clear the screen up to where the cursor is
    writer.writeAll(&clearSequence) catch |err| {
        handlePanic("refresh screen sequence", err);
    };

    // Position cursor at the top of the screen
    writer.writeAll(&cursorPositionSequence) catch |err| {
        handlePanic("cursor reposition", err);
    };

    drawRows(writer);

    writer.writeAll(&cursorPositionSequence) catch |err| {
        handlePanic("cursor reposition", err);
    };

    bw.flush() catch |err| {
        handlePanic("refresh screen", err);
    };
}
