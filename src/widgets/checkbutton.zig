const types = @import("../types.zig");
const widget = @import("../widget.zig");
const PhotoImage = @import("../image.zig").PhotoImage;
const variable = @import("../variable.zig");
const Callback = @import("../callback.zig").Callback;
const Error = @import("../interp.zig").Error;
const Widget = widget.Widget;

/// classic Tk checkbutton(Python tkinter.Checkbutton相当)。
/// Tはvariableの値の型で、onvalue/offvalueも同じ型に限定される。
/// 例: CheckbuttonOf(bool) + BooleanVar、CheckbuttonOf([]const u8) + StringVar(onvalue="on"等)。
pub fn CheckbuttonOf(comptime T: type) type {
    return struct {
        const Self = @This();

        w: Widget,

        pub const Options = struct {
            text: ?[]const u8 = null,
            textvariable: ?variable.StringVar = null,
            /// チェック状態と結び付く変数。
            variable: ?variable.Variable(T) = null,
            /// チェック時にvariableへ入る値(既定は 1)。
            onvalue: ?T = null,
            /// 非チェック時にvariableへ入る値(既定は 0)。
            offvalue: ?T = null,
            command: ?Callback = null,
            /// falseにするとチェックボックスを描かず、押し込み式のボタンとして表示する。
            indicatoron: ?bool = null,
            selectcolor: ?[]const u8 = null,
            width: ?i32 = null,
            height: ?i32 = null,
            state: ?types.State = null,
            relief: ?types.Relief = null,
            borderwidth: ?i32 = null,
            background: ?[]const u8 = null,
            foreground: ?[]const u8 = null,
            activebackground: ?[]const u8 = null,
            activeforeground: ?[]const u8 = null,
            font: ?[]const u8 = null,
            padx: ?i32 = null,
            pady: ?i32 = null,
            anchor: ?types.Anchor = null,
            justify: ?types.Justify = null,
            wraplength: ?i32 = null,
            underline: ?i32 = null,
            image: ?PhotoImage = null,
            compound: ?types.Compound = null,
            cursor: ?[]const u8 = null,
            takefocus: ?bool = null,
        };

        const M = widget.Methods(Self, Options);
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

        pub fn init(parent: anytype, opts: Options) Error!Self {
            return .{ .w = try .create(widget.asWidget(parent), "checkbutton", opts) };
        }

        /// チェック状態にする(commandは呼ばれない)。
        pub fn select(self: Self) Error!void {
            _ = try self.w.interp.call(.{ self.w.path, "select" });
        }

        /// 非チェック状態にする(commandは呼ばれない)。
        pub fn deselect(self: Self) Error!void {
            _ = try self.w.interp.call(.{ self.w.path, "deselect" });
        }

        /// チェック状態を反転する(commandは呼ばれない)。
        pub fn toggle(self: Self) Error!void {
            _ = try self.w.interp.call(.{ self.w.path, "toggle" });
        }

        /// クリックを疑似的に発生させる(状態を反転しcommandを呼ぶ)。
        pub fn invoke(self: Self) Error!void {
            _ = try self.w.interp.call(.{ self.w.path, "invoke" });
        }

        pub fn flash(self: Self) Error!void {
            _ = try self.w.interp.call(.{ self.w.path, "flash" });
        }
    };
}

/// BooleanVarと組み合わせる最も一般的な形。
pub const Checkbutton = CheckbuttonOf(bool);
