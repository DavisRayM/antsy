const std = @import("std");
const antsy = @import("antsy.zig");
const mem = std.mem;
const process = std.process;
const posix = std.posix;
const ascii = std.ascii;

var originalTermios: posix.termios = undefined;

pub const ExitCode = enum(u8) {
    Success,
    Failure,
};

pub fn main() !void {
    enableRawMode();

    var buf: [1]u8 = undefined;
    const stdin = std.io.getStdIn();
    var br = std.io.bufferedReader(stdin.reader());
    var stdinReader = br.reader();

    while (true) {
        buf = undefined;

        _ = stdinReader.read(&buf) catch |err| {
            handlePanic("read input", err);
        };
        if (ascii.isControl(buf[0])) {
            std.debug.print("{d}\r\n", .{buf[0]});
        } else {
            std.debug.print("{d} ('{0c}')\r\n", .{buf[0]});
        }

        if (mem.eql(u8, &buf, "q")) {
            break;
        }
    }

    disableRawMode();
    process.exit(@intFromEnum(ExitCode.Success));
}

fn handlePanic(comptime failurePoint: []const u8, err: anyerror) noreturn {
    defer process.exit(@intFromEnum(ExitCode.Failure));
    const stderr = std.io.getStdErr();
    var bw = std.io.bufferedWriter(stderr.writer());
    try std.fmt.format(bw.writer(), "{s}: {s}\r\n", .{ failurePoint, @errorName(err) });
}

pub fn disableRawMode() void {
    posix.tcsetattr(posix.STDIN_FILENO, .FLUSH, originalTermios) catch |err| {
        handlePanic("tcsetattr", err);
    };
}

pub fn enableRawMode() void {
    // Get current terminal attributes
    // READ MORE: https://man7.org/linux/man-pages/man3/termios.3.html
    //            man termios
    originalTermios = posix.tcgetattr(posix.STDIN_FILENO) catch |err| {
        handlePanic("tcgetattr", err);
    };
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

    posix.tcsetattr(posix.STDIN_FILENO, .FLUSH, raw) catch |err| {
        handlePanic("tcsetattr", err);
    };
}
