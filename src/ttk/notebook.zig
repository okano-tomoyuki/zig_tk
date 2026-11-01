const std = @import("std");
const types = @import("../types.zig");
const widget = @import("../widget.zig");
const PhotoImage = @import("../image.zig").PhotoImage;
const common = @import("common.zig");
const interp_mod = @import("../interp.zig");
const Cmd = interp_mod.Cmd;
const Error = interp_mod.Error;
const Widget = widget.Widget;

/// ttk::notebook(Python tkinter.ttk.Notebook相当)。
/// タブが切り替わると仮想イベント "<<NotebookTabChanged>>" が発生する(bindで受け取る)。
///
/// タブの指定(tab)には次のいずれかを渡せる:
///   - タブとして追加した子Widget
///   - タブの番号(0始まりの整数)
///   - .current(選択中のタブ) / .end(insertの末尾指定)
pub const Notebook = struct {
    w: Widget,

    pub const Options = struct {
        width: ?i32 = null,
        height: ?i32 = null,
        padding: ?types.Padding = null,
        style: ?[]const u8 = null,
        cursor: ?[]const u8 = null,
        takefocus: ?bool = null,
    };

    pub const TabState = enum {
        normal,
        /// 表示されるが選択できない。
        disabled,
        /// 表示されない(hideと同じ)。
        hidden,
    };

    pub const TabOptions = struct {
        text: ?[]const u8 = null,
        state: ?TabState = null,
        image: ?PhotoImage = null,
        compound: ?types.Compound = null,
        /// Alt+文字でタブを選ぶための下線位置(enableTraversal後に有効)。
        underline: ?i32 = null,
        /// タブ内での子Widgetの配置。
        sticky: ?types.Sticky = null,
        padding: ?types.Padding = null,
    };

    const M = widget.Methods(Notebook, Options);
    pub const toTclObj = M.toTclObj;
    pub const config = M.config;
    pub const cget = M.cget;
    pub const pack = M.pack;
    pub const grid = M.grid;
    pub const place = M.place;
    pub const bind = M.bind;
    pub const unbind = M.unbind;
    pub const destroy = M.destroy;
    pub const packForget = M.packForget;
    pub const gridForget = M.gridForget;
    pub const placeForget = M.placeForget;
    pub const gridRowconfigure = M.gridRowconfigure;
    pub const gridColumnconfigure = M.gridColumnconfigure;
    pub const gridPropagate = M.gridPropagate;
    pub const packPropagate = M.packPropagate;
    pub const focusSet = M.focusSet;
    pub const focusForce = M.focusForce;
    pub const winfo = M.winfo;
    pub const winfoExists = M.winfoExists;
    pub const winfoIsmapped = M.winfoIsmapped;
    pub const winfoClass = M.winfoClass;
    pub const eventGenerate = M.eventGenerate;
    pub const waitWindow = M.waitWindow;

    const S = common.Methods(Notebook);
    pub const setState = S.setState;
    pub const instate = S.instate;

    pub fn init(parent: anytype, opts: Options) Error!Notebook {
        return .{ .w = try .create(widget.asWidget(parent), "ttk::notebook", opts) };
    }

    /// childを末尾のタブとして追加する(childはこのNotebookの子として生成したWidget)。
    pub fn add(self: Notebook, child: anytype, opts: TabOptions) Error!void {
        try self.tabCommand("add", .{widget.asWidget(child)}, opts);
    }

    /// childをpos(タブの指定、.endで末尾)の位置に挿入する。追加済みのタブなら移動する。
    pub fn insert(self: Notebook, pos: anytype, child: anytype, opts: TabOptions) Error!void {
        try self.tabCommand("insert", .{ tabRef(pos), widget.asWidget(child) }, opts);
    }

    /// タブの書式を変更する。
    pub fn tab(self: Notebook, which: anytype, opts: TabOptions) Error!void {
        try self.tabCommand("tab", .{tabRef(which)}, opts);
    }

    /// タブのオプション値(例: tabCget(page, "text"))。次のTcl呼び出しまで有効。
    pub fn tabCget(self: Notebook, which: anytype, option: []const u8) Error![]const u8 {
        var buf: [64]u8 = undefined;
        const name = std.fmt.bufPrint(&buf, "-{s}", .{option}) catch return error.OutOfMemory;
        return self.w.interp.call(.{ self.w.path, "tab", tabRef(which), name });
    }

    /// タブを取り除く(子Widget自体は破棄されない)。
    pub fn forget(self: Notebook, which: anytype) Error!void {
        _ = try self.w.interp.call(.{ self.w.path, "forget", tabRef(which) });
    }

    /// タブを隠す(addで再表示できる)。
    pub fn hide(self: Notebook, which: anytype) Error!void {
        _ = try self.w.interp.call(.{ self.w.path, "hide", tabRef(which) });
    }

    pub fn select(self: Notebook, which: anytype) Error!void {
        _ = try self.w.interp.call(.{ self.w.path, "select", tabRef(which) });
    }

    /// 選択中のタブの番号。タブが無ければnull。
    pub fn selectedIndex(self: Notebook) Error!?usize {
        if (try self.count() == 0) return null;
        return try self.index(.current);
    }

    /// タブの番号。
    pub fn index(self: Notebook, which: anytype) Error!usize {
        const result = try self.w.interp.call(.{ self.w.path, "index", tabRef(which) });
        return std.fmt.parseInt(usize, result, 10) catch self.w.interp.failWith("unexpected notebook index");
    }

    /// タブの数。
    pub fn count(self: Notebook) Error!usize {
        return self.index(.end);
    }

    /// Ctrl+Tab等のキーボードによるタブ切り替えを有効にする。
    pub fn enableTraversal(self: Notebook) Error!void {
        _ = try self.w.interp.call(.{ "ttk::notebook::enableTraversal", self.w.path });
    }

    fn tabCommand(self: Notebook, sub: []const u8, args: anytype, opts: TabOptions) Error!void {
        var cmd: Cmd = .init(self.w.interp);
        defer cmd.deinit();
        try cmd.add(self.w.path);
        try cmd.add(sub);
        inline for (args) |a| try cmd.add(a);
        try cmd.addOptions(self.w.path, opts);
        _ = try cmd.eval();
    }

    /// タブの指定をTclへ渡す値にする(Widget / 番号 / .current / .end)。
    fn tabRef(which: anytype) TabRef(@TypeOf(which)) {
        const T = @TypeOf(which);
        switch (@typeInfo(T)) {
            .int, .comptime_int => return which,
            .enum_literal => {
                if (which != .current and which != .end)
                    @compileError("zig_tk: notebook tab literal must be .current or .end, got ." ++ @tagName(which));
                return which;
            },
            else => return widget.asWidget(which),
        }
    }

    fn TabRef(comptime T: type) type {
        return switch (@typeInfo(T)) {
            .int, .comptime_int, .enum_literal => T,
            else => Widget,
        };
    }
};
