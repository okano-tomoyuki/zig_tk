const std = @import("std");
const tcl = @import("../tcl.zig");
const types = @import("../types.zig");
const value = @import("../value.zig");
const widget = @import("../widget.zig");
const PhotoImage = @import("../image.zig").PhotoImage;
const variable = @import("../variable.zig");
const Callback = @import("../callback.zig").Callback;
const interp_mod = @import("../interp.zig");
const Interp = interp_mod.Interp;
const Cmd = interp_mod.Cmd;
const Error = interp_mod.Error;
const Widget = widget.Widget;

/// メニュー(Python tkinter.Menu相当)。メニューバー・プルダウン・ポップアップに使う。
///
///     const menubar = try tk.Menu.init(root, .{});
///     const file = try tk.Menu.init(menubar, .{ .tearoff = false });
///     try file.addCommand(.{ .label = "開く", .accelerator = "Ctrl+O", .command = tk.callback(&app, App.open) });
///     try file.addSeparator();
///     try file.addCommand(.{ .label = "終了", .command = tk.callback(&root, tk.Tk.quit) });
///     try menubar.addCascade(.{ .label = "ファイル", .menu = file });
///     try root.config(.{ .menu = menubar });
///
/// 注意: tearoffが有効だと、先頭(index 0)に切り離し用の項目が入り、追加した項目の番号が1つずれる。
/// 既定値はTkのバージョンで異なる(8.6はtrue、9.0はfalse)ため、明示的に指定するのが確実。
pub const Menu = struct {
    w: Widget,

    /// メニュー項目の位置。
    pub const Index = union(enum) {
        pos: usize,
        /// 最後の項目。
        end,
        /// マウスやキーボードで強調表示中の項目。
        active,
        last,
        /// ラベルがパターン(glob)に一致する最初の項目。
        pattern: []const u8,

        pub fn at(i: usize) Index {
            return .{ .pos = i };
        }

        pub fn label(text: []const u8) Index {
            return .{ .pattern = text };
        }

        pub fn toTclObj(self: Index, interp: *Interp) Error!*tcl.Obj {
            return switch (self) {
                .pos => |i| value.toObj(interp, i),
                .pattern => |p| value.string(p),
                else => value.string(@tagName(self)),
            };
        }
    };

    pub const Options = struct {
        /// 先頭に切り離し用の項目を置くか(既定はTk 8.6がtrue、9.0がfalse)。
        tearoff: ?bool = null,
        /// 切り離したメニューのウィンドウタイトル。
        title: ?[]const u8 = null,
        /// メニューを表示する直前に呼ばれる(項目の更新に使う)。
        postcommand: ?Callback = null,
        font: ?[]const u8 = null,
        foreground: ?[]const u8 = null,
        background: ?[]const u8 = null,
        activeforeground: ?[]const u8 = null,
        activebackground: ?[]const u8 = null,
        disabledforeground: ?[]const u8 = null,
        selectcolor: ?[]const u8 = null,
        relief: ?types.Relief = null,
        borderwidth: ?i32 = null,
        activeborderwidth: ?i32 = null,
        cursor: ?[]const u8 = null,
        takefocus: ?bool = null,
    };

    pub const CommandItemOptions = struct {
        label: ?[]const u8 = null,
        command: ?Callback = null,
        /// 表示だけのショートカット表記(キー割り当て自体はbind等で別途行う)。
        accelerator: ?[]const u8 = null,
        underline: ?i32 = null,
        state: ?types.State = null,
        font: ?[]const u8 = null,
        foreground: ?[]const u8 = null,
        background: ?[]const u8 = null,
        image: ?PhotoImage = null,
        compound: ?types.Compound = null,
    };

    pub const CascadeItemOptions = struct {
        label: ?[]const u8 = null,
        /// 開くサブメニュー(このMenuの子として生成したもの)。
        menu: ?Menu = null,
        underline: ?i32 = null,
        state: ?types.State = null,
        font: ?[]const u8 = null,
        foreground: ?[]const u8 = null,
        background: ?[]const u8 = null,
    };

    /// チェック付き項目。Tはvariableの値の型(tk.CheckbuttonOfと同じ)。
    pub fn CheckItemOptions(comptime T: type) type {
        return struct {
            label: ?[]const u8 = null,
            variable: ?variable.Variable(T) = null,
            onvalue: ?T = null,
            offvalue: ?T = null,
            command: ?Callback = null,
            accelerator: ?[]const u8 = null,
            underline: ?i32 = null,
            state: ?types.State = null,
            /// falseにするとチェック印を表示しない。
            indicatoron: ?bool = null,
            selectcolor: ?[]const u8 = null,
            font: ?[]const u8 = null,
        };
    }

    /// 選択肢の項目。Tはvariable/valueの型(tk.RadiobuttonOfと同じ。enumも使える)。
    pub fn RadioItemOptions(comptime T: type) type {
        return struct {
            label: ?[]const u8 = null,
            variable: ?variable.Variable(T) = null,
            value: ?T = null,
            command: ?Callback = null,
            accelerator: ?[]const u8 = null,
            underline: ?i32 = null,
            state: ?types.State = null,
            indicatoron: ?bool = null,
            selectcolor: ?[]const u8 = null,
            font: ?[]const u8 = null,
        };
    }

    const M = widget.Methods(Menu, Options);
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

    /// parentはメニューバーならTk/Toplevel、サブメニューなら親のMenu。
    pub fn init(parent: anytype, opts: Options) Error!Menu {
        return .{ .w = try .create(widget.asWidget(parent), "menu", opts) };
    }

    pub fn addCommand(self: Menu, opts: CommandItemOptions) Error!void {
        return self.addItem("command", opts);
    }

    pub fn addCascade(self: Menu, opts: CascadeItemOptions) Error!void {
        return self.addItem("cascade", opts);
    }

    pub fn addCheckbutton(self: Menu, comptime T: type, opts: CheckItemOptions(T)) Error!void {
        return self.addItem("checkbutton", opts);
    }

    pub fn addRadiobutton(self: Menu, comptime T: type, opts: RadioItemOptions(T)) Error!void {
        return self.addItem("radiobutton", opts);
    }

    pub fn addSeparator(self: Menu) Error!void {
        _ = try self.w.interp.call(.{ self.w.path, "add", "separator" });
    }

    /// 項目のコールバックは "zt_cb<path>-item<N>-<option>" として登録され、Menuの破棄時に解放される。
    fn addItem(self: Menu, kind: []const u8, opts: anytype) Error!void {
        var cmd: Cmd = .init(self.w.interp);
        defer cmd.deinit();
        try cmd.add(self.w.path);
        try cmd.add("add");
        try cmd.add(kind);
        var owner_buf: [256]u8 = undefined;
        try cmd.addOptions(try self.itemOwner(&owner_buf), opts);
        _ = try cmd.eval();
    }

    /// i番目の項目の設定を変更する。optsは項目の種類に合うOptions(CommandItemOptions等)。
    pub fn entryconfigure(self: Menu, i: Index, opts: anytype) Error!void {
        var cmd: Cmd = .init(self.w.interp);
        defer cmd.deinit();
        try cmd.add(self.w.path);
        try cmd.add("entryconfigure");
        try cmd.add(i);
        var owner_buf: [256]u8 = undefined;
        try cmd.addOptions(try self.itemOwner(&owner_buf), opts);
        _ = try cmd.eval();
    }

    /// i番目の項目のオプション値(例: entrycget(.at(0), "label"))。次のTcl呼び出しまで有効。
    pub fn entrycget(self: Menu, i: Index, option: []const u8) Error![]const u8 {
        var buf: [64]u8 = undefined;
        const name = std.fmt.bufPrint(&buf, "-{s}", .{option}) catch return error.OutOfMemory;
        return self.w.interp.call(.{ self.w.path, "entrycget", i, name });
    }

    /// i番目の項目を実行する(commandを呼び、checkbutton等なら状態を切り替える)。
    pub fn invoke(self: Menu, i: Index) Error!void {
        _ = try self.w.interp.call(.{ self.w.path, "invoke", i });
    }

    /// first〜last(lastを含む)の項目を削除する。
    pub fn delete(self: Menu, first: Index, last: ?Index) Error!void {
        if (last) |l| {
            _ = try self.w.interp.call(.{ self.w.path, "delete", first, l });
        } else {
            _ = try self.w.interp.call(.{ self.w.path, "delete", first });
        }
    }

    /// iを項目番号に解決する。該当する項目が無ければnull。
    pub fn index(self: Menu, i: Index) Error!?usize {
        const result = self.w.interp.call(.{ self.w.path, "index", i }) catch |err| switch (err) {
            // パターンに一致しない場合Tkはエラーを返す
            error.TclError => return null,
            else => return err,
        };
        if (std.mem.eql(u8, result, "none") or result.len == 0) return null;
        return std.fmt.parseInt(usize, result, 10) catch null;
    }

    /// 項目の数(tearoff項目を含む)。
    pub fn count(self: Menu) Error!usize {
        return if (try self.index(.end)) |last| last + 1 else 0;
    }

    /// 画面座標(x_root, y_root)にポップアップ表示する(右クリックメニュー等。Eventのx_root/y_rootを渡す)。
    pub fn popup(self: Menu, x_root: i32, y_root: i32) Error!void {
        _ = try self.w.interp.call(.{ "tk_popup", self.w.path, x_root, y_root });
    }

    pub fn unpost(self: Menu) Error!void {
        _ = try self.w.interp.call(.{ self.w.path, "unpost" });
    }

    fn itemOwner(self: Menu, buf: []u8) Error![]const u8 {
        self.w.interp.next_id += 1;
        return std.fmt.bufPrint(buf, "{s}-item{d}", .{ self.w.path, self.w.interp.next_id }) catch error.OutOfMemory;
    }
};
