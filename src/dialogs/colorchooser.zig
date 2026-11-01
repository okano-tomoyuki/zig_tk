//! 色選択ダイアログ(Python tkinter.colorchooser相当、tk_chooseColorのラッパー)。
const std = @import("std");
const tcl = @import("../tcl.zig");
const value = @import("../value.zig");
const widget = @import("../widget.zig");
const interp_mod = @import("../interp.zig");
const Interp = interp_mod.Interp;
const Cmd = interp_mod.Cmd;
const Error = interp_mod.Error;

/// RGB色。Tkの色指定("#rrggbb")としてオプションに渡せる。
pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,

    /// "#rrggbb" 形式の文字列をbufに書いて返す。
    pub fn hex(self: Color, buf: *[7]u8) []const u8 {
        return std.fmt.bufPrint(buf, "#{x:0>2}{x:0>2}{x:0>2}", .{ self.r, self.g, self.b }) catch unreachable;
    }

    /// "#rrggbb" を解釈する。
    pub fn parse(s: []const u8) ?Color {
        if (s.len != 7 or s[0] != '#') return null;
        const v = std.fmt.parseInt(u24, s[1..], 16) catch return null;
        return .{ .r = @truncate(v >> 16), .g = @truncate(v >> 8), .b = @truncate(v) };
    }

    pub fn toTclObj(self: Color, _: *Interp) Error!*tcl.Obj {
        var buf: [7]u8 = undefined;
        return value.string(self.hex(&buf));
    }
};

pub const Options = struct {
    initialcolor: ?Color = null,
    title: ?[]const u8 = null,
};

/// 色を選ばせる。キャンセル時はnull。
pub fn askcolor(master: anytype, opts: Options) Error!?Color {
    const parent = widget.asWidget(master);
    var cmd: Cmd = .init(parent.interp);
    defer cmd.deinit();
    try cmd.add("tk_chooseColor");
    try cmd.addOptions(parent.path, opts);
    try cmd.addOptions(parent.path, .{ .parent = parent });
    const result = try cmd.eval();
    if (result.len == 0) return null;
    return Color.parse(result) orelse error.TclError;
}
