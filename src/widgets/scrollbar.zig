const types = @import("../types.zig");
const widget = @import("../widget.zig");
const scroll = @import("../scroll.zig");
const Error = @import("../interp.zig").Error;
const Widget = widget.Widget;

/// classic Tk scrollbar(Python tkinter.Scrollbar相当)。連携方法はscroll.zig参照。
pub const Scrollbar = struct {
    w: Widget,

    pub const Options = struct {
        orient: ?types.Orient = null,
        /// つまみの操作時に呼ぶ対象Widgetのxview/yview(例: listbox.yviewCommand())。
        command: ?scroll.View = null,
        width: ?i32 = null,
        elementborderwidth: ?i32 = null,
        /// trueならつまみを離した時だけ対象をスクロールする。
        jump: ?bool = null,
        relief: ?types.Relief = null,
        activerelief: ?types.Relief = null,
        borderwidth: ?i32 = null,
        background: ?[]const u8 = null,
        activebackground: ?[]const u8 = null,
        troughcolor: ?[]const u8 = null,
        repeatdelay: ?i32 = null,
        repeatinterval: ?i32 = null,
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

    const S = scroll.ScrollbarMethods(Scrollbar);
    pub const get = S.get;
    pub const set = S.set;
    pub const setter = S.setter;
    pub const attach = S.attach;

    pub fn init(parent: anytype, opts: Options) Error!Scrollbar {
        return .{ .w = try .create(widget.asWidget(parent), "scrollbar", opts) };
    }
};
