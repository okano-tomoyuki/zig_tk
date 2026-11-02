//! ルートウィンドウ(Python tkinter.Tk相当)。インタプリタの所有者でもある。
const std = @import("std");
const tcl = @import("../tcl.zig");
const types = @import("../types.zig");
const widget = @import("../widget.zig");
const Menu = @import("menu.zig").Menu;
const wm = @import("wm.zig");
const interp_mod = @import("../interp.zig");
const Interp = interp_mod.Interp;
const Error = interp_mod.Error;
const TimerId = interp_mod.TimerId;
const callback = @import("../callback.zig");
const theme = @import("../theme.zig");
const Widget = widget.Widget;

pub const Tk = struct {
    w: Widget,

    pub const Options = struct {
        background: ?[]const u8 = null,
        borderwidth: ?i32 = null,
        relief: ?types.Relief = null,
        padx: ?i32 = null,
        pady: ?i32 = null,
        width: ?i32 = null,
        height: ?i32 = null,
        cursor: ?[]const u8 = null,
        /// メニューバー(このウィンドウの子として生成したMenu)。
        menu: ?Menu = null,
    };

    const M = widget.Methods(Tk, Options);
    pub const toTclObj = M.toTclObj;
    pub const config = M.config;
    pub const cget = M.cget;
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

    /// Tcl/Tkを初期化してルートウィンドウ "." を得る。deinitで破棄する。
    pub fn init(gpa: std.mem.Allocator) Error!Tk {
        const interp = try Interp.create(gpa);
        return .{ .w = .{ .interp = interp, .path = "." } };
    }

    pub fn deinit(self: Tk) void {
        self.w.interp.destroy();
    }

    /// 全てのウィンドウが破棄されるまでイベントループを回す。
    pub fn mainloop(self: Tk) void {
        self.w.interp.checkThread();
        tcl.Tk_MainLoop();
    }

    /// ルートウィンドウを破棄してmainloopを抜ける。
    pub fn quit(self: Tk) Error!void {
        return self.w.destroy();
    }

    const Wm = wm.Methods(Tk);
    pub const title = Wm.title;
    pub const geometry = Wm.geometry;
    pub const withdraw = Wm.withdraw;
    pub const deiconify = Wm.deiconify;
    pub const iconify = Wm.iconify;
    pub const resizable = Wm.resizable;
    pub const minsize = Wm.minsize;
    pub const maxsize = Wm.maxsize;
    pub const lift = Wm.lift;
    pub const protocol = Wm.protocol;
    pub const iconphoto = Wm.iconphoto;

    /// msミリ秒後にcbを1回だけ呼ぶ(Python Misc.after相当)。繰り返す場合はcb内で再度予約する。
    pub fn after(self: Tk, ms: u32, cb: callback.Callback) Error!TimerId {
        return self.w.interp.after(ms, cb);
    }

    /// 同梱のttkテーマに切り替える(theme.zig参照)。例: try root.setTheme(.sun_valley_dark)
    pub fn setTheme(self: Tk, which: theme.Theme) Error!void {
        return theme.use(self.w.interp, which);
    }

    /// どのスレッドからでも呼べる。func(payload)をこのインタプリタのスレッドで実行する(Interp.post参照)。
    pub fn post(self: Tk, payload: anytype, comptime func: anytype) error{OutOfMemory}!void {
        return self.w.interp.post(payload, func);
    }

    /// イベントループが暇になった時にcbを1回だけ呼ぶ(Python Misc.after_idle相当)。
    pub fn afterIdle(self: Tk, cb: callback.Callback) Error!TimerId {
        return self.w.interp.afterIdle(cb);
    }

    /// 予約を取り消してコールバックを解放する。発火済みなら何もしない。
    pub fn afterCancel(self: Tk, id: TimerId) void {
        self.w.interp.afterCancel(id);
    }

    /// 保留中のイベントを処理する(Python Misc.update相当)。
    pub fn update(self: Tk) Error!void {
        return self.w.interp.update();
    }

    /// 保留中の再描画・ジオメトリ計算だけを処理する(Python Misc.update_idletasks相当)。
    pub fn updateIdletasks(self: Tk) Error!void {
        return self.w.interp.updateIdletasks();
    }

    /// クリップボードの文字列。空の場合はerror.TclError。戻り値は次のTcl呼び出しまで有効。
    pub fn clipboardGet(self: Tk) Error![]const u8 {
        return self.w.interp.call(.{ "clipboard", "get" });
    }

    pub fn clipboardClear(self: Tk) Error!void {
        _ = try self.w.interp.call(.{ "clipboard", "clear" });
    }

    /// クリップボードへtextを追記する(置き換える場合は先にclipboardClear)。
    pub fn clipboardAppend(self: Tk, text: []const u8) Error!void {
        _ = try self.w.interp.call(.{ "clipboard", "append", "--", text });
    }

    /// 警告音を鳴らす。
    pub fn bell(self: Tk) Error!void {
        _ = try self.w.interp.call(.{"bell"});
    }

    /// 未ラップのTclコマンドを呼ぶ(Interp.call参照)。
    pub fn call(self: Tk, words: anytype) Error![]const u8 {
        return self.w.interp.call(words);
    }

    /// 直近にerror.TclErrorを返した呼び出しのエラーメッセージ。
    pub fn lastError(self: Tk) []const u8 {
        return self.w.interp.lastError();
    }
};
