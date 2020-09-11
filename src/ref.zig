const Repository = @import("repository.zig").Repository;
const std = @import("std");
const Allocator = std.mem.Allocator;

/// a `Ref` holds the sha-1 identifier of an object or a reference to another branch
pub const Ref = struct {
    name: []const u8,
    hash: []const u8,

    /// Frees the memory of a `Ref`
    pub fn deinit(self: Ref, gpa: *Allocator) void {
        gpa.free(self.name);
        gpa.free(self.hash);
    }
};
/// A list of `Ref`
pub const Refs = []Ref;

/// Possible errors that can occur when retrieving refs
pub const RefError = error{
    OutOfMemory,
    /// when a path is provided to a non-existing directory
    DirectoryNotFound,
    /// A file was not found
    FileNotFound,
    /// The file or directory is not accessible
    AccessDenied,
    /// An unexpected error occured
    Unexpected,
};

/// Finds all `Refs` within the the given `Repository`
/// Memory is owned by the caller
pub fn findAll(repo: Repository, gpa: *Allocator) RefError!Refs {
    var all_refs = std.ArrayList(Ref).init(gpa);
    errdefer {
        // in case tags errors out, we need to free heads refs too
        for (all_refs.items) |ref| gpa.free(ref);
        all_refs.deinit();
    }

    try all_refs.appendSlice(try findInPath(repo, gpa, "refs/heads"));
    try all_refs.appendSlice(try findInPath(repo, gpa, "refs/tags"));

    return all_refs.toOwnedSlice();
}

/// Finds all refs recursively from the given path
/// Memory is owned by the caller and must be freed using the same allocator.
pub fn findInPath(repo: Repository, gpa: *Allocator, path: []const u8) RefError!Refs {
    var refs = std.ArrayList(Ref).init(gpa);
    errdefer {
        for (refs.items) |ref| ref.deinit(gpa);
        refs.deinit();
    }

    var dir = repo.git_dir.openDir(path, .{ .iterate = true }) catch return RefError.DirectoryNotFound;
    defer dir.close();
    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .File) continue;
        if (entry.kind == .Directory) {
            var new_path = try std.fs.path.join(gpa, &[_][]const u8{ path, entry.name });
            defer gpa.free(new_path);
            try refs.appendSlice(try findInPath(repo, gpa, new_path));
            continue;
        }

        const file = dir.openFile(entry.name, .{}) catch return RefError.FileNotFound;
        defer file.close();

        const data = file.readToEndAlloc(gpa, std.math.maxInt(u64)) catch return RefError.OutOfMemory;

        if (std.mem.startsWith(u8, data, "ref: ")) {
            defer gpa.free(data);
            try refs.appendSlice(try findInPath(repo, gpa, data[5..]));
        } else {
            try refs.append(.{
                .name = try gpa.dupe(u8, entry.name),
                .hash = data,
            });
        }
    }

    return refs.toOwnedSlice();
}

/// Attempts to find a `Ref` by the name of a branch
/// Memory is owned by the caller, must call deinit() on returned `Ref`
pub fn findByName(repo: Repository, gpa: *Allocator, name: []const u8) RefError!?Ref {
    var dir = repo.git_dir.openDir("refs/heads", .{ .iterate = true }) catch return RefError.DirectoryNotFound;
    defer dir.close();

    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind == .File and std.mem.eql(u8, entry.name, name)) {
            var file = dir.openFile(entry.name, .{}) catch return RefError.FileNotFound;
            const data = file.readToEndAlloc(gpa, std.math.maxInt(u64)) catch return RefError.OutOfMemory;
            return Ref{ .name = try gpa.dupe(u8, name), .hash = data };
        }
    }

    return null;
}
