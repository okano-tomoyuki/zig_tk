const types = @import("../types.zig");
const widget = @import("../widget.zig");
const callback = @import("../callback.zig");
const common = @import("common.zig");
const editable = @import("../editable.zig");
const scroll = @import("../scroll.zig");
const variable = @import("../variable.zig");
const Callback = @import("../callback.zig").Callback;
const Error = @import("../interp.zig").Error;
const Widget = widget.Widget;

/// ttk::spinbox(Python tkinter.ttk.Spinbox相当)。
/// 数値範囲(from/to/increment)または選択肢の一覧(values)のどちらかで値を切り替える。
pub const Spinbox = struct {
    w: Widget,

    pub const Options = struct {
        from: ?f64 = null,
        to: ?f64 = null,
        increment: ?f64 = null,
        /// 選択肢の一覧。指定するとfrom/toより優先される。
        values: ?[]const []const u8 = null,
        wrap: ?bool = null,
        /// 数値の表示形式(例: "%5.2f")。
        format: ?[]const u8 = null,
        textvariable: ?variable.StringVar = null,
        /// 上下ボタンで値が変わるたびに呼ばれる。
        command: ?Callback = null,
        width: ?i32 = null,
        state: ?types.State = null,
        justify: ?types.Justify = null,
        font: ?[]const u8 = null,
        foreground: ?[]const u8 = null,
        background: ?[]const u8 = null,
        exportselection: ?bool = null,
        /// いつvalidatecommandを呼ぶか(既定 none)。
        validate: ?types.Validate = null,
        /// 入力を検証する(tk.callbackにfn(ctx, tk.Validation) !boolを渡す)。falseで変更を拒否する。
        validatecommand: ?callback.ValidateCallback = null,
        /// validatecommandがfalseを返した時に呼ばれる。
        invalidcommand: ?callback.Callback = null,
        xscrollcommand: ?scroll.Setter = null,
        style: ?[]const u8 = null,
        cursor: ?[]const u8 = null,
        takefocus: ?bool = null,
    };

    const M = widget.Methods(Spinbox, Options);
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

    const S = common.Methods(Spinbox);
    pub const setState = S.setState;
    pub const instate = S.instate;

    const E = editable.Methods(Spinbox);
    pub const get = E.get;
    pub const insert = E.insert;
    pub const delete = E.delete;
    pub const icursor = E.icursor;
    pub const index = E.index;
    pub const selectionRange = E.selectionRange;
    pub const selectionClear = E.selectionClear;
    pub const validateNow = E.validateNow;

    const X = scroll.XMethods(Spinbox);
    pub const xview = X.view;
    pub const xviewMoveto = X.moveto;
    pub const xviewScroll = X.scroll;
    pub const xviewCommand = X.command;

    pub fn init(parent: anytype, opts: Options) Error!Spinbox {
        return .{ .w = try .create(widget.asWidget(parent), "ttk::spinbox", opts) };
    }

    /// 表示中の値をtextに置き換える。
    pub fn set(self: Spinbox, text: []const u8) Error!void {
        _ = try self.w.interp.call(.{ self.w.path, "set", text });
    }
};
