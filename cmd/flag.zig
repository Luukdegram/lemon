const std = @import("std");
const log = std.log.default;

pub const Flag = struct {
    /// Arg is the command that will trigger this
    arg: []const u8,
    /// handle is the function that is triggered by `arg`.
    /// `args` contains a slice of all remaining arguments for further use within the handle.
    handle: fn (gpa: *std.mem.Allocator, args: [][]const u8, writer: anytype) anyerror!void,
    /// description is a small text to describe what the function does
    description: []const u8,
    /// help contains full information about its function.
    /// this will be shown when the user does Lemon help <cmd>
    help: []const u8,
};
