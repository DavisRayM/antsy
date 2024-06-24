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
            process.exit(@intFromEnum(ExitCode.Success));
        },
        else => {},
    }
}

pub fn handlePanic(comptime failurePoint: []const u8, err: anyerror) noreturn {
    defer process.exit(@intFromEnum(ExitCode.Failure));
    const stderr = std.io.getStdErr();
    var bw = std.io.bufferedWriter(stderr.writer());
    try std.fmt.format(bw.writer(), "{s}: {s}\r\n", .{ failurePoint, @errorName(err) });
    try bw.flush();
}

pub fn enableRawMode() void {
    terminal.enableRawMode() catch |err| {
        handlePanic("enableRawMode", err);
    };
}

fn ctrlKey(k: u8) u8 {
    // Same as using 0b00011111
    // Performs the same bitmasking done when a user presses the CTRL key
    return (k & 0x1f);
}
