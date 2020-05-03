const std = @import("std");
const lemon = @import("lemon");
const parser = @import("parser.zig");
const flags = @import("flag.zig");

var allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);

pub fn main() !void {
    defer allocator.deinit();

    var init = flags.Flag{
        .arg = "init",
        .description = "Initializes a new Git repository",
        .help = "Init creates a new .git repository within the worktree.",
        .handle = handleInit,
    };

    if (parser.Parse(&allocator.allocator)) |result| {
        defer result.deinit();
        var f = flags.init(result.args, &allocator.allocator);
        _ = try f.register(init);
        f.run();
    } else |err| {
        std.debug.warn("Error occured: {}\n", .{err});
    }
}

fn handleInit(args: [][]const u8, response: flags.Response) void {
    var path = if (args.len > 0) if (std.mem.eql(u8, args[0], ".")) "" else args[0] else "";

    if (lemon.Repository.init(&allocator.allocator, path)) |*repo| {
        defer repo.deinit();
        if (repo.create()) |_| {
            response.write("Initialized empty Git Repository in {}/.git\n", repo.working_path);
        } else |err| {
            response.write("Could not initialize Git repository.\n Error: {}\n", .{err});
        }
    } else |err| {
        response.write("Unexpected error occured: {}", err);
    }
}
