const types = @import("../types.zig");
const widget = @import("../widget.zig");
const Error = @import("../interp.zig").Error;
const Widget = widget.Widget;

/// ttk::separator(Python tkinter.ttk.Separator相当)。区切り線。
/// 横線はpack(.{ .fill = .x })、縦線はorient = .verticalとpack(.{ .fill = .y })で使う。
pub const Separator = struct {
    w: Widget,

    pub const Options = struct {
        orient: ?types.Orient = null,
        style: ?[]const u8 = null,
        cursor: ?[]const u8 = null,
        takefocus: ?bool = null,
    };

    const M = widget.Methods(Separator, Options);
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

    pub fn init(parent: anytype, opts: Options) Error!Separator {
        return .{ .w = try .create(widget.asWidget(parent), "ttk::separator", opts) };
    }
};
