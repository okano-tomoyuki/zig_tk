const types = @import("../types.zig");
const widget = @import("../widget.zig");
const interp_mod = @import("../interp.zig");
const Cmd = interp_mod.Cmd;
const Error = interp_mod.Error;
const Widget = widget.Widget;

/// classic Tk panedwindow(Python tkinter.PanedWindow相当)。仕切りで大きさを変えられるペインの並び。
pub const PanedWindow = struct {
    w: Widget,

    pub const Options = struct {
        orient: ?types.Orient = null,
        /// 仕切りの太さ。
        sashwidth: ?i32 = null,
        sashrelief: ?types.Relief = null,
        sashpad: ?i32 = null,
        /// 仕切りにつまみを表示する。
        showhandle: ?bool = null,
        handlesize: ?i32 = null,
        /// trueならドラッグ中もペインの大きさを追従させる。
        opaqueresize: ?bool = null,
        width: ?i32 = null,
        height: ?i32 = null,
        background: ?[]const u8 = null,
        relief: ?types.Relief = null,
        borderwidth: ?i32 = null,
        cursor: ?[]const u8 = null,
    };

    /// ペインが伸縮する時に余った空間を受け取る条件。
    pub const Stretch = enum { always, first, last, middle, never };

    pub const PaneOptions = struct {
        minsize: ?i32 = null,
        width: ?i32 = null,
        height: ?i32 = null,
        padx: ?i32 = null,
        pady: ?i32 = null,
        sticky: ?types.Sticky = null,
        stretch: ?Stretch = null,
        /// ペインを隠す(並びからは外さない)。
        hide: ?bool = null,
    };

    const M = widget.Methods(PanedWindow, Options);
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

    pub fn init(parent: anytype, opts: Options) Error!PanedWindow {
        return .{ .w = try .create(widget.asWidget(parent), "panedwindow", opts) };
    }

    /// childを末尾のペインとして追加する(childはこのPanedWindowの子として生成したWidget)。
    pub fn add(self: PanedWindow, child: anytype, opts: PaneOptions) Error!void {
        try self.paneCommand("add", child, opts);
    }

    /// ペインの設定を変更する。
    pub fn paneconfigure(self: PanedWindow, child: anytype, opts: PaneOptions) Error!void {
        try self.paneCommand("paneconfigure", child, opts);
    }

    /// childをペインから外す(Widget自体は破棄されない)。
    pub fn forget(self: PanedWindow, child: anytype) Error!void {
        _ = try self.w.interp.call(.{ self.w.path, "forget", widget.asWidget(child) });
    }

    fn paneCommand(self: PanedWindow, sub: []const u8, child: anytype, opts: PaneOptions) Error!void {
        var cmd: Cmd = .init(self.w.interp);
        defer cmd.deinit();
        try cmd.add(self.w.path);
        try cmd.add(sub);
        try cmd.add(widget.asWidget(child));
        try cmd.addOptions(self.w.path, opts);
        _ = try cmd.eval();
    }
};
