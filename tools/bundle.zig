//! 実行ファイルの末尾にzipアーカイブ(deflate圧縮)を連結するビルド用ツール。
//! Tcl 9のzipfsは実行ファイル末尾のzipを //zipfs:/app に自動マウントし、
//! そこから tcl_library/init.tcl と tk_library/tk.tcl を探す。
//!
//! 使い方: bundle <入力exe> <出力exe> <アーカイブ内prefix>=<ディレクトリ> ... [--exclude=<アーカイブ内パス>]...
const std = @import("std");
const Io = std.Io;

const Entry = struct {
    name: []const u8, // アーカイブ内パス('/'区切り、ディレクトリは末尾'/')
    /// 格納するバイト列(method == .deflate なら圧縮後)。
    data: []const u8,
    uncompressed_len: usize,
    crc: u32,
    method: Method = .stored,
    offset: u32 = 0,

    const Method = enum(u16) { stored = 0, deflate = 8 };

    fn directory(name: []const u8) Entry {
        return .{ .name = name, .data = "", .uncompressed_len = 0, .crc = 0 };
    }
};

/// 各ファイルの圧縮に使い回す作業領域。
const Deflater = struct {
    out: Io.Writer.Allocating,
    window: []u8,
    compress: *std.compress.flate.Compress,

    fn init(gpa: std.mem.Allocator) !Deflater {
        return .{
            .out = try .initCapacity(gpa, 64 * 1024),
            .window = try gpa.alloc(u8, std.compress.flate.max_window_len),
            .compress = try gpa.create(std.compress.flate.Compress),
        };
    }

    /// dataを圧縮したentryを返す。圧縮しても小さくならなければ無圧縮のまま格納する。
    fn entry(self: *Deflater, arena: std.mem.Allocator, name: []const u8, data: []const u8) !Entry {
        const crc = std.hash.Crc32.hash(data);
        self.out.clearRetainingCapacity();
        self.compress.* = try .init(&self.out.writer, self.window, .raw, .default);
        try self.compress.writer.writeAll(data);
        try self.compress.finish();
        const packed_data = self.out.written();
        if (packed_data.len >= data.len) return .{ .name = name, .data = data, .uncompressed_len = data.len, .crc = crc };
        return .{ .name = name, .data = try arena.dupe(u8, packed_data), .uncompressed_len = data.len, .crc = crc, .method = .deflate };
    }
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    if (args.len < 4) {
        std.debug.print("usage: bundle <in.exe> <out.exe> <prefix>=<dir>... [--exclude=<path>]...\n", .{});
        return error.InvalidArguments;
    }

    var excludes: std.ArrayList([]const u8) = .empty;
    for (args[3..]) |arg| {
        if (std.mem.startsWith(u8, arg, "--exclude=")) try excludes.append(arena, arg["--exclude=".len..]);
    }

    var entries: std.ArrayList(Entry) = .empty;
    var deflater: Deflater = try .init(arena);
    for (args[3..]) |arg| {
        if (std.mem.startsWith(u8, arg, "--")) continue;
        const eq = std.mem.indexOfScalar(u8, arg, '=') orelse return error.InvalidArguments;
        try collect(io, arena, &deflater, &entries, excludes.items, arg[0..eq], arg[eq + 1 ..]);
    }
    std.mem.sort(Entry, entries.items, {}, struct {
        fn lessThan(_: void, a: Entry, b: Entry) bool {
            return std.mem.lessThan(u8, a.name, b.name);
        }
    }.lessThan);

    const exe = try Io.Dir.cwd().readFileAlloc(io, args[1], arena, .unlimited);
    // 実行ファイル/共有ライブラリの実行権限(Unix)を引き継ぐ
    const in_stat = try Io.Dir.cwd().statFile(io, args[1], .{});
    const out = try Io.Dir.cwd().createFile(io, args[2], .{ .permissions = in_stat.permissions });
    defer out.close(io);
    var buf: [64 * 1024]u8 = undefined;
    var fw = out.writer(io, &buf);
    const w = &fw.interface;

    try w.writeAll(exe);
    try writeZip(w, entries.items);
    try w.flush();
}

fn collect(
    io: Io,
    arena: std.mem.Allocator,
    deflater: *Deflater,
    entries: *std.ArrayList(Entry),
    excludes: []const []const u8,
    prefix: []const u8,
    dir_path: []const u8,
) !void {
    var dir = try Io.Dir.cwd().openDir(io, dir_path, .{ .iterate = true });
    defer dir.close(io);
    try entries.append(arena, .directory(try std.fmt.allocPrint(arena, "{s}/", .{prefix})));

    var walker = try dir.walk(arena);
    defer walker.deinit();
    while (try walker.next(io)) |e| {
        const rel = try arena.dupe(u8, e.path);
        std.mem.replaceScalar(u8, rel, '\\', '/');
        const name = try std.fmt.allocPrint(arena, "{s}/{s}{s}", .{ prefix, rel, if (e.kind == .directory) "/" else "" });
        if (isExcluded(excludes, name)) {
            if (e.kind == .directory) walker.leave(io);
            continue;
        }
        switch (e.kind) {
            .directory => try entries.append(arena, .directory(name)),
            .file => {
                const data = try e.dir.readFileAlloc(io, e.basename, arena, .unlimited);
                try entries.append(arena, try deflater.entry(arena, name, data));
            },
            else => {},
        }
    }
}

fn isExcluded(excludes: []const []const u8, name: []const u8) bool {
    for (excludes) |x| {
        if (std.mem.startsWith(u8, name, x) and (name.len == x.len or name[x.len] == '/')) return true;
    }
    return false;
}

/// zipを書き出す。オフセットはzip先頭からの相対値
/// (前置された実行ファイル分はzipfsが中央ディレクトリの位置から逆算する)。
fn writeZip(w: *Io.Writer, entries: []Entry) !void {
    const utf8_flag: u16 = 0x0800;
    const dos_time: u16 = 0;
    const dos_date: u16 = (1 << 5) | 1; // 1980-01-01

    var pos: u32 = 0;
    for (entries) |*e| {
        e.offset = pos;
        try w.writeInt(u32, 0x04034b50, .little);
        try w.writeInt(u16, 20, .little);
        try w.writeInt(u16, utf8_flag, .little);
        try w.writeInt(u16, @intFromEnum(e.method), .little);
        try w.writeInt(u16, dos_time, .little);
        try w.writeInt(u16, dos_date, .little);
        try w.writeInt(u32, e.crc, .little);
        try w.writeInt(u32, @intCast(e.data.len), .little);
        try w.writeInt(u32, @intCast(e.uncompressed_len), .little);
        try w.writeInt(u16, @intCast(e.name.len), .little);
        try w.writeInt(u16, 0, .little);
        try w.writeAll(e.name);
        try w.writeAll(e.data);
        pos += @intCast(30 + e.name.len + e.data.len);
    }

    const cd_start = pos;
    for (entries) |e| {
        try w.writeInt(u32, 0x02014b50, .little);
        try w.writeInt(u16, 20, .little);
        try w.writeInt(u16, 20, .little);
        try w.writeInt(u16, utf8_flag, .little);
        try w.writeInt(u16, @intFromEnum(e.method), .little);
        try w.writeInt(u16, dos_time, .little);
        try w.writeInt(u16, dos_date, .little);
        try w.writeInt(u32, e.crc, .little);
        try w.writeInt(u32, @intCast(e.data.len), .little);
        try w.writeInt(u32, @intCast(e.uncompressed_len), .little);
        try w.writeInt(u16, @intCast(e.name.len), .little);
        try w.writeInt(u16, 0, .little); // extra
        try w.writeInt(u16, 0, .little); // comment
        try w.writeInt(u16, 0, .little); // disk
        try w.writeInt(u16, 0, .little); // internal attr
        try w.writeInt(u32, 0, .little); // external attr
        try w.writeInt(u32, e.offset, .little);
        try w.writeAll(e.name);
        pos += @intCast(46 + e.name.len);
    }

    try w.writeInt(u32, 0x06054b50, .little);
    try w.writeInt(u16, 0, .little);
    try w.writeInt(u16, 0, .little);
    try w.writeInt(u16, @intCast(entries.len), .little);
    try w.writeInt(u16, @intCast(entries.len), .little);
    try w.writeInt(u32, pos - cd_start, .little);
    try w.writeInt(u32, cd_start, .little);
    try w.writeInt(u16, 0, .little);
}
