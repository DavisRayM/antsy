const std = @import("std");
const terminal = @import("terminal.zig");
const process = std.process;

pub const ExitCode = enum(u8) {
    Success,
    Failure,
};

pub fn initEditor() void {
    terminal.initializeEditorState() catch |err| {
        handlePanic("initializeEditor", err);
    };
}

pub fn deinitEditor() void {
    terminal.globalState.deinit();
}

pub fn processKeyPress() void {
    const key = terminal.readKey();

    switch (key) {
        terminal.ctrlKey('q') => {
            deinitEditor();
            refreshScreen(false);
            process.exit(@intFromEnum(ExitCode.Success));
        },
        'k', 'l', 'h', 'j' => {
            terminal.globalState.moveCursor(@enumFromInt(key));
        },
        else => {},
    }
}

pub fn handlePanic(comptime failurePoint: []const u8, err: anyerror) noreturn {
    defer process.exit(@intFromEnum(ExitCode.Failure));
    deinitEditor();
    refreshScreen(false);

    const stderr = std.io.getStdErr();
    var bw = std.io.bufferedWriter(stderr.writer());
    try std.fmt.format(bw.writer(), "{s}: {s}\r\n", .{ failurePoint, @errorName(err) });
    try bw.flush();
}

pub fn drawRows(writer: anytype) void {
    // unlike J (tells the terminal to clear the screen), K clears the current pointer lines
    // and takes an argument.
    // 0: clear the right side of the cursor(default)
    // 1: clear the left side of the cursor.
    // 2: clear the entire line
    const clearLineSequence = [_]u8{ 27, '[', 'K' };
    const welcomeMessage: []const u8 = "Antsy Editor";
    const terminalCols: u16 = terminal.globalState.winsize.ws_col;
    const terminalRows: u16 = terminal.globalState.winsize.ws_row;

    for (0..terminalRows) |i| {
        if (i == terminalRows / 3) {
            var len = welcomeMessage.len;
            if (len > terminalCols) {
                len = terminalCols;
            }

            var padding = (terminalCols - len) / 2;
            if (padding > 0) {
                writer.writeAll("~") catch |err| {
                    handlePanic("drawWelcomeMessage", err);
                };
                padding -= 1;
            }

            while (padding != 0) {
                writer.writeAll(" ") catch |err| {
                    handlePanic("drawWelcomeMessage", err);
                };
                padding -= 1;
            }

            writer.writeAll(welcomeMessage) catch |err| {
                handlePanic("drawWelcomeMessage", err);
            };
        } else {
            writer.writeAll("~") catch |err| {
                handlePanic("drawRows", err);
            };

            // Clear line to the right of the pointer
            writer.writeAll(&clearLineSequence) catch |err| {
                handlePanic("drawRows", err);
            };
        }

        if (i < terminalRows - 1) {
            writer.writeAll("\r\n") catch |err| {
                handlePanic("drawRows", err);
            };
        }
    }
}

/// Refreshes the terminal screen using an escape sequence.
/// Uses VT100 Escape sequence: https://en.wikipedia.org/wiki/VT100
/// READ MORE: https://vt100.net/docs/vt100-ug/chapter3.html
/// NOTE: For more compatability checkout implementing `ncurses` which
///       queries the current capabilities of the terminal and sends the
///       appropriate escape sequence.
pub fn refreshScreen(draw: bool) void {
    const cursorPositionSequence = [_]u8{ 27, '[', 'H' };
    const hidePointerSequence = [_]u8{ 27, '[', '?', '2', '5', 'l' };
    const showPointerSequence = [_]u8{ 27, '[', '?', '2', '5', 'h' };
    const stdout = std.io.getStdOut();

    var bw = std.io.bufferedWriter(stdout.writer());
    var writer = bw.writer();

    // Try to hide pointer
    writer.writeAll(&hidePointerSequence) catch |err| {
        handlePanic("pointer escape sequence", err);
    };

    // Position cursor at the top of the screen
    writer.writeAll(&cursorPositionSequence) catch |err| {
        handlePanic("cursor reposition", err);
    };

    if (draw) {
        drawRows(writer);
    }

    std.fmt.format(writer, "\x1b[{d};{d}H", .{ terminal.globalState.cursorPosY, terminal.globalState.cursorPosX }) catch |err| {
        handlePanic("cursor reposition", err);
    };

    writer.writeAll(&showPointerSequence) catch |err| {
        handlePanic("pointer escape sequence", err);
    };

    bw.flush() catch |err| {
        handlePanic("refresh screen", err);
    };
}
