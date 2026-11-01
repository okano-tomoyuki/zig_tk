const types = @import("../types.zig");
const widget = @import("../widget.zig");
const common = @import("common.zig");
const Menu = @import("../widgets/menu.zig").Menu;
const Direction = @import("../widgets/menubutton.zig").Direction;
const PhotoImage = @import("../image.zig").PhotoImage;
const StringVar = @import("../variable.zig").StringVar;
const Error = @import("../interp.zig").Error;
const Widget = widget.Widget;

/// ttk::menubutton(Python tkinter.ttk.Menubutton相当)。押すとmenuを開くボタン。
pub const Menubutton = struct {
    w: Widget,

    pub const Options = struct {
        text: ?[]const u8 = null,
        textvariable: ?StringVar = null,
        /// 開くメニュー(このMenubuttonの子として生成したMenu)。
        menu: ?Menu = null,
        direction: ?Direction = null,
        image: ?PhotoImage = null,
        compound: ?types.Compound = null,
        width: ?i32 = null,
        padding: ?types.Padding = null,
        underline: ?i32 = null,
        style: ?[]const u8 = null,
        cursor: ?[]const u8 = null,
        takefocus: ?bool = null,
    };

    const M = widget.Methods(Menubutton, Options);
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

    const S = common.Methods(Menubutton);
    pub const setState = S.setState;
    pub const instate = S.instate;

    pub fn init(parent: anytype, opts: Options) Error!Menubutton {
        return .{ .w = try .create(widget.asWidget(parent), "ttk::menubutton", opts) };
    }
};
