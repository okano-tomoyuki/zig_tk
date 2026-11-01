const types = @import("../types.zig");
const widget = @import("../widget.zig");
const common = @import("common.zig");
const scroll = @import("../scroll.zig");
const Error = @import("../interp.zig").Error;
const Widget = widget.Widget;

/// ttk::scrollbar(Python tkinter.ttk.Scrollbar相当)。連携方法はscroll.zig参照。
pub const Scrollbar = struct {
    w: Widget,

    pub const Options = struct {
        orient: ?types.Orient = null,
        /// つまみの操作時に呼ぶ対象Widgetのxview/yview(例: listbox.yviewCommand())。
        command: ?scroll.View = null,
        style: ?[]const u8 = null,
        cursor: ?[]const u8 = null,
        takefocus: ?bool = null,
    };

    const M = widget.Methods(Scrollbar, Options);
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

    const T = common.Methods(Scrollbar);
    pub const setState = T.setState;
    pub const instate = T.instate;

    const S = scroll.ScrollbarMethods(Scrollbar);
    pub const get = S.get;
    pub const set = S.set;
    pub const setter = S.setter;
    pub const attach = S.attach;

    pub fn init(parent: anytype, opts: Options) Error!Scrollbar {
        return .{ .w = try .create(widget.asWidget(parent), "ttk::scrollbar", opts) };
    }
};
