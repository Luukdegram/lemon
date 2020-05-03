const std = @import("std");

pub const Flag = struct {
    arg: []const u8,
    /// handle is the function that is triggered by `arg`.
    /// `args` contains a slice of all remaining arguments for further use within the handle.
    handle: fn (args: [][]const u8, response: Response) void,
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
    resp: Response = Response{},

    flags: std.ArrayList(Flag),
    args: [][]const u8,

    /// run will check for each `Flag` if it matches the argument and then triggers its handler.
    pub fn run(self: Self) void {
        if (self.args.len == 0) {
            return;
        }

        // for each flag, check if it has a matching argument
        for (self.flags.items) |flag| {
            if (std.mem.eql(u8, flag.arg, self.args[0])) {
                flag.handle(self.args[1..], self.resp);
            }
        }
    }

    pub fn register(self: *Self, flag: Flag) !void {
        return self.flags.append(flag);
    }
};

pub const Response = struct {
    const Self = @This();

    fn write(self: Self, comptime fmt: []const u8, obj: var) void {
        const out = std.io.getStdOut().outStream();
        if (out.print(fmt, .{obj})) |_| {} else |err| {
            std.debug.warn("Could not write to std out: {}\n", .{err});
        }
    }
};

/// init creates a new `Flags` and initializes the mandatory fields
pub fn init(args: [][]const u8, allocator: *std.mem.Allocator) Flags {
    return .{
        .flags = std.ArrayList(Flag).init(allocator),
        .args = args,
    };
}
