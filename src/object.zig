const std = @import("std");
const fs = std.fs;
const Allocator = std.mem.Allocator;

usingnamespace @import("repository.zig");

/// Errors that can be thrown while decoding an object file
const ReadError = error{
    BadFile,
    InvalidType,
    InvalidSize,
};

/// Object's kind
const Kind = enum {
    blob,
    commit,
};

/// Header of a object file
const Header = struct {
    kind: Kind,
    size: usize,
    offset: usize,
};

/// Parses the given buffer in a `Header` struct
fn parseHeader(buffer: []u8) (ReadError || std.fmt.ParseIntError)!Header {
    var i: usize = 0;
    while (i < buffer.len) : (i += 1) if (buffer[i] == ' ') break;

    const raw = buffer[0..i];
    const kind = std.meta.stringToEnum(Kind, raw) orelse return ReadError.InvalidType;

    var j: usize = i + 1;
    while (j < buffer.len) : (j += 1) if (buffer[j] == '\x00') break;

    const sizeBytes = buffer[i + 1 .. j];
    const size = try std.fmt.parseInt(usize, sizeBytes, 10);
    if (size != (buffer.len - j - 1)) return ReadError.InvalidSize;

    return Header{
        .kind = kind,
        .size = size,
        .offset = j + 1,
    };
}

/// Returns the string value of a `Kind`
fn kindToString(kind: Kind) []const u8 {
    return @tagName(kind);
}

pub const Object = struct {
    kind: Kind,

    /// Finds the corresponding object file and decodes the decompressed data
    /// The memory owned by `Object` is owned by the caller and must be freed by the caller
    pub fn decode(repo: Repository, hash: []const u8) !*Object {
        const path = try fs.path.join(repo.gpa, &[_][]const u8{
            "objects",
            hash[0..2],
            hash[2..],
        });
        defer repo.gpa.free(path);

        const file = try repo.git_dir.openFile(path, .{ .read = true });
        defer file.close();

        var zlib_stream = try std.compress.zlib.zlibStream(repo.gpa, file.reader());
        defer repo.gpa.free(zlib_stream.window_slice);
        const data = try zlib_stream.reader().readAllAlloc(repo.gpa, std.math.maxInt(usize));
        defer repo.gpa.free(data);

        const header = try parseHeader(data);

        return switch (header.kind) {
            .blob => {
                const blob = try repo.gpa.create(Blob);
                blob.* = .{
                    .base = Object{ .kind = .blob },
                    .data = try repo.gpa.dupe(u8, data[header.offset..]),
                };

                return &blob.base;
            },
            .commit => {
                const commit = try repo.gpa.create(Commit);
                commit.* = Commit.deserialize(try repo.gpa.dupe(u8, data[header.offset..]));

                return &commit.base;
            },
        };
    }

    /// Compresses the Object, its data and writes it to an object file
    /// This will return the hash
    pub fn encode(self: Object, gpa: *Allocator, data: []u8) WriteError![20]u8 {
        @compileError("TODO implement when zlib compression is supported");
        const kind = kindToString(self.kind);
        const sizeString = std.mem.toBytes(data.len);
        const content = &[_][]u8{
            kind,
            " ",
            data.len,
            '\x00',
            data,
        };
        // create our buffer
        const size = kind.len + 1 + sizeString.len + '\x00'.len + data.len;
        var buffer = gpa.alloc(u8, size);
        defer gpa.free(buffer);

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

        const path = try fs.path.join(gpa, &[_][]u8{
            "objects",
            hash[0..2],
            hash[2..],
        });
        defer gpa.free(path);

        // write contents to our file
        var file = try self.repo.git_dir.?.openFile(path, .{ .write = true });
        defer file.close();
        // TODO: Replace buffer with zlib compressed content
        try file.writeAll(buffer);
    }

    /// Serializes an object and writes it to a stream
    pub fn serialize(self: *Object, writer: anytype) @TypeOf(writer).Error!void {
        switch (self.kind) {
            .blob => {
                const blob = @fieldParentPtr(Blob, "base", self);
                try writer.writeAll(blob.data);
            },
            .commit => {
                const commit = @fieldParentPtr(Commit, "base", self);
                //try writer.print("{}\n", .{commit});
            },
        }
    }

    /// Frees the object's memory
    pub fn deinit(self: *Object, gpa: *Allocator) void {
        switch (self.kind) {
            .blob => {
                const blob = @fieldParentPtr(Blob, "base", self);
                gpa.free(blob.data);
                gpa.destroy(blob);
            },
            .commit => {
                const commit = @fieldParentPtr(Commit, "base", self);
                commit.deinit(gpa);
            },
        }
    }
};

pub const Blob = struct {
    base: Object,
    data: []const u8,
};

pub const Tree = struct {
    base: Object,
    data: []const u8,
};

pub const Commit = struct {
    base: Object,
    tree: ?[]const u8,
    parent: ?[]const u8,
    author: ?[]const u8,
    committer: ?[]const u8,
    gpgsig: ?[]const u8,
    message: ?[]const u8,
    data: []const u8,

    /// Deserializes the `buffer` data into a `Commit`
    pub fn deserialize(buffer: []const u8) Commit {
        const State = enum { key, value };

        var state = State.key;
        var commit = Commit{
            .base = Object{ .kind = .commit },
            .tree = null,
            .parent = null,
            .author = null,
            .committer = null,
            .gpgsig = null,
            .message = null,
            .data = buffer,
        };

        var last_key: []const u8 = undefined;
        var last_value: []const u8 = undefined;
        var prev: u8 = undefined;

        var index: usize = 0;
        for (buffer) |c, i| {
            switch (state) {
                .key => {
                    if (c == ' ') {
                        last_key = buffer[index..i];
                        inline for (@typeInfo(Commit).Struct.fields) |field| {
                            if (std.mem.eql(u8, field.name, last_key)) {
                                if (@hasField(Commit, field.name)) {
                                    index = i + 1;
                                    state = .value;
                                }
                            }
                        }
                    }
                    if (c == '\n') {
                        index += 1;
                        break;
                    }
                },
                .value => {
                    if (prev == '\n' and c != ' ') {
                        last_value = buffer[index .. i - 1];
                        index += last_value.len + 1;
                        state = .key;
                        inline for (@typeInfo(Commit).Struct.fields) |field| {
                            if (std.mem.eql(u8, field.name, last_key)) {
                                if (@TypeOf(@field(commit, field.name)) == ?[]const u8)
                                    @field(commit, field.name) = last_value;
                            }
                        }
                    }
                },
            }
            prev = c;
        }
        commit.message = buffer[index..buffer.len];

        return commit;
    }

    /// Frees memory of the Object
    pub fn deinit(self: *Commit, gpa: *Allocator) void {
        gpa.free(self.data);
        gpa.destroy(self);
    }
};

fn parseCommit(buffer: []const u8) !Commit {}

test "Test decode" {
    var repo = try Repository.find(std.testing.allocator);
    defer repo.?.deinit();

    const object = try Object.decode(repo.?, std.testing.allocator, "8bc9a453e049d06ba4eaac24297d371de53c9603");
    defer std.testing.allocator.free(object.data);
}
