const std = @import("std");

const Locker = @import("locker.zig").Locker;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var app = try Locker.init(gpa.allocator());
    defer app.deinit();

    app.run();
}
