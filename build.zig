const std = @import("std");

const Builder = std.build.Builder;

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{});

    var main_tests = b.addTest("src/repository.zig");
    main_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);

    const cli = b.addExecutable("lemon", "cli/main.zig");
    cli.addPackage(.{ .name = "lemon", .path = .{ .path = "src/lemon.zig" } });
    cli.setTarget(target);
    cli.setBuildMode(mode);
    cli.addIncludeDir("libs/zlib");
    cli.install();
}
