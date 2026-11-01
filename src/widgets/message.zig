const types = @import("../types.zig");
const widget = @import("../widget.zig");
const StringVar = @import("../variable.zig").StringVar;
const Error = @import("../interp.zig").Error;
const Widget = widget.Widget;

/// classic Tk message(Python tkinter.Message相当)。複数行に自動で折り返して表示するラベル。
pub const Message = struct {
    w: Widget,

    pub const Options = struct {
        text: ?[]const u8 = null,
        textvariable: ?StringVar = null,
        /// 折り返す幅(ピクセル、0ならaspectに従う)。
        width: ?i32 = null,
        /// 幅:高さの比(×100、既定 150)。widthが0の時に使われる。
        aspect: ?i32 = null,
        justify: ?types.Justify = null,
        anchor: ?types.Anchor = null,
        font: ?[]const u8 = null,
        foreground: ?[]const u8 = null,
        background: ?[]const u8 = null,
        padx: ?i32 = null,
        pady: ?i32 = null,
        relief: ?types.Relief = null,
        borderwidth: ?i32 = null,
        cursor: ?[]const u8 = null,
        takefocus: ?bool = null,
    };

    const M = widget.Methods(Message, Options);
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

    pub fn init(parent: anytype, opts: Options) Error!Message {
        return .{ .w = try .create(widget.asWidget(parent), "message", opts) };
    }
};
