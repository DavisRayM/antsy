const std = @import("std");
const process = std.process;
const antsy = @import("antsy.zig");

pub fn main() !void {
    antsy.enableRawMode();
    defer antsy.disableRawMode();
    antsy.initializeEditor();

    while (true) {
        antsy.refreshScreen();
        antsy.processKeyPress();
    }

    process.exit(@intFromEnum(antsy.ExitCode.Success));
}
