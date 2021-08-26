const std = @import("std");
const Pkg = std.build.Pkg;
const string = []const u8;

pub const cache = ".zigmod\\deps";

pub fn addAllTo(exe: *std.build.LibExeObjStep) void {
    @setEvalBranchQuota(1_000_000);
    for (packages) |pkg| {
        exe.addPackage(pkg.pkg.?);
    }
    inline for (std.meta.declarations(package_data)) |decl| {
        const pkg = @as(Package, @field(package_data, decl.name));
        var llc = false;
        inline for (pkg.system_libs) |item| {
            exe.linkSystemLibrary(item);
            llc = true;
        }
        inline for (pkg.c_include_dirs) |item| {
            exe.addIncludeDir(@field(dirs, decl.name) ++ "/" ++ item);
            llc = true;
        }
        inline for (pkg.c_source_files) |item| {
            exe.addCSourceFile(@field(dirs, decl.name) ++ "/" ++ item, pkg.c_source_flags);
            llc = true;
        }
        if (llc) {
            exe.linkLibC();
        }
    }
}

pub const Package = struct {
    directory: string,
    pkg: ?Pkg = null,
    c_include_dirs: []const string = &.{},
    c_source_files: []const string = &.{},
    c_source_flags: []const string = &.{},
    system_libs: []const string = &.{},
};

const dirs = struct {
    pub const _root = "";
    pub const _jzmgxcgdmb91 = cache ++ "/../..";
    pub const _pwblq5jcdktq = cache ++ "/git/github.com/nektro/zig-zlib/";
    pub const _m7bcg7m71n5g = cache ++ "/v/git/github.com/madler/zlib/tag-v1.2.11";
};

pub const package_data = struct {
    pub const _pwblq5jcdktq = Package{
        .directory = dirs._pwblq5jcdktq,
        .pkg = Pkg{ .name = "zlib", .path = .{ .path = dirs._pwblq5jcdktq ++ "/src/lib.zig" }, .dependencies = null },
    };
    pub const _jzmgxcgdmb91 = Package{
        .directory = dirs._jzmgxcgdmb91,
        .pkg = Pkg{ .name = "lemon", .path = .{ .path = dirs._jzmgxcgdmb91 ++ "/src/lemon.zig" }, .dependencies = &.{ _pwblq5jcdktq.pkg.? } },
    };
    pub const _root = Package{
        .directory = dirs._root,
    };
    pub const _m7bcg7m71n5g = Package{
        .directory = dirs._m7bcg7m71n5g,
        .c_include_dirs = &.{ "" },
        .c_source_files = &.{ "inftrees.c", "inflate.c", "adler32.c", "zutil.c", "trees.c", "gzclose.c", "gzwrite.c", "gzread.c", "deflate.c", "compress.c", "crc32.c", "infback.c", "gzlib.c", "uncompr.c", "inffast.c" },
    };
};

pub const packages = &[_]Package{
    package_data._jzmgxcgdmb91,
};

pub const pkgs = struct {
    pub const lemon = package_data._jzmgxcgdmb91;
};

pub const imports = struct {
    pub const lemon = @import(".zigmod\\deps/../../src/lemon.zig");
};
