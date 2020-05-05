const std = @import("std");
const Repository = @import("repository.zig").Repository;
const fs = std.fs;

const ReadError = error{
    RepositoryNotInitialized,
    BadFile,
    InvalidType,
    InvalidSize,
};

const Kind = enum {
    Blob,
    Commit,
    Tree,
};

const Header = struct {
    kind: Kind,
    size: usize,
    offset: usize,
};

fn parseHeader(buffer: []u8) ReadError!Header {
    var i: usize = 0;
    while (i < buffer.len) : (i += 1) {
        if (std.mem.eql(u8, buffer[i], " ")) {
            break;
        }
    }

    const raw = buffer[0..i];
    const kind = parseType(raw) catch |err| return err;

    var j: usize = i;
    while (j < buffer.len) : (j += 1) {
        if (std.mem.eql(u8, buffer[j], '\x00')) {
            break;
        }
    }
    const sizeBytes = buffer[i..j];
    const size = std.fmt.parseInt(usize, sizeBytes, 16);
    if (size != (raw.len - j - 1)) return ReadError.InvalidSize;

    return .{
        .kind = kind,
        .size = size,
        .offset = j + 1,
    };
}

fn parseType(val: []const u8) ReadError!Kind {
    return switch (val) {
        "commit" => .Commit,
        "tree" => .Tree,
        "blob" => .Blob,
        else => ReadError.InvalidType,
    };
}

fn kindToString(kind: Kind) []const u8 {
    return switch (kind) {
        .Blob => "blob",
        .Commit => "commit",
        .Tree => "tree",
    };
}

const Object = struct {
    const Self = @This();

    data: []u8,
    kind: Kind,
    size: usize = 0,
    repo: *Repository,

    pub fn init(repo: *Repository) !Self {
        if (!repo.initialized()) {
            return .RepositoryNotInitialized;
        }

        return .{ .repo = repo };
    }

    pub fn decode(self: *Self, allocator: *std.mem.Allocator, hash: [20]u8) ReadError!void {
        const path = fs.path.join(allocator, &[_][]u8{
            "objects",
            hash[0..2],
            hash[2..],
        }) catch |err| return err;
        defer allocator.free(path);

        const file = repo.git_dir.?.openFile(path, .{ .read = true }) catch |err| return .BadFile;
        defer file.close();

        const stat = file.stat() catch |err| return .BadFile;
        const buffer = allocator.alloc(u8, stat.size);
        defer allocator.free(buffer);

        const len = file.read(buffer) catch |err| return .BadFile;

        // TODO: Do zlib decompression here

        const header = parseHeader(buffer);
        self.data = buffer[header.offset..];
        self.kind = header.kind;
        self.size = header.size;
    }

    pub fn encode(self: Self, allocator: *std.mem.Allocator, data: []u8) WriteError![20]u8 {
        const kind = kindToString(self.kind);
        const sizeString = intToSlice(data.len);
        const content = &[_][]u8{
            kind,
            " ",
            data.len,
            '\x00',
            data,
        };
        // create our buffer
        const size = kind.len + 1 + sizeString.len + '\x00'.len + data.len;
        var buffer = allocator.alloc(u8, size);
        defer allocator.free(buffer);

        // fill our buffer with the content
        var i: usize = 0;
        for (content) |val| {
            for (val) |c| {
                buffer[i] = c;
                i += 1;
            }
        }

        // Create hash
        var sha1 = std.crypto.Sha1.init();
        var hash: [sha1.digest_length]u8 = undefined;
        sha1.update(buffer);
        sha1.final(hash);

        const path = fs.path.join(allocator, &[_][]u8{
            "objects",
            hash[0..2],
            hash[2..],
        }) catch |err| return err;
        defer allocator.free(path);

        // write contents to our file
        var file = self.repo.git_dir.?.openFile(path, .{ .write = true });
        // TODO: Replace buffer with zlib compressed content
        file.writeAll(buffer) catch |err| return err;
    }
};

fn intToSlice(val: u64) []const u8 {
    var bytes: [8]u8 = undefined;
    std.mem.writeIntBig(u64, &bytes, val);
    return bytes[0..];
}

const Blob = struct {
    const Self = @This();
    data: []const u8,
    hash: [20]u8,

    pub fn init(repo: *repository) Self {}

    pub fn serialize(data: []u8) []u8 {
        return data;
    }

    pub fn deserialize(self: *Self) void {}
};
