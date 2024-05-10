const std = @import("std");
const Server = @import("server.zig");

pub fn main() !void {
    var allocator = std.heap.raw_c_allocator;

    const app = Server.init(&allocator);
    defer app.deinit();

    const port: u16 = 3000;
    const folder = std.fs.cwd().openDir("public", .{.iterate = true}) catch unreachable;

    //app.static(.{ .folder = folder, .route = "" });
    app.dynamic(.{ .folder = folder, .route = "public" });

    try app.listen(.{
        .port = port
    });
}