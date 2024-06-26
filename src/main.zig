const std = @import("std");
const process = std.process;
const antsy = @import("antsy.zig");

pub fn main() !void {
    antsy.initEditor();
    defer antsy.deinitEditor();

    while (true) {
        antsy.refreshScreen(true);
        antsy.processKeyPress();
    }

    process.exit(@intFromEnum(antsy.ExitCode.Success));
}
