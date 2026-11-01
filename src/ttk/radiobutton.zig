const types = @import("../types.zig");
const widget = @import("../widget.zig");
const PhotoImage = @import("../image.zig").PhotoImage;
const common = @import("common.zig");
const variable = @import("../variable.zig");
const Callback = @import("../callback.zig").Callback;
const Error = @import("../interp.zig").Error;
const Widget = widget.Widget;

/// ttk::radiobutton(Python tkinter.ttk.Radiobutton相当)。
/// Tはvariable/valueの型(tk.RadiobuttonOfと同じ。enumも使える)。
pub fn RadiobuttonOf(comptime T: type) type {
    return struct {
        const Self = @This();

        w: Widget,

        pub const Options = struct {
            text: ?[]const u8 = null,
            textvariable: ?variable.StringVar = null,
            variable: ?variable.Variable(T) = null,
            value: ?T = null,
            command: ?Callback = null,
            width: ?i32 = null,
            padding: ?types.Padding = null,
            image: ?PhotoImage = null,
            compound: ?types.Compound = null,
            underline: ?i32 = null,
            style: ?[]const u8 = null,
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

        const S = common.Methods(Self);
        pub const setState = S.setState;
        pub const instate = S.instate;

        pub fn init(parent: anytype, opts: Options) Error!Self {
            return .{ .w = try .create(widget.asWidget(parent), "ttk::radiobutton", opts) };
        }

        /// クリックを疑似的に発生させる(選択してcommandを呼ぶ)。
        pub fn invoke(self: Self) Error!void {
            _ = try self.w.interp.call(.{ self.w.path, "invoke" });
        }
    };
}

/// StringVarと組み合わせる形(初期値を選択肢のいずれかにしておくこと。tk.Radiobutton参照)。
pub const Radiobutton = RadiobuttonOf([]const u8);
