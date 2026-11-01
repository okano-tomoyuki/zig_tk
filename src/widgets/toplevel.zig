const types = @import("../types.zig");
const widget = @import("../widget.zig");
const Menu = @import("menu.zig").Menu;
const wm = @import("wm.zig");
const Error = @import("../interp.zig").Error;
const Widget = widget.Widget;

/// 追加のトップレベルウィンドウ(Python tkinter.Toplevel相当)。
pub const Toplevel = struct {
    w: Widget,

    /// 生成後にconfigで変更できるオプション。
    pub const Options = struct {
        background: ?[]const u8 = null,
        borderwidth: ?i32 = null,
        relief: ?types.Relief = null,
        padx: ?i32 = null,
        pady: ?i32 = null,
        width: ?i32 = null,
        height: ?i32 = null,
        cursor: ?[]const u8 = null,
        takefocus: ?bool = null,
        /// メニューバー(このウィンドウの子として生成したMenu)。
        menu: ?Menu = null,
    };

    /// initが受け付けるオプション(Options + 生成時のみ指定できるもの)。
    pub const CreateOptions = struct {
        /// オプションデータベースやbindで使うクラス名(既定 "Toplevel")。生成時のみ。
        class: ?[]const u8 = null,
        /// 他アプリのウィンドウを埋め込むコンテナにする。生成時のみ。
        container: ?bool = null,
        /// "new" または同じカラーマップを使うウィンドウのパス名。生成時のみ。
        colormap: ?[]const u8 = null,
        visual: ?[]const u8 = null,
        /// 表示するX11スクリーン(例: ":0.0")。生成時のみ。
        screen: ?[]const u8 = null,
        /// 埋め込み先ウィンドウのID。生成時のみ。
        use: ?[]const u8 = null,

        background: ?[]const u8 = null,
        borderwidth: ?i32 = null,
        relief: ?types.Relief = null,
        padx: ?i32 = null,
        pady: ?i32 = null,
        width: ?i32 = null,
        height: ?i32 = null,
        cursor: ?[]const u8 = null,
        takefocus: ?bool = null,
        /// メニューバー(このウィンドウの子として生成したMenu)。
        menu: ?Menu = null,
    };

    const M = widget.MethodsCreate(Toplevel, CreateOptions, Options);
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

    const Wm = wm.Methods(Toplevel);
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

    pub fn init(parent: anytype, opts: CreateOptions) Error!Toplevel {
        return .{ .w = try .create(widget.asWidget(parent), "toplevel", opts) };
    }
};
