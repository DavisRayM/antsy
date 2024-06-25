const std = @import("std");
const posix = std.posix;

const EditorStateError = error{
    WinInfoRequestFailed,
};

const EditorState = struct {
    originalTermios: posix.termios,
    winsize: posix.winsize,

    fn init() !EditorState {
        const originalTermios = try posix.tcgetattr(posix.STDIN_FILENO);
        var winsize: posix.winsize = undefined;
        if (posix.system.ioctl(posix.STDIN_FILENO, posix.T.IOCGWINSZ, @intFromPtr(&winsize)) < 0) {
            return EditorStateError.WinInfoRequestFailed;
        }

        return .{
            .originalTermios = originalTermios,
            .winsize = winsize,
        };
    }
};

pub var globalState: EditorState = undefined;

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

    return key;
}

pub fn disableRawMode() !void {
    try posix.tcsetattr(posix.STDIN_FILENO, .FLUSH, globalState.originalTermios);
}

pub fn enableRawMode() !void {
    // Get current terminal attributes
    // READ MORE: https://man7.org/linux/man-pages/man3/termios.3.html
    //            man termios
    var raw = globalState.originalTermios;

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
