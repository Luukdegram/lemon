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
    tree,
    tag,
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
    data: []const u8,

    /// Finds the corresponding object file and decodes the decompressed data
    /// The memory owned by `Object` is owned by the caller and must be freed by the caller
    pub fn decode(repo: *Repository, hash: []const u8) !Object {
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

        return Object{
            .data = try repo.gpa.dupe(u8, data[header.offset..]),
            .kind = header.kind,
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
    pub fn serialize(self: Object, writer: anytype) @TypeOf(writer).Error!void {
        switch (self.kind) {
            .blob => try writer.writeAll(self.data),
            else => {},
        }
    }

    /// Deserializes the data and writes it to the object file
    /// Data is owned by the caller
    pub fn deserialize(self: *Object, buffer: []const u8) Object {
        switch (self.kind) {
            .blob => self.data = buffer,
            else => {},
        }
    }
};

pub const Blob = struct {
    base: Kind,
    data: []const u8,

    /// Blobs is just all file data and can be returned without deserializing
    pub fn deserialize(self: Blog) []const u8 {
        return self.data;
    }
};

pub const Tree = struct {
    base: Kind,
    data: []const u8,
};

test "Test decode" {
    var repo = try Repository.find(std.testing.allocator);
    defer repo.?.deinit();

    const object = try Object.decode(repo.?, std.testing.allocator, "8bc9a453e049d06ba4eaac24297d371de53c9603");
    defer std.testing.allocator.free(object.data);
    std.debug.print("{}\n", .{object.data});
}
