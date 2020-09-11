const std = @import("std");
const Allocator = std.mem.Allocator;
const fs = std.fs;
const testing = std.testing;
const ref = @import("ref.zig");

usingnamespace @import("object.zig");

pub const Repository = struct {
    /// Working tree of the repository
    working_tree: fs.Dir,
    /// Directory where all Git objects are stored
    git_dir: fs.Dir,
    /// Path to the working directory
    working_path: []const u8,

    gpa: *Allocator,

    /// Find will try to look for a Git repository from within the current working directory.
    /// It searches recursively through its parents. Will return null if no Repository is found
    ///
    /// Deinit() must be called on the `Repository` to free its memory
    pub fn find(gpa: *Allocator) !?Repository {
        // cwd does not have iterate rights, therefore re-open current working directory with correct rights.
        var dir = try fs.cwd().openDir(".", .{ .iterate = true });
        errdefer dir.close();

        // get path of current working directory and free its memory on finishing
        var cwd = try std.process.getCwdAlloc(gpa);
        defer gpa.free(cwd);

        // loop over the current directory and set current to parent if nothing found
        while (true) {
            // iterate over childs to detect .git directory
            var dir_it = dir.iterate();
            while (try dir_it.next()) |entry| {
                if (std.mem.eql(u8, entry.name, ".git") and entry.kind == fs.Dir.Entry.Kind.Directory) {
                    return Repository{
                        .working_tree = dir,
                        .working_path = try gpa.dupe(u8, cwd),
                        .git_dir = try dir.openDir(".git", .{}),
                        .gpa = gpa,
                    };
                }
            }

            // if current directory is root
            if (std.mem.eql(u8, cwd, fs.path.sep_str)) {
                dir.close();
                return null;
            }

            // try to resolve path to the parent
            const tmp = try fs.path.resolve(gpa, &[_][]const u8{
                cwd,
                "..",
            });

            // cleanup old cwd memory and set cwd to new path
            gpa.free(cwd);
            cwd = tmp;

            // actually open the parent
            const new_dir = try dir.openDir("..", .{ .iterate = true });

            // close the previous directory
            dir.close();

            // assign new directory
            dir = new_dir;
        }

        return false;
    }

    /// Attempts to create a new Git repository from the current path
    /// Memory is owned by the Repository and must be freed by calling deinit()
    pub fn create(gpa: *Allocator, path: []const u8) !Repository {
        var tmp = fs.cwd();

        try tmp.makePath(path);

        var working_tree = try tmp.openDir(path, fs.Dir.OpenDirOptions{ .iterate = true });

        try working_tree.makeDir(".git");
        errdefer working_tree.close();
        var git_dir = try working_tree.openDir(".git", fs.Dir.OpenDirOptions{ .iterate = true });
        errdefer git_dir.close();

        // setup .git directory structure
        try git_dir.makeDir("branches");
        try git_dir.makeDir("objects");

        try git_dir.makePath("refs" ++ std.fs.path.sep_str ++ "tags");
        try git_dir.makePath("refs" ++ std.fs.path.sep_str ++ "heads");

        // Create our start files
        const desc_file = try git_dir.createFile("description", fs.File.CreateFlags{});
        defer desc_file.close();
        try desc_file.writeAll("Unnamed repository; edit this file 'description' to name the repository.\n");

        const head_file = try git_dir.createFile("HEAD", fs.File.CreateFlags{});
        defer head_file.close();
        try head_file.writeAll("ref: refs/heads/master\n");

        const config_file = try git_dir.createFile("config", fs.File.CreateFlags{});
        defer config_file.close();
        try config_file.writeAll(configFile);

        return Repository{
            .working_path = try gpa.dupe(u8, path),
            .working_tree = working_tree,
            .git_dir = git_dir,
            .gpa = gpa,
        };
    }

    /// Resolves the possible hashes based on a name given. The `name` can be part of the hash,
    /// a tag, the HEAD, etc.
    ///
    /// Returns a list of possible hashes.
    ///
    /// Memory is owned by the caller and each element in the slice should be freed.
    pub fn resolvePart(self: Repository, name: []const u8) !?[][]const u8 {
        if (name.len < 4) return null;

        var list = std.ArrayList([]const u8).init(self.gpa);
        errdefer {
            for (list.items) |item| {
                self.gpa.free(item);
            }
            list.deinit();
        }

        // Resolve by ref
        if (std.mem.eql(u8, name, "HEAD")) {
            const refs = try ref.findInPath(self, self.gpa, name);
            // will only return 1 ref
            defer {
                refs[0].deinit(self.gpa);
                self.gpa.free(refs);
            }

            try list.append(try self.gpa.dupe(u8, refs[0].name));
            return list.toOwnedSlice();
        }

        // If hash, return hash itself
        if (name.len == 40) {
            try list.append(try self.gpa.dupe(u8, name));
            return list.toOwnedSlice();
        }

        // Our return hash, all lowercase
        var low_case = try std.ascii.allocLowerString(self.gpa, name);
        defer self.gpa.free(low_case);

        // generate our path to objects folder
        var path: [10]u8 = undefined;
        std.mem.copy(u8, path[0..9], "objects/");
        std.mem.copy(u8, path[8..10], low_case[0..2]);

        var obj_dir = try self.git_dir.openDir(path[0..], .{ .iterate = true });
        var it = obj_dir.iterate();
        while (try it.next()) |entry| {
            if (std.mem.startsWith(u8, entry.name, low_case[2..])) {
                var hash = try self.gpa.alloc(u8, entry.name.len + 2);
                std.mem.copy(u8, hash[0..2], low_case[0..2]);
                std.mem.copy(u8, hash[2..], entry.name);
                try list.append(hash);
            }
        }

        return list.toOwnedSlice();
    }

    /// Finds an object by its name, is decoded and then returned to the caller
    ///
    /// Memory is owned by the caller and can be freed by calling deinit() on the returned `Object`
    pub fn findObject(self: Repository, gpa: *Allocator, name: []const u8) !?*Object {
        const results = (try resolvePart(self, name)) orelse return null;
        defer {
            for (results) |result| {
                self.gpa.free(result);
            }
            self.gpa.free(results);
        }
        if (results.len > 1) return error.MultipleResults;

        const hash = results[0];

        // for now just return object
        // soon we can return a specific commit, tag or tree
        return try Object.decode(self, gpa, hash);
    }

    /// Checks out a tree in the given path
    /// Returns an error if the path already exists
    pub fn checkout(self: Repository, tree: *const Tree, path: []const u8) anyerror!void {
        try self.working_tree.makeDir(path);

        for (tree.leafs) |leaf| {
            const obj = (try self.findObject(self.gpa, leaf.hash)).?;
            defer obj.deinit(self.gpa);

            const dest = try fs.path.join(self.gpa, &[_][]const u8{ path, leaf.path });
            defer self.gpa.free(dest);

            if (obj.kind == .tree) {
                try self.checkout(obj.cast(.tree).?, dest);
            } else if (obj.kind == .blob) {
                const file = try self.working_tree.createFile(dest, .{});
                defer file.close();

                const blob = obj.cast(.blob).?;
                try file.writer().writeAll(blob.data);
            }
        }
    }

    /// Closes the directories so other processes can use them.
    pub fn deinit(self: *Repository) void {
        self.gpa.free(self.working_path);
        self.git_dir.close();
        self.working_tree.close();
    }
};

const configFile =
    \\[core]
    \\	repositoryformatversion = 0
    \\	filemode = false
    \\	bare = false
    \\	logallrefupdates = true
;

test "Find repo" {
    var repo = try Repository.find(testing.allocator);
    testing.expect(repo != null);
    repo.?.deinit();
}
