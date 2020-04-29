const std = @import("std");
const testing = std.testing;

pub const Repository = struct {
    const Self = @This();
    working_tree: []const u8,
    git_dir: []const u8,

    fn init(allocator: *std.mem.Allocator, path: []u8, force: bool) !Self {
        var self: Self = undefined;
        self.working_tree = path;
        self.git_dir = try std.fs.path.join(allocator, &[_][]const u8{
            path,
            ".git",
        });

        // TODO: Check if dir exists instead of checking if it's a file.
        if (!force and std.fs.path.dirname(self.git_dir) == null) {
            return error.NotGitRepository;
        }

        return self;
    }

    fn create(self: Self) !void {
        // attempt to create a directory with read and write permissions for current user
        std.os.mkdir(self.working_tree, 0o600) catch |err| return err;
    }
};

test "Repo directories set correctly" {
    const cwd = try std.process.getCwdAlloc(testing.allocator);
    const repo = try Repository.init(testing.allocator, cwd, false);

    try repo.create();
    std.debug.warn("\nwt: {}\n", .{repo.working_tree});
    testing.allocator.free(cwd);
    testing.allocator.free(repo.git_dir);
}
