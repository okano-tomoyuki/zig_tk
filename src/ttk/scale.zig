const std = @import("std");
const types = @import("../types.zig");
const widget = @import("../widget.zig");
const common = @import("common.zig");
const variable = @import("../variable.zig");
const Callback = @import("../callback.zig").Callback;
const Error = @import("../interp.zig").Error;
const Widget = widget.Widget;

/// ttk::scale(Python tkinter.ttk.Scale相当)。classic版と違い刻み(resolution)や目盛りは無い。
pub const Scale = struct {
    w: Widget,

    pub const Options = struct {
        from: ?f64 = null,
        to: ?f64 = null,
        value: ?f64 = null,
        variable: ?variable.DoubleVar = null,
        /// 値が変わるたびに呼ばれる。現在値はgetで取得する。
        command: ?Callback = null,
        orient: ?types.Orient = null,
        length: ?i32 = null,
        style: ?[]const u8 = null,
        cursor: ?[]const u8 = null,
        takefocus: ?bool = null,
    };

    const M = widget.Methods(Scale, Options);
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

    const S = common.Methods(Scale);
    pub const setState = S.setState;
    pub const instate = S.instate;

    pub fn init(parent: anytype, opts: Options) Error!Scale {
        return .{ .w = try .create(widget.asWidget(parent), "ttk::scale", opts) };
    }

    pub fn get(self: Scale) Error!f64 {
        const result = try self.w.interp.call(.{ self.w.path, "get" });
        return std.fmt.parseFloat(f64, result) catch error.TclError;
    }

    pub fn set(self: Scale, v: f64) Error!void {
        _ = try self.w.interp.call(.{ self.w.path, "set", v });
    }
};
