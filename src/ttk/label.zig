const types = @import("../types.zig");
const widget = @import("../widget.zig");
const PhotoImage = @import("../image.zig").PhotoImage;
const common = @import("common.zig");
const StringVar = @import("../variable.zig").StringVar;
const Error = @import("../interp.zig").Error;
const Widget = widget.Widget;

/// ttk::label(Python tkinter.ttk.Label相当)。
pub const Label = struct {
    w: Widget,

    pub const Options = struct {
        text: ?[]const u8 = null,
        textvariable: ?StringVar = null,
        width: ?i32 = null,
        anchor: ?types.Anchor = null,
        justify: ?types.Justify = null,
        wraplength: ?i32 = null,
        relief: ?types.Relief = null,
        background: ?[]const u8 = null,
        foreground: ?[]const u8 = null,
        font: ?[]const u8 = null,
        padding: ?types.Padding = null,
        image: ?PhotoImage = null,
        compound: ?types.Compound = null,
        underline: ?i32 = null,
        style: ?[]const u8 = null,
        cursor: ?[]const u8 = null,
        takefocus: ?bool = null,
    };

    const M = widget.Methods(Label, Options);
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

    const T = common.Methods(Label);
    pub const setState = T.setState;
    pub const instate = T.instate;

    pub fn init(parent: anytype, opts: Options) Error!Label {
        return .{ .w = try .create(widget.asWidget(parent), "ttk::label", opts) };
    }
};
