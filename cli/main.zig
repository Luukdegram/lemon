const std = @import("std");
const lemon = @import("lemon");
const parser = @import("parser.zig");

usingnamespace @import("flag.zig");

const log = std.log.default;

pub fn main() !void {
    var gpa_alloc = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_alloc.deinit();
    var arena = std.heap.ArenaAllocator.init(&gpa_alloc.allocator);
    defer arena.deinit();
    const gpa = &arena.allocator;

    const cmds_imp = @import("cmds.zig");

    const cmds = .{
        .{ "init", cmds_imp.init },
        .{ "cat-file", cmds_imp.cat },
        .{ "hash-object", cmds_imp.hash },
    };

    const result = parser.parse(gpa) catch |err| return log.err("Error occured parsing arguments: {}\n", .{err});
    defer result.deinit();

    inline for (cmds) |cmd| {
        if (std.mem.eql(u8, cmd[0], result.args[0])) {
            try cmd[1].handle(gpa, result.args, std.io.getStdOut().writer());
            return;
        }
    }

    log.err("Unknown command: {}\n", .{result.args[0]});
}
