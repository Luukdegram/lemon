const std = @import("std");

pub const Flag = struct {
    arg: []const u8,
    /// handle is the function that is triggered by `arg`.
    /// `args` contains a slice of all remaining arguments for further use within the handle.
    handle: fn (args: [][]const u8) void,
    /// description is a small text to describe what the function does
    description: []const u8,
    /// help contains full information about its function.
    /// this will be shown when the user does Lemon help <cmd>
    help: []const u8,
};

/// Flags parses the provided arguments and fires a handle
/// if it matches the flag.
pub const Flags = struct {
    const Self = @This();
    flags: std.ArrayList(Flag),
    args: [][]const u8,

    /// run will check for each `Flag` if it matches the argument
    pub fn run(self: Self) void {
        if (args.len == 0) {
            return;
        }

        // for each flag, check if it has a matching argument
        for (flags) |flag| {
            if (std.mem.equal([]const u8, flag.arg, self.args[0])) {
                flag.handle(args[1..]);
            }
        }
    }

    pub fn deinit(self: Self) void {
        self.flags.deinit();
    }
};

/// init creates a new `Flags` and initializes the mandatory fields
pub fn init(args: [][]const u8, allocator: *std.mem.Allocator) Flags {
    return .{
        .flags = ArrayList(Flag).init(allocator),
        .allocator = allocator,
        .args = args,
    };
}
