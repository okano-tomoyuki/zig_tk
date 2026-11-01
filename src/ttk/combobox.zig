const std = @import("std");
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

/// ttk::combobox(Python tkinter.ttk.Combobox相当)。
/// 一覧から選ばれた時は仮想イベント "<<ComboboxSelected>>" が発生する(bindで受け取る)。
pub const Combobox = struct {
    w: Widget,

    pub const Options = struct {
        /// ドロップダウンに表示する選択肢。
        values: ?[]const []const u8 = null,
        textvariable: ?variable.StringVar = null,
        /// readonlyにすると一覧からの選択のみ(直接入力不可)になる。
        state: ?types.State = null,
        /// ドロップダウンを開く直前に呼ばれる(valuesの更新に使う)。
        postcommand: ?Callback = null,
        width: ?i32 = null,
        /// ドロップダウンに一度に表示する行数。
        height: ?i32 = null,
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

    const M = widget.Methods(Combobox, Options);
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

    const S = common.Methods(Combobox);
    pub const setState = S.setState;
    pub const instate = S.instate;

    const E = editable.Methods(Combobox);
    pub const get = E.get;
    pub const insert = E.insert;
    pub const delete = E.delete;
    pub const icursor = E.icursor;
    pub const index = E.index;
    pub const selectionRange = E.selectionRange;
    pub const selectionClear = E.selectionClear;
    pub const validateNow = E.validateNow;

    const X = scroll.XMethods(Combobox);
    pub const xview = X.view;
    pub const xviewMoveto = X.moveto;
    pub const xviewScroll = X.scroll;
    pub const xviewCommand = X.command;

    pub fn init(parent: anytype, opts: Options) Error!Combobox {
        return .{ .w = try .create(widget.asWidget(parent), "ttk::combobox", opts) };
    }

    /// 表示中の値をtextに置き換える。
    pub fn set(self: Combobox, text: []const u8) Error!void {
        _ = try self.w.interp.call(.{ self.w.path, "set", text });
    }

    /// 表示中の値がvaluesの何番目か。一致する選択肢が無ければnull。
    pub fn current(self: Combobox) Error!?usize {
        const result = try self.w.interp.call(.{ self.w.path, "current" });
        // 一致しない場合、Tk 8.6は -1、Tk 9.0は空文字列を返す
        if (result.len == 0) return null;
        const i = std.fmt.parseInt(i64, result, 10) catch return error.TclError;
        return if (i < 0) null else @intCast(i);
    }

    /// valuesのindex番目を表示する。
    pub fn setCurrent(self: Combobox, i: usize) Error!void {
        _ = try self.w.interp.call(.{ self.w.path, "current", i });
    }
};
