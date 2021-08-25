const std = @import("std");
const fs = std.fs;
const Allocator = std.mem.Allocator;
const Repository = @import("repository.zig").Repository;

/// Errors that can be thrown while decoding an object file
const ReadError = error{
    /// Object file contains an incorrect type
    InvalidType,
    /// Size in object file does not match expected length
    InvalidSize,
};

/// Object's kind
const Kind = enum {
    /// Raw file data
    blob,
    /// Commit object, containing information such as tree, author, etc
    commit,
    /// Contains all leaf objects
    tree,
    /// Tag object, references a name/version to an object such as a commit
    tag,

    /// Returns the `type` that corresponds to the `Kind`
    pub fn Type(self: Kind) type {
        return switch (self) {
            .commit => Commit,
            .blob => Blob,
            .tree => Tree,
            .tag => Tag,
        };
    }
};

/// Header of an object file
const Header = struct {
    /// object type
    kind: Kind,
    /// data size
    size: usize,
    /// offset of where the data starts after the header
    offset: usize,
};

/// Parses the given buffer in a `Header` struct
fn parseHeader(buffer: []const u8) (ReadError || std.fmt.ParseIntError)!Header {
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

/// Object is a type used internally by Git to compress and
/// store the data of Git objects. An object can be a `Commit`,
/// `Tree`, `Blob` or `Tag`.
pub const Object = struct {
    kind: Kind,

    /// Finds the corresponding object file and decodes the decompressed data
    /// The memory owned by `Object` is owned by the caller and must be freed by the caller
    /// this can be done by calling deinit().
    ///
    /// `hash` must be a valid, checked, hash with a length of 40.
    pub fn decode(repo: Repository, gpa: *Allocator, hash: []const u8) !*Object {
        const path = try fs.path.join(gpa, &[_][]const u8{
            "objects",
            hash[0..2],
            hash[2..],
        });
        defer gpa.free(path);

        const file = try repo.git_dir.openFile(path, .{ .read = true });
        defer file.close();

        var zlib_stream = try std.compress.zlib.zlibStream(gpa, file.reader());
        defer gpa.free(zlib_stream.window_slice);
        const data = try zlib_stream.reader().readAllAlloc(gpa, std.math.maxInt(usize));
        defer gpa.free(data);

        const header = try parseHeader(data);

        const allocated_data = try gpa.dupe(u8, data[header.offset..]);
        errdefer gpa.free(allocated_data);

        return switch (header.kind) {
            .blob => {
                const blob = try gpa.create(Blob);
                errdefer gpa.destroy(blob);
                blob.* = Blob.deserialize(allocated_data);

                return &blob.base;
            },
            .commit => {
                const commit = try gpa.create(Commit);
                errdefer gpa.destroy(commit);
                commit.* = Commit.deserialize(allocated_data);

                return &commit.base;
            },
            .tree => {
                const tree = try gpa.create(Tree);
                errdefer gpa.destroy(tree);
                tree.* = try Tree.deserialize(gpa, allocated_data);

                return &tree.base;
            },
            .tag => {
                const tag = try gpa.create(Tag);
                errdefer gpa.destroy(tag);
                tag.* = Tag.deserialize(allocated_data);

                return &tag.base;
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

    /// Serializes an object and writes it to a stream for now, this can be removed when encode is
    /// fully implemented
    pub fn serialize(self: *Object, writer: anytype) @TypeOf(writer).Error!void {
        switch (self.kind) {
            .blob => {
                const blob = self.cast(.blob).?;
                try writer.writeAll(blob.data);
            },
            .commit => {
                const commit = self.cast(.commit).?;
                try writer.print("{s}\n", .{commit.message});
            },
            .tree => {
                const tree = self.cast(.tree).?;
                try writer.print("{s}\n", .{tree.leafs[0].hash});
            },
            .tag => {
                const tag = self.cast(.tag).?;
                try writer.print("{s}\n", .{tag});
            },
        }
    }

    /// Returns the Typed Object with its data
    /// Returns null if the kind of the given `Object` is not the same
    /// as the expected `kind`.
    pub fn cast(self: *Object, comptime kind: Kind) ?*kind.Type() {
        if (self.kind != kind) return null;

        return @fieldParentPtr(kind.Type(), "base", self);
    }

    /// Returns the corresponding `type` of the `Kind`.
    /// Frees the object's memory, this has to be called after calling
    /// `Object.decode()`
    pub fn deinit(self: *Object, gpa: *Allocator) void {
        switch (self.kind) {
            .blob => self.cast(.blob).?.deinit(gpa),
            .commit => self.cast(.commit).?.deinit(gpa),
            .tree => self.cast(.tree).?.deinit(gpa),
            .tag => self.cast(.tag).?.deinit(gpa),
        }
    }
};

/// Blob object that contains raw file data
pub const Blob = struct {
    base: Object,
    /// raw file data
    data: []const u8,

    /// Simply returns a new `Blob` object as buffer already contains the raw data
    pub fn deserialize(buffer: []const u8) Blob {
        return .{
            .base = .{ .kind = .blob },
            .data = buffer,
        };
    }

    /// Frees Blob's memory
    pub fn deinit(self: *Blob, gpa: *Allocator) void {
        gpa.free(self.data);
        gpa.destroy(self);
    }
};

/// Tree structured object that points to `Leaf` objects
/// which contain a mode, path and hash
pub const Tree = struct {
    base: Object,
    /// List of `Leaf`
    leafs: []Leaf,
    /// Raw data of `Tree`, used to free all data at once
    data: []const u8,

    /// Leaf that belongs to a Tree which can point to commits
    pub const Leaf = struct {
        /// file mode
        mode: usize,
        /// path of the 'file'
        path: []const u8,
        /// corresponding hash
        hash: []const u8,
    };

    /// Parses the input `buffer` and turns it into a `Tree` `Object`
    /// Memory is owned by the returned Tree object.
    pub fn deserialize(gpa: *Allocator, buffer: []u8) !Tree {
        var leafs = std.ArrayList(Leaf).init(gpa);
        errdefer {
            for (leafs.items) |leaf| gpa.free(leaf.hash);
            leafs.deinit();
        }

        var pos: usize = 0;
        while (pos < buffer.len) {
            const index = std.mem.indexOf(u8, buffer[pos..], " ").?;
            const mode = buffer[pos .. pos + index];
            pos += index;
            const end = std.mem.indexOf(u8, buffer[pos..], "\x00").?;
            const path = buffer[pos + 1 .. pos + end];
            pos += path.len + 1;

            var hash: [40]u8 = undefined;
            try bytesToHex(&hash, buffer[pos .. pos + 20]);

            pos += 21;

            try leafs.append(.{
                .mode = try std.fmt.parseInt(usize, mode, 10),
                .path = path,
                .hash = try gpa.dupe(u8, hash[2..]),
            });
        }

        return Tree{
            .base = .{ .kind = .tree },
            .leafs = leafs.toOwnedSlice(),
            .data = buffer,
        };
    }

    /// Frees memory of Tree object
    /// Expected to be called on Tree object after Object.decode() has created this object
    pub fn deinit(self: *Tree, gpa: *Allocator) void {
        for (self.leafs) |leaf| {
            gpa.free(leaf.hash);
        }
        gpa.free(self.leafs);
        gpa.free(self.data);
        gpa.destroy(self);
    }
};

/// Converts a slice to a Hex string
fn bytesToHex(out: []u8, input: []const u8) !void {
    if (out.len / 2 != input.len) return error.InvalidSize;

    const hextable = "0123456789abcdef";

    for (input) |c, i| {
        out[i * 2] = hextable[c >> 4];
        out[i * 2 + 1] = hextable[c & 0x0F];
    }
}

/// Commit `Object` with its optional data
/// Note that all fields are named after their represental
/// data fields as this allows for easy parsing
pub const Commit = struct {
    base: Object,
    /// Points to the hash of the tree
    tree: []const u8,
    /// Optional parent's hash
    parent: ?[]const u8,
    /// Author data
    author: []const u8,
    /// Committer data, not neccesairely the same as the `author`
    committer: []const u8,
    /// Optional GPG signature
    gpgsig: ?[]const u8,
    /// Message emitted when the commit was applied
    message: []const u8,
    /// contains complete commit data, used to free all memory at once
    data: []const u8,

    /// Returns the `Tree` that the Commit points to
    pub fn getTree(self: Commit, repo: Repository, gpa: *Allocator) !*Tree {
        const tree = (try repo.findObject(gpa, self.tree)).?;

        return tree.cast(.tree).?;
    }

    /// Deserializes the `buffer` data into a `Commit`
    pub fn deserialize(buffer: []const u8) Commit {
        const State = enum { key, value };

        var state = State.key;
        var commit = Commit{
            .base = .{ .kind = .commit },
            .tree = undefined,
            .parent = null,
            .author = undefined,
            .committer = undefined,
            .gpgsig = null,
            .message = undefined,
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
                                if (@TypeOf(@field(commit, field.name)) == ?[]const u8 or
                                    @TypeOf(@field(commit, field.name)) == []const u8)
                                    @field(commit, field.name) = last_value;
                            }
                        }
                    }
                },
            }
            prev = c;
        }

        // -1 because we don't want the \n in our message at the end
        commit.message = buffer[index .. buffer.len - 1];

        return commit;
    }

    /// Frees memory of the `Commit`
    pub fn deinit(self: *Commit, gpa: *Allocator) void {
        gpa.free(self.data);
        gpa.destroy(self);
    }
};

/// Tag `Object` which is a reference that points at HEAD or an other `Object`
pub const Tag = struct {
    base: Object,
    /// Author who created the Tag
    author: []const u8,
    /// Date when the Tag was created
    date: []const u8,
    /// Optional GPG signature of the author
    gpgsig: ?[]const u8,
    /// Optional annotation of the Tag
    annotation: ?[]const u8,
    /// Contains raw data, used to free all data at once
    data: []const u8,

    /// Deserializes the raw data into a `Tag` object
    /// The memory is owned by the caller and can be freed using deinit()
    pub fn deserialize(buffer: []const u8) Tag {
        // perhaps we could merge this with Commit's deserialize some way.
        var tag = Tag{
            .base = .{ .kind = .tag },
            .author = undefined,
            .date = undefined,
            .gpgsig = null,
            .annotation = null,
            .data = buffer,
        };

        const State = enum { key, value };

        var state = State.key;
        var last_key: []const u8 = undefined;
        var last_value: []const u8 = undefined;
        var prev: u8 = undefined;

        var index: usize = 0;
        for (buffer) |c, i| {
            switch (state) {
                .key => {
                    if (c == ' ') {
                        last_key = buffer[index..i];
                        inline for (@typeInfo(Tag).Struct.fields) |field| {
                            if (std.mem.eql(u8, field.name, last_key)) {
                                if (@hasField(Tag, field.name)) {
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
                        inline for (@typeInfo(Tag).Struct.fields) |field| {
                            if (std.mem.eql(u8, field.name, last_key)) {
                                if (@TypeOf(@field(tag, field.name)) == ?[]const u8 or
                                    @TypeOf(@field(tag, field.name)) == []const u8)
                                    @field(tag, field.name) = last_value;
                            }
                        }
                    }
                },
            }
            prev = c;
        }

        return tag;
    }

    /// Frees all data of the Tag.
    pub fn deinit(self: *Tag, gpa: *Allocator) void {
        gpa.free(self.data);
        gpa.destroy(self);
    }
};

test "Test decode" {
    var repo = (try Repository.find(std.testing.allocator)).?;
    defer repo.deinit();

    const object = try Object.decode(repo, std.testing.allocator, "8bc9a453e049d06ba4eaac24297d371de53c9603");
    defer object.deinit(std.testing.allocator);
}
