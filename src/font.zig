//! 名前付きフォント(Python tkinter.font相当)。
//!
//!     const heading = try tk.font.Font.init(root, .{ .family = "Helvetica", .size = 14, .weight = .bold });
//!     defer heading.deinit();
//!     _ = try tk.Label.init(root, .{ .text = "Title", .font = heading.name() });
//!     try heading.config(.{ .size = 18 });   // このフォントを使う全Widgetに反映される
//!
//! Widgetのfontオプションには、フォント名(name())のほか "Helvetica 12 bold" のような記述も渡せる。
const std = @import("std");
const tcl = @import("tcl.zig");
const value = @import("value.zig");
const widget = @import("widget.zig");
const interp_mod = @import("interp.zig");
const Interp = interp_mod.Interp;
const Cmd = interp_mod.Cmd;
const Error = interp_mod.Error;

pub const Weight = enum { normal, bold };
pub const Slant = enum { roman, italic };

pub const Options = struct {
    family: ?[]const u8 = null,
    /// 正ならポイント、負ならピクセル単位の大きさ。
    size: ?i32 = null,
    weight: ?Weight = null,
    slant: ?Slant = null,
    underline: ?bool = null,
    overstrike: ?bool = null,
};

pub const Metric = enum {
    /// ベースラインから上端まで(ピクセル)。
    ascent,
    /// ベースラインから下端まで。
    descent,
    /// 行の高さ。
    linespace,
};

/// Tkが標準で用意している名前付きフォント。
pub const standard = struct {
    pub const default = "TkDefaultFont";
    pub const text = "TkTextFont";
    pub const fixed = "TkFixedFont";
    pub const menu = "TkMenuFont";
    pub const heading = "TkHeadingFont";
    pub const caption = "TkCaptionFont";
    pub const small_caption = "TkSmallCaptionFont";
    pub const icon = "TkIconFont";
    pub const tooltip = "TkTooltipFont";
};

pub const Font = struct {
    interp: *Interp,
    font_name: [:0]const u8,
    /// initで作成したフォントならtrue(deinitで削除する)。namedで参照しただけならfalse。
    owned: bool,

    /// 新しい名前付きフォントを作る。masterは同じインタプリタに属する任意のWidget。
    pub fn init(master: anytype, opts: Options) Error!Font {
        const interp = widget.asWidget(master).interp;
        const font_name = try interp.uniqueName("zt_font");
        var cmd: Cmd = .init(interp);
        defer cmd.deinit();
        try cmd.add("font");
        try cmd.add("create");
        try cmd.add(font_name);
        try cmd.addOptions(font_name, opts);
        _ = try cmd.eval();
        return .{ .interp = interp, .font_name = font_name, .owned = true };
    }

    /// 既存の名前付きフォント(standard.*やfont createで作られたもの)を参照する。
    pub fn named(master: anytype, font_name: [:0]const u8) Font {
        return .{ .interp = widget.asWidget(master).interp, .font_name = font_name, .owned = false };
    }

    /// initで作成したフォントを削除する(使用中のWidgetは既定のフォントに戻る)。namedの場合は何もしない。
    pub fn deinit(self: Font) void {
        if (!self.owned) return;
        _ = self.interp.call(.{ "font", "delete", self.font_name }) catch {};
    }

    /// Widgetのfontオプションに渡す名前。
    pub fn name(self: Font) []const u8 {
        return self.font_name;
    }

    pub fn toTclObj(self: Font, _: *Interp) Error!*tcl.Obj {
        return value.string(self.font_name);
    }

    /// フォントの属性を変更する。このフォントを使う全Widgetに反映される。
    pub fn config(self: Font, opts: Options) Error!void {
        var cmd: Cmd = .init(self.interp);
        defer cmd.deinit();
        try cmd.add("font");
        try cmd.add("configure");
        try cmd.add(self.font_name);
        try cmd.addOptions(self.font_name, opts);
        _ = try cmd.eval();
    }

    /// 実際に使われるファミリ名(要求したものが無い場合は代替のもの)。次のTcl呼び出しまで有効。
    pub fn actualFamily(self: Font) Error![]const u8 {
        return self.interp.call(.{ "font", "actual", self.font_name, "-family" });
    }

    /// textを表示した時の幅(ピクセル)。
    pub fn measure(self: Font, text: []const u8) Error!i32 {
        return self.parseInt(try self.interp.call(.{ "font", "measure", self.font_name, text }));
    }

    pub fn metrics(self: Font, which: Metric) Error!i32 {
        var buf: [16]u8 = undefined;
        const option = std.fmt.bufPrint(&buf, "-{t}", .{which}) catch return error.OutOfMemory;
        return self.parseInt(try self.interp.call(.{ "font", "metrics", self.font_name, option }));
    }

    /// 等幅フォントか。
    pub fn isFixed(self: Font) Error!bool {
        return std.mem.eql(u8, try self.interp.call(.{ "font", "metrics", self.font_name, "-fixed" }), "1");
    }

    fn parseInt(self: Font, s: []const u8) Error!i32 {
        return std.fmt.parseInt(i32, s, 10) catch self.interp.failWith("unexpected font metric");
    }
};

/// 利用できるフォントファミリ名をgpaで複製して返す(tk.freeStringsで解放)。
pub fn families(gpa: std.mem.Allocator, master: anytype) Error![][]u8 {
    return value.dupeStrings(gpa, try widget.asWidget(master).interp.callList(.{ "font", "families" }));
}

/// 定義済みの名前付きフォント名をgpaで複製して返す(tk.freeStringsで解放)。
pub fn names(gpa: std.mem.Allocator, master: anytype) Error![][]u8 {
    return value.dupeStrings(gpa, try widget.asWidget(master).interp.callList(.{ "font", "names" }));
}
