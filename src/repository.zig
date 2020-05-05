const std = @import("std");
const os = std.os;
const fs = std.fs;
const testing = std.testing;

pub const Repository = struct {
    const Self = @This();

    working_tree: ?fs.Dir,
    git_dir: ?fs.Dir,
    working_path: []const u8,
    allocator: *std.mem.Allocator,

    /// init initiates a Repository object within the provided path.
    /// `path` is the relative path to the current working directory.
    pub fn init(allocator: *std.mem.Allocator, path: []const u8) !Self {
        var self: Self = undefined;
        self.allocator = allocator;

        self.working_path = fs.path.join(allocator, &[_][]const u8{
            path,
            "abc",
        }) catch |err| return err;
        const git_path = fs.path.join(allocator, &[_][]const u8{
            self.working_path,
            ".git",
        }) catch |err| return err;
        defer allocator.free(git_path);

        const cwd = fs.cwd();
        if (cwd.openDir(self.working_path, fs.Dir.OpenDirOptions{ .iterate = true })) |dir| {
            self.working_tree = dir;
        } else |_| {}

        if (cwd.openDir(git_path, fs.Dir.OpenDirOptions{ .iterate = true })) |dir| {
            self.git_dir = dir;
        } else |_| {}

        return self;
    }

    /// Find will try to look for a Git repository from within the current working directory.
    /// It searches recursively through its parents. Will return false if nothing found.
    pub fn find(self: *Self) !bool {
        if (self.initialized()) return true;

        // cwd does not have iterate rights, therefore re-open current working directory with correct rights.
        var dir = fs.cwd().openDir(".", .{ .iterate = true }) catch |err| return err;

        // get path of current working directory and free its memory on finishing
        var cwd = std.process.getCwdAlloc(self.allocator) catch |err| return err;
        defer self.allocator.free(cwd);

        // loop over the current directory and set current to parent if nothing found
        scan_dir: while (true) {
            // iterate over childs to detect .git directory
            var dir_it = dir.iterate();
            while (try dir_it.next()) |entry| {
                if (std.mem.eql(u8, entry.name, ".git") and entry.kind == fs.Dir.Entry.Kind.Directory) {
                    self.working_tree = dir;

                    self.git_dir = dir.openDir(".git", .{ .iterate = true }) catch |err| return err;
                    return true;
                }
            }
            // if current directory is root
            if (std.mem.eql(u8, cwd, fs.path.sep_str)) {
                return false;
            }

            // try to resolve path to the parent
            const tmp = fs.path.resolve(self.allocator, &[_][]const u8{
                cwd,
                "..",
            }) catch |err| return err;

            // cleanup memory and set cwd to new path
            self.allocator.free(cwd);
            cwd = tmp;

            // actually open the parent
            const new_dir = dir.openDir("..", .{ .iterate = true }) catch |err| return err;

            // close the previous directory
            dir.close();

            // assign new directory
            dir = new_dir;

            // continue back to loop
            continue :scan_dir;
        }

        return false;
    }

    /// Attempts to create a new Git repository from the current path
    pub fn create(self: *Self) !void {
        const tmp = fs.cwd();
        tmp.makePath(self.working_path) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
        const working_tree = tmp.openDir(self.working_path, fs.Dir.OpenDirOptions{ .iterate = true }) catch |err| return err;

        working_tree.makeDir(".git") catch |err| return err;
        const git_dir = working_tree.openDir(".git", fs.Dir.OpenDirOptions{ .iterate = true }) catch |err| return err;

        // setup .git directory structure
        git_dir.makeDir("branches") catch |err| return err;
        git_dir.makeDir("objects") catch |err| return err;

        const tags = fs.path.join(self.allocator, &[_][]const u8{
            "refs",
            "tags",
        }) catch |err| return err;
        defer self.allocator.free(tags);

        const heads = fs.path.join(self.allocator, &[_][]const u8{
            "refs",
            "heads",
        }) catch |err| return err;
        defer self.allocator.free(heads);

        git_dir.makePath(tags) catch |err| return err;
        git_dir.makePath(heads) catch |err| return err;

        // Create our start files
        const desc_file = git_dir.createFile("description", fs.File.CreateFlags{}) catch |err| return err;
        _ = desc_file.write("Unnamed repository; edit this file 'description' to name the repository.\n") catch |err| return err;
        desc_file.close();

        const head_file = git_dir.createFile("HEAD", fs.File.CreateFlags{}) catch |err| return err;
        _ = head_file.write("ref: refs/heads/master\n") catch |err| return err;
        head_file.close();

        const config_file = git_dir.createFile("config", fs.File.CreateFlags{}) catch |err| return err;
        _ = config_file.write(configFile) catch |err| return err;
        config_file.close();

        self.working_tree = working_tree;
        self.git_dir = git_dir;
    }

    /// Frees memory and closes the directories so other processes can use them.
    pub fn deinit(self: *Self) void {
        self.allocator.free(self.working_path);
        if ((self.git_dir)) |*dir| {
            dir.close();
        }
        if (self.working_tree) |*dir| {
            dir.close();
        }
    }

    /// Returns true if current git directory is set.
    pub fn initialized(self: Self) bool {
        return self.git_dir != null;
    }
};

const configFile = @embedFile("assets/config");

test "Repo directories set correctly" {
    const cwd = try std.process.getCwdAlloc(testing.allocator);
    var repo = try Repository.init(testing.allocator, cwd);

    std.debug.warn("\nwt: {}\n", .{repo.working_tree});
    repo.deinit();
    testing.allocator.free(cwd);
}

test "Find repo" {
    var repo = try Repository.init(testing.allocator, ".");
    const found = repo.find();

    std.debug.warn("\nfound: {}\n", .{found});
    repo.deinit();
}
