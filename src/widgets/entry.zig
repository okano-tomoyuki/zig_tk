const types = @import("../types.zig");
const widget = @import("../widget.zig");
const callback = @import("../callback.zig");
const editable = @import("../editable.zig");
const scroll = @import("../scroll.zig");
const StringVar = @import("../variable.zig").StringVar;
const Error = @import("../interp.zig").Error;
const Widget = widget.Widget;

/// classic Tk entry(Python tkinter.Entry相当)。1行の入力欄。
pub const Entry = struct {
    w: Widget,

    pub const Options = struct {
        textvariable: ?StringVar = null,
        width: ?i32 = null,
        /// パスワード入力等で表示を置き換える文字(例: "*")。
        show: ?[]const u8 = null,
        justify: ?types.Justify = null,
        state: ?types.State = null,
        font: ?[]const u8 = null,
        foreground: ?[]const u8 = null,
        background: ?[]const u8 = null,
        disabledforeground: ?[]const u8 = null,
        disabledbackground: ?[]const u8 = null,
        readonlybackground: ?[]const u8 = null,
        insertbackground: ?[]const u8 = null,
        insertwidth: ?i32 = null,
        selectforeground: ?[]const u8 = null,
        selectbackground: ?[]const u8 = null,
        relief: ?types.Relief = null,
        borderwidth: ?i32 = null,
        highlightthickness: ?i32 = null,
        exportselection: ?bool = null,
        /// いつvalidatecommandを呼ぶか(既定 none)。
        validate: ?types.Validate = null,
        /// 入力を検証する(tk.callbackにfn(ctx, tk.Validation) !boolを渡す)。falseで変更を拒否する。
        validatecommand: ?callback.ValidateCallback = null,
        /// validatecommandがfalseを返した時に呼ばれる。
        invalidcommand: ?callback.Callback = null,
        xscrollcommand: ?scroll.Setter = null,
        cursor: ?[]const u8 = null,
        takefocus: ?bool = null,
    };

    const M = widget.Methods(Entry, Options);
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

    const E = editable.Methods(Entry);
    pub const get = E.get;
    pub const insert = E.insert;
    pub const delete = E.delete;
    pub const icursor = E.icursor;
    pub const index = E.index;
    pub const selectionRange = E.selectionRange;
    pub const selectionClear = E.selectionClear;
    pub const validateNow = E.validateNow;

    const X = scroll.XMethods(Entry);
    pub const xview = X.view;
    pub const xviewMoveto = X.moveto;
    pub const xviewScroll = X.scroll;
    pub const xviewCommand = X.command;

    pub fn init(parent: anytype, opts: Options) Error!Entry {
        return .{ .w = try .create(widget.asWidget(parent), "entry", opts) };
    }
};
