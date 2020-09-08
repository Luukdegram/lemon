const std = @import("std");
const lemon = @import("lemon");
const parser = @import("parser.zig");

usingnamespace @import("flag.zig");

const log = std.log.default;

pub fn main() !void {
    var gpa_alloc = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_alloc.deinit();
    var arena = std.heap.ArenaAllocator.init(&gpa_alloc.allocator);
    defer arena.deinit();
    const gpa = &arena.allocator;

    const init = Flag{
        .arg = "init",
        .description = "Initializes a new Git repository",
        .help = "Init creates a new .git repository within the worktree.",
        .handle = handleInit,
    };

    const cmds = .{.{ "init", init }};

    const result = parser.parse(gpa) catch |err| return log.err("Error occured parsing arguments: {}\n", .{err});
    defer result.deinit();

    inline for (cmds) |cmd| {
        if (std.mem.eql(u8, cmd[0], result.args[0])) {
            try cmd[1].handle(gpa, result.args, std.io.getStdOut().writer());
            return;
        }
    }

    log.err("Unknown command: {}\n", .{result.args[0]});
}

fn handleInit(gpa: *std.mem.Allocator, args: [][]const u8, writer: anytype) !void {
    var path = if (args.len > 1) if (std.mem.eql(u8, args[1], ".")) "" else args[1] else "";

    var repo = lemon.Repository.init(gpa, path);
    defer repo.deinit();

    if (repo.create()) {
        try writer.print("Initialized empty Git Repository in {}/.git\n", .{repo.working_path});
    } else |err| {
        const msg = switch (err) {
            error.PathAlreadyExists => "Git repository already exists",
            else => err,
        };
        try writer.print("Could not initialize Git repository: {}\n", .{msg});
    }
}
