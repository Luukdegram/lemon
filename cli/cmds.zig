const std = @import("std");
const Allocator = std.mem.Allocator;

usingnamespace @import("flag.zig");
usingnamespace @import("lemon");

pub const init = Flag{
    .arg = "init",
    .description = "Initializes a new Git repository",
    .help = "Init creates a new .git repository within the worktree.",
    .handle = handleInit,
};

pub const cat = Flag{
    .arg = "cat-file",
    .description = "Shows the content of an object",
    .help =
    \\Parses a hash to find its corresponding object, 
    \\it then shows the content of this file that corresponds to this object
    ,
    .handle = handleCat,
};

pub const hash = Flag{
    .arg = "hash-object",
    .description = "Creates object ID and optionally a blob",
    .help =
    \\Creates a unique object ID and stores it as an object file, 
    \\acceptable arguments: -t, -w, path
    \\-w        Will generate an object ID as well as write it to an object file
    ,
    .handle = handleHash,
};

fn handleInit(gpa: *Allocator, args: [][]const u8, writer: anytype) !void {
    var path = if (args.len > 1) if (std.mem.eql(u8, args[1], ".")) "" else args[1] else "";

    if (Repository.create(gpa, path)) |*repo| {
        defer repo.deinit();
        try writer.print("Initialized empty Git Repository in {}/.git\n", .{repo.working_path});
    } else |err| {
        const msg = switch (err) {
            error.PathAlreadyExists => "Git repository already exists",
            else => err,
        };
        try writer.print("Could not initialize Git repository: {}\n", .{msg});
    }
}

fn handleCat(gpa: *Allocator, args: [][]const u8, writer: anytype) !void {
    var name = if (args.len > 1) args[1] else return writer.print("Expected object hash: {}\n", .{cat.help});

    var repo = (try Repository.find(gpa)) orelse return writer.writeAll("Not a Git repository\n");
    defer repo.deinit();

    const obj = repo.findObject(name) catch |err| return if (err == error.MultipleResults)
        return writer.writeAll("Multiple objects were found, please specify further\n")
    else
        return err;

    if (obj) |o| {
        defer o.deinit(gpa);
        try o.serialize(writer);
    } else
        try writer.writeAll("No object file found\n");
}

fn handleHash(gpa: *Allocator, args: [][]const u8, writer: anytype) !void {}
