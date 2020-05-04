const std = @import("std");
const Builder = std.build.Builder;

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    const lib = b.addStaticLibrary("lemon", "src" ++ std.fs.path.sep_str ++ "lemon.zig");
    lib.setBuildMode(mode);
    lib.install();

    var main_tests = b.addTest("src/repository.zig");
    main_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);

    const cmd = b.addExecutable("lemon", "cmd" ++ std.fs.path.sep_str ++ "main.zig");
    cmd.addPackagePath("lemon", "src" ++ std.fs.path.sep_str ++ "lemon.zig");
    cmd.setBuildMode(mode);
    cmd.install();

    const cmd_step = b.step("cmd", "Build Lemon CLI");
    cmd_step.dependOn(&cmd.step);
}
