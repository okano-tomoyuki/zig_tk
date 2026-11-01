//! 画像(Python tkinter.PhotoImage相当)。
//!
//!     const icon = try tk.PhotoImage.init(root, .{ .data = .{ .bytes = @embedFile("icon.png") } });
//!     defer icon.deinit();
//!     _ = try tk.Button.init(root, .{ .image = icon, .text = "保存", .compound = .left });
//!
//! 対応形式はTk標準のPNG/GIF/PPM/PGM/SVG(nano)。画像はdeinitまで(またはインタプリタ破棄まで)残る。
//! 使用中の画像をdeinitすると、それを表示しているWidgetは空になる。
const std = @import("std");
const tcl = @import("tcl.zig");
const value = @import("value.zig");
const widget = @import("widget.zig");
const Color = @import("dialogs/colorchooser.zig").Color;
const interp_mod = @import("interp.zig");
const Interp = interp_mod.Interp;
const Cmd = interp_mod.Cmd;
const Error = interp_mod.Error;

pub const PhotoImage = struct {
    interp: *Interp,
    image_name: [:0]const u8,

    /// メモリ上の画像データ(PNG/GIFファイルの中身等)。@embedFileの結果をそのまま渡せる。
    pub const Data = struct {
        bytes: []const u8,

        pub fn toTclObj(self: Data, _: *Interp) Error!*tcl.Obj {
            return tcl.Tcl_NewByteArrayObj(self.bytes.ptr, @intCast(self.bytes.len));
        }
    };

    /// 画素の範囲(x2, y2は含まない)。
    pub const Region = struct {
        x1: i32,
        y1: i32,
        x2: i32,
        y2: i32,

        pub fn toTclObj(self: Region, interp: *Interp) Error!*tcl.Obj {
            return value.toObj(interp, .{ self.x1, self.y1, self.x2, self.y2 });
        }
    };

    pub const Options = struct {
        /// 読み込むファイルのパス。
        file: ?[]const u8 = null,
        /// 読み込むデータ(fileと同時には指定しない)。
        data: ?Data = null,
        /// 画像形式("png" "gif" 等)。省略時は自動判別。
        format: ?[]const u8 = null,
        /// 幅・高さを固定する(省略時は画像に合わせる)。
        width: ?i32 = null,
        height: ?i32 = null,
        gamma: ?f64 = null,
    };

    /// masterは同じインタプリタに属する任意のWidget。
    pub fn init(master: anytype, opts: Options) Error!PhotoImage {
        const interp = widget.asWidget(master).interp;
        const image_name = try interp.uniqueName("zt_img");
        var cmd: Cmd = .init(interp);
        defer cmd.deinit();
        try cmd.add("image");
        try cmd.add("create");
        try cmd.add("photo");
        try cmd.add(image_name);
        try cmd.addOptions(image_name, opts);
        _ = try cmd.eval();
        return .{ .interp = interp, .image_name = image_name };
    }

    /// 画像を削除する。
    pub fn deinit(self: PhotoImage) void {
        _ = self.interp.call(.{ "image", "delete", self.image_name }) catch {};
    }

    /// Tcl側の画像名。
    pub fn name(self: PhotoImage) []const u8 {
        return self.image_name;
    }

    pub fn toTclObj(self: PhotoImage, _: *Interp) Error!*tcl.Obj {
        return value.string(self.image_name);
    }

    /// 画像を読み直す・大きさを変える等(Optionsと同じ指定)。
    pub fn config(self: PhotoImage, opts: Options) Error!void {
        var cmd: Cmd = .init(self.interp);
        defer cmd.deinit();
        try cmd.add(self.image_name);
        try cmd.add("configure");
        try cmd.addOptions(self.image_name, opts);
        _ = try cmd.eval();
    }

    pub fn width(self: PhotoImage) Error!i32 {
        return self.parseInt(try self.interp.call(.{ "image", "width", self.image_name }));
    }

    pub fn height(self: PhotoImage) Error!i32 {
        return self.parseInt(try self.interp.call(.{ "image", "height", self.image_name }));
    }

    /// 全画素を透明にする。
    pub fn blank(self: PhotoImage) Error!void {
        _ = try self.interp.call(.{ self.image_name, "blank" });
    }

    /// regionの画素をcolorで塗る。
    pub fn put(self: PhotoImage, color: Color, region: Region) Error!void {
        // -to は1つのリストではなく4つの整数として渡す
        _ = try self.interp.call(.{ self.image_name, "put", color, "-to", region.x1, region.y1, region.x2, region.y2 });
    }

    /// (x, y)の画素の色。
    pub fn get(self: PhotoImage, x: i32, y: i32) Error!Color {
        const objs = try self.interp.callList(.{ self.image_name, "get", x, y });
        if (objs.len < 3) return self.interp.failWith("unexpected pixel value");
        var rgb: [3]u8 = undefined;
        for (objs[0..3], &rgb) |obj, *c| {
            var v: tcl.WideInt = 0;
            if (tcl.Tcl_GetWideIntFromObj(self.interp.raw, obj, &v) != tcl.OK) return self.interp.fail();
            c.* = std.math.cast(u8, v) orelse return self.interp.failWith("unexpected pixel value");
        }
        return .{ .r = rgb[0], .g = rgb[1], .b = rgb[2] };
    }

    pub fn transparencyGet(self: PhotoImage, x: i32, y: i32) Error!bool {
        return std.mem.eql(u8, try self.interp.call(.{ self.image_name, "transparency", "get", x, y }), "1");
    }

    pub fn transparencySet(self: PhotoImage, x: i32, y: i32, transparent: bool) Error!void {
        _ = try self.interp.call(.{ self.image_name, "transparency", "set", x, y, transparent });
    }

    /// 縦横をx, y倍に拡大した新しい画像を作る(deinitが必要)。
    pub fn zoom(self: PhotoImage, x: i32, y: i32) Error!PhotoImage {
        return self.copyInto("-zoom", x, y);
    }

    /// 縦横の画素をx, yおきに間引いた新しい画像を作る(deinitが必要)。
    pub fn subsample(self: PhotoImage, x: i32, y: i32) Error!PhotoImage {
        return self.copyInto("-subsample", x, y);
    }

    fn copyInto(self: PhotoImage, mode: []const u8, x: i32, y: i32) Error!PhotoImage {
        const dst = try PhotoImage.init(widget.Widget{ .interp = self.interp, .path = "." }, .{});
        errdefer dst.deinit();
        _ = try self.interp.call(.{ dst.image_name, "copy", self.image_name, mode, x, y });
        return dst;
    }

    /// ファイルへ保存する(formatは "png" "gif" "ppm" 等)。
    pub fn write(self: PhotoImage, path: []const u8, format: []const u8) Error!void {
        _ = try self.interp.call(.{ self.image_name, "write", path, "-format", format });
    }

    fn parseInt(self: PhotoImage, s: []const u8) Error!i32 {
        return std.fmt.parseInt(i32, s, 10) catch self.interp.failWith("unexpected image size");
    }
};
