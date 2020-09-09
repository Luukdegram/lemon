const std = @import("std");

/// Parse will attempt to parse the arguments. Possibly returns
/// `error.NoExecutableName` incase no executable was provided.
/// Note that the executable is not part of the result itself.
pub fn parse(allocator: *std.mem.Allocator) !ParseResult {
    var args = std.process.args();

    // Attempt to get the executable and leave it out of the rest
    const exe = try (args.next(allocator) orelse {
        return error.NoExecutableName;
    });
    defer allocator.free(exe);

    // create an Arena allocator so we can free all memory at once
    var arena = std.heap.ArenaAllocator.init(allocator);

    // Create and fill our arguments list
    var argList = std.ArrayList([]const u8).init(&arena.allocator);
    while (args.next(&arena.allocator)) |argument| {
        const arg = try argument;
        try argList.append(arg);
    }

    return ParseResult{ .args = argList.toOwnedSlice(), .arena = arena.state, .gpa = allocator };
}

/// ParseResult is the resultset from Parser.
/// `args` contains a slice of arguments
pub const ParseResult = struct {
    const Self = @This();

    args: [][]const u8,
    arena: std.heap.ArenaAllocator.State,
    gpa: *std.mem.Allocator,

    pub fn len(self: Self) usize {
        return self.args.len;
    }

    pub fn isEmpty(self: Self) bool {
        return self.len() == 0;
    }

    pub fn deinit(self: Self) void {
        self.arena.promote(self.gpa).deinit();
    }
};
