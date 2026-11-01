const std = @import("std");
const types = @import("../types.zig");
const widget = @import("../widget.zig");
const common = @import("common.zig");
const variable = @import("../variable.zig");
const Error = @import("../interp.zig").Error;
const Widget = widget.Widget;

/// ttk::progressbar(Python tkinter.ttk.Progressbar相当)。
pub const Progressbar = struct {
    w: Widget,

    pub const Mode = enum {
        /// 進捗(value / maximum)を表示する。
        determinate,
        /// 進捗が分からない処理中であることを、往復するバーで表示する(start/stop)。
        indeterminate,
    };

    pub const Options = struct {
        orient: ?types.Orient = null,
        /// 長辺の長さ(ピクセル)。
        length: ?i32 = null,
        mode: ?Mode = null,
        /// valueの最大値(既定 100)。
        maximum: ?f64 = null,
        value: ?f64 = null,
        variable: ?variable.DoubleVar = null,
        /// バーに重ねて表示する文字列(Tk 9.0以降)。
        text: ?[]const u8 = null,
        style: ?[]const u8 = null,
        cursor: ?[]const u8 = null,
        takefocus: ?bool = null,
    };

    const M = widget.Methods(Progressbar, Options);
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

    const S = common.Methods(Progressbar);
    pub const setState = S.setState;
    pub const instate = S.instate;

    pub fn init(parent: anytype, opts: Options) Error!Progressbar {
        return .{ .w = try .create(widget.asWidget(parent), "ttk::progressbar", opts) };
    }

    /// interval_msミリ秒ごとにstep(1)を自動で繰り返す(既定 50ms)。主にindeterminateモード用。
    pub fn start(self: Progressbar, interval_ms: ?u32) Error!void {
        if (interval_ms) |ms| {
            _ = try self.w.interp.call(.{ self.w.path, "start", ms });
        } else {
            _ = try self.w.interp.call(.{ self.w.path, "start" });
        }
    }

    pub fn stop(self: Progressbar) Error!void {
        _ = try self.w.interp.call(.{ self.w.path, "stop" });
    }

    /// valueをamount(既定 1)だけ進める。maximumを超えると0に戻る。
    pub fn step(self: Progressbar, amount: ?f64) Error!void {
        if (amount) |a| {
            _ = try self.w.interp.call(.{ self.w.path, "step", a });
        } else {
            _ = try self.w.interp.call(.{ self.w.path, "step" });
        }
    }

    /// 現在の値。
    pub fn value(self: Progressbar) Error!f64 {
        const result = try self.w.cget("value");
        return std.fmt.parseFloat(f64, result) catch self.w.interp.failWith("unexpected progressbar value");
    }

    /// 値を設定する。variableが結び付いている場合は(-valueが変数の値で上書きされるため)変数側に設定する。
    pub fn setValue(self: Progressbar, v: f64) Error!void {
        const var_name = try self.w.cget("variable");
        if (var_name.len > 0) {
            _ = try self.w.interp.call(.{ "set", var_name, v });
        } else {
            try self.w.configure(.{ .value = v });
        }
    }
};
