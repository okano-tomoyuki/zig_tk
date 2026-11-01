const types = @import("../types.zig");
const widget = @import("../widget.zig");
const Error = @import("../interp.zig").Error;
const Widget = widget.Widget;

/// classic Tk frame(Python tkinter.Frame相当)。
pub const Frame = struct {
    w: Widget,

    /// 生成後にconfigで変更できるオプション。
    pub const Options = struct {
        width: ?i32 = null,
        height: ?i32 = null,
        relief: ?types.Relief = null,
        borderwidth: ?i32 = null,
        background: ?[]const u8 = null,
        padx: ?i32 = null,
        pady: ?i32 = null,
        cursor: ?[]const u8 = null,
        takefocus: ?bool = null,
    };

    /// initが受け付けるオプション(Options + 生成時のみ指定できるもの)。
    pub const CreateOptions = struct {
        /// オプションデータベースやbindで使うクラス名(既定 "Frame")。生成時のみ。
        class: ?[]const u8 = null,
        /// 他アプリのウィンドウを埋め込むコンテナにする。生成時のみ。
        container: ?bool = null,
        /// "new" または同じカラーマップを使うウィンドウのパス名。生成時のみ。
        colormap: ?[]const u8 = null,
        visual: ?[]const u8 = null,

        width: ?i32 = null,
        height: ?i32 = null,
        relief: ?types.Relief = null,
        borderwidth: ?i32 = null,
        background: ?[]const u8 = null,
        padx: ?i32 = null,
        pady: ?i32 = null,
        cursor: ?[]const u8 = null,
        takefocus: ?bool = null,
    };

    const M = widget.MethodsCreate(Frame, CreateOptions, Options);
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

    pub fn init(parent: anytype, opts: CreateOptions) Error!Frame {
        return .{ .w = try .create(widget.asWidget(parent), "frame", opts) };
    }
};
