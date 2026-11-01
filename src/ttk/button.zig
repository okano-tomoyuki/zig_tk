const types = @import("../types.zig");
const widget = @import("../widget.zig");
const PhotoImage = @import("../image.zig").PhotoImage;
const common = @import("common.zig");
const Callback = @import("../callback.zig").Callback;
const StringVar = @import("../variable.zig").StringVar;
const Error = @import("../interp.zig").Error;
const Widget = widget.Widget;

/// ttk::button(Python tkinter.ttk.Button相当)。
pub const Button = struct {
    w: Widget,

    pub const Options = struct {
        text: ?[]const u8 = null,
        textvariable: ?StringVar = null,
        command: ?Callback = null,
        width: ?i32 = null,
        padding: ?types.Padding = null,
        image: ?PhotoImage = null,
        compound: ?types.Compound = null,
        underline: ?i32 = null,
        style: ?[]const u8 = null,
        cursor: ?[]const u8 = null,
        takefocus: ?bool = null,
    };

    const M = widget.Methods(Button, Options);
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

    const T = common.Methods(Button);
    pub const setState = T.setState;
    pub const instate = T.instate;

    pub fn init(parent: anytype, opts: Options) Error!Button {
        return .{ .w = try .create(widget.asWidget(parent), "ttk::button", opts) };
    }

    /// commandを疑似的に発火させる(Python ttk.Button.invoke()相当)。
    pub fn invoke(self: Button) Error![]const u8 {
        return self.w.interp.call(.{ self.w.path, "invoke" });
    }
};
