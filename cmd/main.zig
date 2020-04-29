const std = @import("std");
const parser = @import("parser.zig");

pub fn main() !void {
    var allocator = std.heap.page_allocator;

    if (parser.Parse(allocator)) |result| {
        std.debug.warn("Empty: {}\n", .{result.isEmpty()});
        for (result.args) |arg| {
            std.debug.warn("arg: {}\n", .{arg});
        }
        result.deinit();
    } else |err| {
        std.debug.warn("Error occured: {}\n", .{err});
    }
}
