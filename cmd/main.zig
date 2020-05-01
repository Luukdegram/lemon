const std = @import("std");
const lemon = @import("lemon");
const parser = @import("parser.zig");
const flags = @import("flag.zig");

pub fn main() !void {
    var allocator = std.heap.page_allocator;

    var init = flags.Flag{
        .arg = "init",
        .description = "Initializes a new Git repository",
        .help = "Init creates a new .git repository within the worktree.",
        .handle = fn (args: [][]const u8) void{
            //var path = if (args.len > 0) { return args[0] } or
            //var repo = lemon.Repository.init();
        },
    };

    if (parser.Parse(allocator)) |result| {
        std.debug.warn("Empty: {}\n", .{result.isEmpty()});
        for (result.args) |arg| {
            std.debug.warn("arg: {}\n", .{arg});
        }
        result.deinit();
    } else |err| {
        std.debug.warn("Error occured: {}\n", .{err});
    }
}
