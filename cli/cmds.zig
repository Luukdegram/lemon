const std = @import("std");
const Allocator = std.mem.Allocator;

usingnamespace @import("flag.zig");
usingnamespace @import("lemon");
const lemon = @import("lemon");

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
    \\Updates files in the working tree to match the version in the index or the specified tree.
    ,
    .handle = handleHash,
};

pub const check_out = Flag{
    .arg = "checkout",
    .description = "Switch branches or restore working tree files",
    .help =
    \\By default shows a list of files which are modified.
    \\Using -b a branch can be checked out.
    ,
    .handle = handleCheckout,
};

pub const log = Flag{
    .arg = "log",
    .description = "Prints the log of the given branch",
    .help =
    \\Prints a list of the object + message of each commit,
    \\belonging to the given branch as argument
    ,
    .handle = handleLog,
};

pub const tags = Flag{
    .arg = "tags",
    .description = "tags [name]",
    .help =
    \\Prints all tags or creates a new one if name is given.
    ,
    .handle = handleTag,
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

    const obj = repo.findObject(gpa, name) catch |err| return if (err == error.MultipleResults)
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

/// Checks out a branch if specified. If not, list all branches
fn handleCheckout(gpa: *Allocator, args: [][]const u8, writer: anytype) !void {
    const commit: ?[]const u8 = for (args) |arg, i| {
        if (i != 0 and std.mem.startsWith(u8, arg, "-commit=")) break arg else continue;
    } else null;

    if (commit == null) return writer.writeAll("Please specify a commit or tree\n");

    const path: ?[]const u8 = for (args) |arg| {
        if (std.mem.startsWith(u8, arg, "-path=")) break arg else continue;
    } else null;

    if (path == null) return writer.writeAll("Please specify a path to checkout to\n");

    var repo = (try Repository.find(gpa)) orelse return writer.writeAll("Not a Git repository\n");
    defer repo.deinit();

    const obj = repo.findObject(gpa, commit.?[8..]) catch |err| return if (err == error.MultipleResults)
        return writer.writeAll("Multiple objects were found, please specify further\n")
    else
        return err;

    if (obj == null) return writer.writeAll("No object file found\n");
    defer obj.?.deinit(gpa);

    const tree = switch (obj.?.kind) {
        .commit => blk: {
            const commit_obj = obj.?.cast(.commit).?;
            break :blk try commit_obj.getTree(repo, gpa);
        },
        .tree => obj.?.cast(.tree).?,
        .blob => return writer.writeAll("This is not a commit or tree hash\n"),
        .tag => return writer.writeAll("TODO, implement for tag\n"),
    };
    defer tree.deinit(gpa);

    repo.checkout(tree, path.?[6..]) catch |err| {
        switch (err) {
            error.PathAlreadyExists => try writer.writeAll("Path already exists\n"),
            else => return err,
        }
    };
}

/// Returns the log of the given branch
fn handleLog(gpa: *Allocator, args: [][]const u8, writer: anytype) !void {
    const branch = if (args.len > 1) args[1] else return writer.writeAll("Missing branch name\n");

    var repo = (try Repository.find(gpa)) orelse return writer.writeAll("Not a Git repository\n");
    defer repo.deinit();

    const path = try std.fs.path.join(gpa, &[_][]const u8{ "refs", "heads" });
    defer gpa.free(path);

    const ref = (try refs.findByName(repo, gpa, branch)) orelse return writer.writeAll("Branch does not exist\n");
    defer ref.deinit(gpa);

    try writer.print("{} {}", .{ ref.name, ref.hash });
}

/// Shows a list of all tags or creates a new one if a name argument is given
fn handleTag(gpa: *Allocator, args: [][]const u8, writer: anytype) !void {
    const name = if (args.len > 1) args[1] else null;

    var repo = (try Repository.find(gpa)) orelse return writer.writeAll("Not a Git repository\n");
    defer repo.deinit();

    const found_tags = refs.findInPath(repo, gpa, "refs/tags") catch return writer.writeAll("There's currently no tags\n");
    defer {
        for (found_tags) |tag| tag.deinit(gpa);
        gpa.free(found_tags);
    }

    for (found_tags) |tag|
        try writer.print("{} {}", .{ tag.name, tag.hash });
}
