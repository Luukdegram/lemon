const std = @import("std");
const Builder = std.build.Builder;

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();

    var main_tests = b.addTest("src/repository.zig");
    main_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);

    const cmd = b.addExecutable("lemon", "cli/main.zig");
    cmd.addPackagePath("lemon", "src/lemon.zig");
    cmd.setBuildMode(mode);
    cmd.install();

    const cmd_step = b.step("cli", "Build Lemon CLI");
    cmd_step.dependOn(&cmd.step);
    cmd_step.dependOn(b.getInstallStep());
}
