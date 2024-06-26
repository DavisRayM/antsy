const std = @import("std");
const posix = std.posix;
const antsy = @import("antsy.zig");

pub var globalState: EditorState = undefined;

pub const EditorKey = enum(u8) {
    CURSOR_LEFT = 'h',
    CURSOR_RIGHT = 'l',
    CURSOR_UP = 'k',
    CURSOR_DOWN = 'j',
};

pub fn ctrlKey(k: u8) u8 {
    // Same as using 0b00011111
    // Performs the same bitmasking done when a user presses the CTRL key
    return (k & 0x1f);
}

pub fn initializeEditorState() !void {
    globalState = try EditorState.init();
}

pub fn readKey() u8 {
    const stdin = std.io.getStdIn();
    var br = std.io.bufferedReader(stdin.reader());
    var stdinReader = br.reader();

    const key = stdinReader.readByte() catch {
        return 0;
    };

    // Check if escape was pressed. NOTE: 27 = \x1b
    if (key == 27) {
        const k2 = stdinReader.readByte() catch {
            return 0;
        };

        if (k2 == '[') {
            const k3 = stdinReader.readByte() catch {
                return 0;
            };

            switch (k3) {
                'A' => return @intFromEnum(EditorKey.CURSOR_UP),
                'B' => return @intFromEnum(EditorKey.CURSOR_DOWN),
                'C' => return @intFromEnum(EditorKey.CURSOR_RIGHT),
                'D' => return @intFromEnum(EditorKey.CURSOR_LEFT),
                else => {
                    return key;
                },
            }
        }
    }

    return key;
}

fn disableRawMode(originalTermios: posix.termios) !void {
    try posix.tcsetattr(posix.STDIN_FILENO, .FLUSH, originalTermios);
}

fn enableRawMode(originalTermios: posix.termios) !void {
    // Get current terminal attributes
    // READ MORE: https://man7.org/linux/man-pages/man3/termios.3.html
    //            man termios
    var raw = originalTermios;

    // Disable 'ECHO'. User input will no longer be printed to stdin.
    raw.lflag.ECHO = false;
    // Disable canonical mode aka cooked mode. User input is now read after each
    // keypress; no need for them to press 'ENTER'
    raw.lflag.ICANON = false;
    // Disable signal mapping for INTR, QUIT, SUSP, or DSUSP. No more CTRL-C for
    // ya! use 'q'
    raw.lflag.ISIG = false;
    // Disable software control flow sequences. Disables CTRL-S (Stop transmit
    // of data to shell) & CTRL-Q (Resume transmit of data).
    // READ MORE: https://en.wikipedia.org/wiki/Software_flow_control
    raw.iflag.IXON = false;
    // Disable implementation defined input processing
    raw.lflag.IEXTEN = false;
    // Disable carriage return to newline translation. FUN FACT: CTRL-M is a
    // carriage return; Byte-wise atleast (13, '\r') also (10, '\n').
    raw.iflag.ICRNL = false;
    // Disable output processing features. Have to print '\r\n' from now on in
    // order to have the cursor move to the beginning.
    // NOTE: Whenever you press 'ENTER' the terminal sends a '\r\n'; `\r` to
    //       move to the beginning of the current line and '\n' to move to
    //       the next line.
    raw.oflag.OPOST = false;

    // Disable legacy flags.
    // BRKINT: Break conditions cause the terminal to send a SIGINT
    // INPCK: Enable parity checking
    // ISTRIP: Causes the 8th bit of each input byte sent to be turned stripped
    raw.iflag.BRKINT = false;
    raw.iflag.INPCK = false;
    raw.iflag.ISTRIP = false;

    // Set timeout for read

    // Minimum read of 0 characters
    raw.cc[@intFromEnum(posix.V.MIN)] = 0;
    // Timer for 1 tenth of a second
    raw.cc[@intFromEnum(posix.V.TIME)] = 1;

    try posix.tcsetattr(posix.STDIN_FILENO, .FLUSH, raw);
}

const EditorState = struct {
    originalTermios: posix.termios,
    winsize: posix.winsize,
    cursorPosX: u16 = 1,
    cursorPosY: u16 = 1,

    pub fn init() !EditorState {
        const originalTermios = try posix.tcgetattr(posix.STDIN_FILENO);
        errdefer disableRawMode(originalTermios) catch {};

        try enableRawMode(originalTermios);

        return .{
            .originalTermios = originalTermios,
            .winsize = try getWinSize(),
        };
    }

    pub fn deinit(self: *EditorState) void {
        disableRawMode(self.originalTermios) catch |err| {
            antsy.handlePanic("editorState deinit", err);
        };
        self.cursorPosX = 1;
        self.cursorPosY = 1;
        self.winsize = undefined;
        self.originalTermios = undefined;
    }

    pub fn moveCursor(self: *EditorState, key: EditorKey) void {
        switch (key) {
            EditorKey.CURSOR_UP => {
                if (self.cursorPosY > 1) {
                    self.cursorPosY -= 1;
                }
            },
            EditorKey.CURSOR_DOWN => {
                if (self.cursorPosY < self.winsize.ws_row) {
                    self.cursorPosY += 1;
                }
            },
            EditorKey.CURSOR_LEFT => {
                if (self.cursorPosX > 1) {
                    self.cursorPosX -= 1;
                }
            },
            EditorKey.CURSOR_RIGHT => {
                if (self.cursorPosX < self.winsize.ws_col) {
                    self.cursorPosX += 1;
                }
            },
        }
    }
};

fn getWinSize() !posix.winsize {
    var winsize: posix.winsize = undefined;

    if (posix.system.ioctl(posix.STDIN_FILENO, posix.T.IOCGWINSZ, @intFromPtr(&winsize)) < 0) {
        const stdin = std.io.getStdIn();
        var br = std.io.bufferedReader(stdin.reader());
        var bw = std.io.bufferedWriter(stdin.writer());
        var stdinWriter = bw.writer();
        var stdinReader = br.reader();

        const cursorForwardSequence: [6]u8 = .{ 27, '[', '9', '9', '9', 'C' };
        const cursorDownSequence: [6]u8 = .{ 27, '[', '9', '9', '9', 'B' };
        const cursorReportSequence: [4]u8 = .{ 27, '[', '6', 'n' };

        try stdinWriter.writeAll(&cursorForwardSequence);
        try stdinWriter.writeAll(&cursorDownSequence);

        try bw.flush();

        try stdinWriter.writeAll(&cursorReportSequence);
        try bw.flush();

        var cursorReport: [32]u8 = std.mem.zeroes([32]u8);
        _ = try stdinReader.read(&cursorReport);

        winsize = .{
            .ws_col = 0,
            .ws_row = 0,
            .ws_xpixel = 0,
            .ws_ypixel = 0,
        };

        for (2..cursorReport.len) |i| {
            if (cursorReport[i] == ';') {
                winsize.ws_row = try std.fmt.parseInt(u16, cursorReport[2..i], 10);
                const start = i + 1;

                for (start..cursorReport.len) |j| {
                    if (cursorReport[j] == 'R') {
                        winsize.ws_col = try std.fmt.parseInt(u16, cursorReport[start..j], 10);
                        break;
                    }
                }

                break;
            }
        }
    }

    return winsize;
}
