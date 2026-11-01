const std = @import("std");
const types = @import("../types.zig");
const widget = @import("../widget.zig");
const common = @import("common.zig");
const interp_mod = @import("../interp.zig");
const Cmd = interp_mod.Cmd;
const Error = interp_mod.Error;
const Widget = widget.Widget;

/// ttk::panedwindow(Python tkinter.ttk.PanedWindow相当)。
pub const Panedwindow = struct {
    w: Widget,

    /// 生成後にconfigで変更できるオプション。
    pub const Options = struct {
        width: ?i32 = null,
        height: ?i32 = null,
        style: ?[]const u8 = null,
        cursor: ?[]const u8 = null,
        takefocus: ?bool = null,
    };

    /// initが受け付けるオプション(Options + 生成時のみ指定できるもの)。
    pub const CreateOptions = struct {
        /// ペインを並べる向き(既定 vertical)。生成時のみ。
        orient: ?types.Orient = null,
        /// スタイルやbindで使うクラス名。生成時のみ。
        class: ?[]const u8 = null,

        width: ?i32 = null,
        height: ?i32 = null,
        style: ?[]const u8 = null,
        cursor: ?[]const u8 = null,
        takefocus: ?bool = null,
    };

    /// add/insertで各ペインに指定するオプション。
    pub const PaneOptions = struct {
        /// ウィンドウの伸縮時にこのペインへ配分する比率。
        weight: ?i32 = null,
    };

    const M = widget.MethodsCreate(Panedwindow, CreateOptions, Options);
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

    const T = common.Methods(Panedwindow);
    pub const setState = T.setState;
    pub const instate = T.instate;

    pub fn init(parent: anytype, opts: CreateOptions) Error!Panedwindow {
        return .{ .w = try .create(widget.asWidget(parent), "ttk::panedwindow", opts) };
    }

    /// childを末尾のペインとして追加する。childはこのPanedwindowの子として生成したWidget。
    pub fn add(self: Panedwindow, child: anytype, opts: PaneOptions) Error!void {
        var cmd: Cmd = .init(self.w.interp);
        defer cmd.deinit();
        try cmd.add(self.w.path);
        try cmd.add("add");
        try cmd.add(widget.asWidget(child));
        try cmd.addOptions(self.w.path, opts);
        _ = try cmd.eval();
    }

    /// childをindex番目のペインとして挿入する。
    pub fn insert(self: Panedwindow, index: i32, child: anytype, opts: PaneOptions) Error!void {
        var cmd: Cmd = .init(self.w.interp);
        defer cmd.deinit();
        try cmd.add(self.w.path);
        try cmd.add("insert");
        try cmd.add(index);
        try cmd.add(widget.asWidget(child));
        try cmd.addOptions(self.w.path, opts);
        _ = try cmd.eval();
    }

    /// childをペインから外す(Widget自体は破棄されない)。
    pub fn forget(self: Panedwindow, child: anytype) Error!void {
        _ = try self.w.interp.call(.{ self.w.path, "forget", widget.asWidget(child) });
    }

    /// index番目の仕切りの位置(ピクセル)。
    pub fn sashpos(self: Panedwindow, index: i32) Error!i32 {
        const result = try self.w.interp.call(.{ self.w.path, "sashpos", index });
        return std.fmt.parseInt(i32, result, 10) catch error.TclError;
    }

    /// index番目の仕切りを移動し、実際に設定された位置を返す。
    pub fn setSashpos(self: Panedwindow, index: i32, position: i32) Error!i32 {
        const result = try self.w.interp.call(.{ self.w.path, "sashpos", index, position });
        return std.fmt.parseInt(i32, result, 10) catch error.TclError;
    }
};
