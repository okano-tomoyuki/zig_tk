const types = @import("../types.zig");
const widget = @import("../widget.zig");
const common = @import("common.zig");
const Error = @import("../interp.zig").Error;
const Widget = widget.Widget;

/// ttk::labelframe(Python tkinter.ttk.LabelFrame相当)。見出し付きの枠。
pub const Labelframe = struct {
    w: Widget,

    /// 見出しの位置(枠のどの辺のどちら寄りか。例: nw = 上辺の左寄り、wn = 左辺の上寄り)。
    pub const LabelAnchor = enum { nw, n, ne, en, e, es, se, s, sw, ws, w, wn };

    /// 生成後にconfigで変更できるオプション。
    pub const Options = struct {
        text: ?[]const u8 = null,
        labelanchor: ?LabelAnchor = null,
        underline: ?i32 = null,
        width: ?i32 = null,
        height: ?i32 = null,
        padding: ?types.Padding = null,
        relief: ?types.Relief = null,
        borderwidth: ?i32 = null,
        style: ?[]const u8 = null,
        cursor: ?[]const u8 = null,
        takefocus: ?bool = null,
    };

    /// initが受け付けるオプション(Options + 生成時のみ指定できるもの)。
    pub const CreateOptions = struct {
        /// スタイルやbindで使うクラス名(既定 "TLabelframe")。生成時のみ。
        class: ?[]const u8 = null,

        text: ?[]const u8 = null,
        labelanchor: ?LabelAnchor = null,
        underline: ?i32 = null,
        width: ?i32 = null,
        height: ?i32 = null,
        padding: ?types.Padding = null,
        relief: ?types.Relief = null,
        borderwidth: ?i32 = null,
        style: ?[]const u8 = null,
        cursor: ?[]const u8 = null,
        takefocus: ?bool = null,
    };

    const M = widget.MethodsCreate(Labelframe, CreateOptions, Options);
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

    const S = common.Methods(Labelframe);
    pub const setState = S.setState;
    pub const instate = S.instate;

    pub fn init(parent: anytype, opts: CreateOptions) Error!Labelframe {
        return .{ .w = try .create(widget.asWidget(parent), "ttk::labelframe", opts) };
    }
};
