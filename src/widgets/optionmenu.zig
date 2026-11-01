const std = @import("std");
const types = @import("../types.zig");
const widget = @import("../widget.zig");
const variable = @import("../variable.zig");
const Menu = @import("menu.zig").Menu;
const Callback = @import("../callback.zig").Callback;
const interp_mod = @import("../interp.zig");
const Cmd = interp_mod.Cmd;
const Error = interp_mod.Error;
const Widget = widget.Widget;

/// 選択肢から1つを選ぶボタン(Python tkinter.OptionMenu相当)。
/// Menubuttonとradiobutton項目のMenuで構成し、選んだ値がvariableに入る。
/// Tはvariableと選択肢の型。enumなら選択肢のラベルはタグ名になる:
///
///     const Size = enum { small, medium, large };
///     const size = try tk.Variable(Size).init(root, .{ .value = .medium });
///     _ = try tk.OptionMenuOf(Size).init(frame, size, &.{ .small, .medium, .large }, .{});
pub fn OptionMenuOf(comptime T: type) type {
    return struct {
        const Self = @This();

        /// ボタン本体(Menubutton)。
        w: Widget,
        /// 選択肢を並べたメニュー。
        menu: Menu,
        variable: variable.Variable(T),
        command: ?Callback,

        pub const Options = struct {
            /// 選択肢が選ばれた時に呼ばれる(選んだ値はvariableから取得する)。
            command: ?Callback = null,
            width: ?i32 = null,
            state: ?types.State = null,
            font: ?[]const u8 = null,
            foreground: ?[]const u8 = null,
            background: ?[]const u8 = null,
            anchor: ?types.Anchor = null,
            cursor: ?[]const u8 = null,
            takefocus: ?bool = null,
        };

        /// config/cgetで扱えるボタン側のオプション(commandは選択肢ごとの設定のため含まない)。
        pub const ButtonOptions = struct {
            width: ?i32 = null,
            state: ?types.State = null,
            font: ?[]const u8 = null,
            foreground: ?[]const u8 = null,
            background: ?[]const u8 = null,
            anchor: ?types.Anchor = null,
            cursor: ?[]const u8 = null,
            takefocus: ?bool = null,
        };

        const M = widget.Methods(Self, ButtonOptions);
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

        pub fn init(parent: anytype, var_: variable.Variable(T), values: []const T, opts: Options) Error!Self {
            const p = widget.asWidget(parent);
            var cmd_opts: ButtonOptions = .{};
            inline for (@typeInfo(ButtonOptions).@"struct".field_names) |name| @field(cmd_opts, name) = @field(opts, name);

            const button = try Widget.create(p, "menubutton", .{
                .textvariable = var_,
                .indicatoron = true,
                .relief = types.Relief.raised,
                .anchor = types.Anchor.center,
            });
            try button.configure(cmd_opts);
            const menu = try Menu.init(button, .{ .tearoff = false });
            try button.configure(.{ .menu = menu });

            const self: Self = .{ .w = button, .menu = menu, .variable = var_, .command = opts.command };
            try self.addValues(values);
            return self;
        }

        /// 選択肢を置き換える(現在の値はそのまま)。
        pub fn setValues(self: Self, values: []const T) Error!void {
            if (try self.menu.count() > 0) try self.menu.delete(.at(0), .end);
            try self.addValues(values);
        }

        fn addValues(self: Self, values: []const T) Error!void {
            for (values) |v| {
                var buf: [64]u8 = undefined;
                try self.menu.addRadiobutton(T, .{
                    .label = try labelOf(&buf, v),
                    .variable = self.variable,
                    .value = v,
                    .command = self.command,
                });
            }
        }

        fn labelOf(buf: []u8, v: T) Error![]const u8 {
            return switch (@typeInfo(T)) {
                .@"enum" => @tagName(v),
                else => if (T == []const u8) v else std.fmt.bufPrint(buf, "{}", .{v}) catch error.OutOfMemory,
            };
        }
    };
}

/// StringVarと組み合わせる形。
pub const OptionMenu = OptionMenuOf([]const u8);
