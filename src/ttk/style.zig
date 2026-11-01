//! ttkのスタイルとテーマ(Python tkinter.ttk.Style相当)。
//!
//!     const style = tk.ttk.Style.init(root);
//!     try style.themeUse("clam");
//!     try style.configure("Accent.TButton", .{ .foreground = "white", .background = "#3366cc", .padding = .xy(12, 4) });
//!     try style.map("Accent.TButton", "background", &.{
//!         .{ .state = .{ .pressed = true }, .value = "#224488" },
//!         .{ .state = .{ .active = true }, .value = "#4477dd" },
//!     });
//!     _ = try tk.ttk.Button.init(root, .{ .text = "OK", .style = "Accent.TButton" });
//!
//! スタイル名は "<任意の名前>.<元のスタイル>"(例: "Accent.TButton")とすると元のスタイルを継承する。
const std = @import("std");
const tcl = @import("../tcl.zig");
const types = @import("../types.zig");
const value = @import("../value.zig");
const widget = @import("../widget.zig");
const common = @import("common.zig");
const interp_mod = @import("../interp.zig");
const Interp = interp_mod.Interp;
const Cmd = interp_mod.Cmd;
const Error = interp_mod.Error;

/// configureで設定できる代表的なスタイルオプション。どれが効くかはテーマとWidgetの要素による。
/// ここに無いオプションはconfigureRawで指定する。
pub const StyleOptions = struct {
    foreground: ?[]const u8 = null,
    background: ?[]const u8 = null,
    font: ?[]const u8 = null,
    padding: ?types.Padding = null,
    relief: ?types.Relief = null,
    borderwidth: ?i32 = null,
    anchor: ?types.Anchor = null,
    justify: ?types.Justify = null,
    /// Entry/Combobox等の入力欄の背景色。
    fieldbackground: ?[]const u8 = null,
    selectbackground: ?[]const u8 = null,
    selectforeground: ?[]const u8 = null,
    /// 入力欄のカーソルの色。
    insertcolor: ?[]const u8 = null,
    troughcolor: ?[]const u8 = null,
    arrowcolor: ?[]const u8 = null,
    bordercolor: ?[]const u8 = null,
    lightcolor: ?[]const u8 = null,
    darkcolor: ?[]const u8 = null,
    focuscolor: ?[]const u8 = null,
    indicatorcolor: ?[]const u8 = null,
    /// Treeviewの行の高さ等。
    rowheight: ?i32 = null,
};

/// mapの1項目: stateのときoptionをvalueにする。
pub const StateValue = struct {
    state: common.StateSpec,
    value: []const u8,
};

pub const Style = struct {
    interp: *Interp,

    /// masterは同じインタプリタに属する任意のWidget。
    pub fn init(master: anytype) Style {
        return .{ .interp = widget.asWidget(master).interp };
    }

    /// 利用できるテーマ名をgpaで複製して返す(tk.freeStringsで解放)。
    pub fn themeNames(self: Style, gpa: std.mem.Allocator) Error![][]u8 {
        return value.dupeStrings(gpa, try self.interp.callList(.{ "ttk::style", "theme", "names" }));
    }

    /// テーマを切り替える(全ttk Widgetの見た目が変わる)。
    pub fn themeUse(self: Style, theme: []const u8) Error!void {
        _ = try self.interp.call(.{ "ttk::style", "theme", "use", theme });
    }

    /// 現在のテーマ名。次のTcl呼び出しまで有効。
    pub fn currentTheme(self: Style) Error![]const u8 {
        return self.interp.call(.{ "ttk::style", "theme", "use" });
    }

    pub fn configure(self: Style, style: []const u8, opts: StyleOptions) Error!void {
        var cmd: Cmd = .init(self.interp);
        defer cmd.deinit();
        try cmd.add("ttk::style");
        try cmd.add("configure");
        try cmd.add(style);
        try cmd.addOptions(style, opts);
        _ = try cmd.eval();
    }

    /// StyleOptionsに無いオプションを指定する。例: configureRaw("TCheckbutton", .{ "-indicatormargin", 4 })
    pub fn configureRaw(self: Style, style: []const u8, words: anytype) Error!void {
        var cmd: Cmd = .init(self.interp);
        defer cmd.deinit();
        try cmd.add("ttk::style");
        try cmd.add("configure");
        try cmd.add(style);
        inline for (words) |word| try cmd.add(word);
        _ = try cmd.eval();
    }

    /// 状態に応じたoptionの値を設定する(先に並べたものが優先される)。
    pub fn map(self: Style, style: []const u8, option: []const u8, entries: []const StateValue) Error!void {
        var buf: [64]u8 = undefined;
        const name = std.fmt.bufPrint(&buf, "-{s}", .{option}) catch return error.OutOfMemory;
        var cmd: Cmd = .init(self.interp);
        defer cmd.deinit();
        try cmd.add("ttk::style");
        try cmd.add("map");
        try cmd.add(style);
        try cmd.add(name);
        const list = tcl.Tcl_NewListObj(0, null);
        try cmd.addObj(list);
        for (entries) |e| {
            _ = tcl.Tcl_ListObjAppendElement(null, list, try e.state.toTclObj(self.interp));
            _ = tcl.Tcl_ListObjAppendElement(null, list, value.string(e.value));
        }
        _ = try cmd.eval();
    }

    /// styleのoptionの値(stateを指定するとその状態での値)。次のTcl呼び出しまで有効。
    pub fn lookup(self: Style, style: []const u8, option: []const u8, state: ?common.StateSpec) Error![]const u8 {
        var buf: [64]u8 = undefined;
        const name = std.fmt.bufPrint(&buf, "-{s}", .{option}) catch return error.OutOfMemory;
        if (state) |s| return self.interp.call(.{ "ttk::style", "lookup", style, name, s });
        return self.interp.call(.{ "ttk::style", "lookup", style, name });
    }
};
