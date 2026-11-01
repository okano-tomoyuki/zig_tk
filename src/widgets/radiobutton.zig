const types = @import("../types.zig");
const widget = @import("../widget.zig");
const PhotoImage = @import("../image.zig").PhotoImage;
const variable = @import("../variable.zig");
const Callback = @import("../callback.zig").Callback;
const Error = @import("../interp.zig").Error;
const Widget = widget.Widget;

/// classic Tk radiobutton(Python tkinter.Radiobutton相当)。
/// 同じvariableを共有するボタン群のうち、variableの値がvalueと一致するものが選択状態になる。
/// Tはvariable/valueの型。enumを使うと選択肢を型で表せる:
///
///     const Size = enum { small, medium, large };
///     const size = try tk.Variable(Size).init(root, .{ .value = .medium });
///     _ = try tk.RadiobuttonOf(Size).init(frame, .{ .text = "Small", .variable = size, .value = .small });
pub fn RadiobuttonOf(comptime T: type) type {
    return struct {
        const Self = @This();

        w: Widget,

        pub const Options = struct {
            text: ?[]const u8 = null,
            textvariable: ?variable.StringVar = null,
            variable: ?variable.Variable(T) = null,
            /// このボタンが選ばれた時にvariableへ入る値。
            value: ?T = null,
            command: ?Callback = null,
            /// falseにすると丸印を描かず、押し込み式のボタンとして表示する。
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
            return .{ .w = try .create(widget.asWidget(parent), "radiobutton", opts) };
        }

        /// このボタンを選択状態にする(commandは呼ばれない)。
        pub fn select(self: Self) Error!void {
            _ = try self.w.interp.call(.{ self.w.path, "select" });
        }

        pub fn deselect(self: Self) Error!void {
            _ = try self.w.interp.call(.{ self.w.path, "deselect" });
        }

        /// クリックを疑似的に発生させる(選択してcommandを呼ぶ)。
        pub fn invoke(self: Self) Error!void {
            _ = try self.w.interp.call(.{ self.w.path, "invoke" });
        }

        pub fn flash(self: Self) Error!void {
            _ = try self.w.interp.call(.{ self.w.path, "flash" });
        }
    };
}

/// StringVarと組み合わせる形。
/// 注意: variableの値が空文字列(StringVarの既定値)だと、Tkは全ボタンを「どちらとも言えない」
/// (tristate)表示にする。初期値として選択肢のいずれかを入れておくこと。
pub const Radiobutton = RadiobuttonOf([]const u8);
