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
        if (cwd.openDir(self.working_path, fs.Dir.OpenDirOptions{})) |dir| {
            self.working_tree = dir;
        } else |_| {}

        if (cwd.openDir(git_path, fs.Dir.OpenDirOptions{})) |dir| {
            self.git_dir = dir;
        } else |_| {}

        return self;
    }

    pub fn create(self: *Self) !void {
        const tmp = fs.cwd();
        tmp.makePath(self.working_path) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
        const working_tree = tmp.openDir(self.working_path, fs.Dir.OpenDirOptions{}) catch |err| return err;

        working_tree.makeDir(".git") catch |err| return err;
        const git_dir = working_tree.openDir(".git", fs.Dir.OpenDirOptions{}) catch |err| return err;

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

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.working_path);
        if ((self.git_dir)) |*dir| {
            dir.close();
        }
        if (self.working_tree) |*dir| {
            dir.close();
        }
    }

    pub fn initialized(self: Self) bool {
        return self.git_dir != null;
    }
};

const configFile = @embedFile("assets/config");

test "Repo directories set correctly" {
    const cwd = try std.process.getCwdAlloc(testing.allocator);
    var repo = try Repository.init(testing.allocator, cwd);

    try repo.create();
    std.debug.warn("\nwt: {}\n", .{repo.working_tree});
    repo.deinit();
    testing.allocator.free(cwd);
}
