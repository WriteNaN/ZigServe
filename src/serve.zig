allocator: *std.mem.Allocator,
//map: *std.StringHashMap([]const u8),

const std = @import("std");
const Thread = std.Thread;
const Http = std.http;

const Server = @This();

const ServeOptions = struct { folder: std.fs.Dir, route: []const u8 };

var map: std.StringHashMap([]const u8) = undefined;
var isDynamicDirRegistered: bool = false;
var dynamic_map: std.StringHashMap(std.fs.Dir) = undefined;

/// Initialize the server.
pub fn init(allocator: *std.mem.Allocator) Server {
    map = std.StringHashMap([]const u8).init(allocator.*);
    //dynamic_map = std.StringHashMap(std.fs.Dir).init(allocator.*);
    return Server{ .allocator = allocator };
}

/// #### Recursively fetches files in a directory and serves it.
/// ##### note that you would have to restart the app to register new files in the hashmap.
/// otherwise you might probably want to use `<app>.dynamic`.
/// ```zig
/// <app>.static(.{ folder = "public", route: "" });
/// ```
/// *note that a file might be overridden if the same path is explicitly used on the server API (GET/POST/PUT/DEL)*
pub fn static(self: Server, opts: ServeOptions) void {
    var iterable = opts.folder.iterate();

    const realPath = opts.folder.realpathAlloc(self.allocator.*, ".") catch unreachable;
    defer self.allocator.*.free(realPath);
    //const basename = (@constCast(&std.mem.splitBackwards(u8, realPath, "/"))).first();

    while (iterable.next() catch unreachable) |it| {
        if (it.kind == .file) {
            const realFilePath = std.fmt.allocPrint(self.allocator.*, "{s}/{s}", .{ realPath, it.name }) catch @panic("failed to format realpath of file.");
            const webLinkPath = std.fmt.allocPrint(self.allocator.*, "{s}/{s}", .{ opts.route, it.name }) catch @panic("failed to format webpath of file.");

            // I think static served directories are most safe from a directory traversal attack
            // since we wont serve anything that's not allowed to be exposed to client
            // next I'm gonna write dynamic serve function. hope that would be foolproof as well.
            // but please let me know if it is not.

            if (webLinkPath[0] != '/') {
                const fmt = std.fmt.allocPrint(self.allocator.*, "/{s}", .{webLinkPath}) catch @panic("failed to format \"/\"!");
                _ = &map.put(fmt, realFilePath);
            } else {
                _ = &map.put(webLinkPath, realFilePath);
            }
        } else if (it.kind == .directory) {
            if (std.mem.eql(u8, opts.route, "")) {
                const webRoot = std.fmt.allocPrint(self.allocator.*, "{s}", .{it.name}) catch @panic("failed to format child root.");
                const childDir = opts.folder.openDir(it.name, .{ .iterate = true }) catch unreachable;
                static(self, .{ .folder = childDir, .route = webRoot });
            } else {
                const webRoot = std.fmt.allocPrint(self.allocator.*, "{s}/{s}", .{ opts.route, it.name }) catch @panic("failed to format child root.");
                const childDir = opts.folder.openDir(it.name, .{ .iterate = true }) catch unreachable;
                static(self, .{ .folder = childDir, .route = webRoot });
            }
        }
    }
}

const ListenOpts = struct { port: u16, host: ?[]const u8 = null };

/// Starts the server on the specified port.
pub fn listen(self: Server, opts: ListenOpts) !void {
    const addr = try std.net.Address.parseIp(opts.host orelse "127.0.0.1", opts.port);
    var http = try addr.listen(.{ .reuse_address = true });
    defer http.deinit();

    var recv_buf: [8192]u8 = undefined;

    serve: while (true) {
        const conn = try http.accept();
        defer conn.stream.close();

        var serv = Http.Server.init(conn, &recv_buf);

        while (serv.state == .ready) {
            var request = serv.receiveHead() catch |err| {
                std.debug.print("Error: {s}\n", .{@errorName(err)});
                continue :serve;
            };

            const req = &request;
            if (map.contains(req.head.target)) {
                const file = try std.fs.openFileAbsolute(map.get(req.head.target).?, .{ .mode = .read_only });
                const file_size = (try file.stat()).size;
                const content = try file.readToEndAlloc(self.allocator.*, file_size);
                defer {
                    file.close();
                    self.allocator.*.free(content);
                }
                try req.respond(content, .{ .status = .ok, .transfer_encoding = .chunked });
            } else {
                handle(.not_found, req);
            }
        }
    }
}

fn handle(status: Http.Status, req: *Http.Server.Request) !void {
    try req.respond("unavailable", .{ .status = status });
}

pub fn deinit(self: Server) void {
    _ = self;
    //dynamic_map.deinit();
    map.deinit();
}
