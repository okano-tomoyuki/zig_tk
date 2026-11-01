const std = @import("std");
const tcl = @import("../tcl.zig");
const types = @import("../types.zig");
const value = @import("../value.zig");
const widget = @import("../widget.zig");
const PhotoImage = @import("../image.zig").PhotoImage;
const common = @import("common.zig");
const scroll = @import("../scroll.zig");
const callback = @import("../callback.zig");
const interp_mod = @import("../interp.zig");
const Interp = interp_mod.Interp;
const Cmd = interp_mod.Cmd;
const Error = interp_mod.Error;
const Widget = widget.Widget;

/// ttk::treeview(Python tkinter.ttk.Treeview相当)。表形式・木構造のどちらにも使える。
/// 仮想イベント "<<TreeviewSelect>>" "<<TreeviewOpen>>" "<<TreeviewClose>>" が発生する。
///
///     const tv = try tk.ttk.Treeview.init(root, .{ .columns = &.{ "size", "kind" }, .show = .tree_headings });
///     try tv.heading(tk.ttk.Treeview.tree_column, .{ .text = "Name" });
///     const dir = try tv.insert(.root, .end, .{ .text = "src", .open = true });
///     _ = try tv.insert(dir, .end, .{ .text = "main.zig", .values = &.{ "1 KB", "zig" } });
pub const Treeview = struct {
    w: Widget,

    /// 項目のID(iid)。確保領域を持たない値型で、自由にコピー・保持できる。
    pub const Item = struct {
        buf: [max_len]u8 = undefined,
        len: u8 = 0,

        pub const max_len = 47;

        /// 木の根(親を指定する時の最上位)。
        pub const root: Item = .{};

        /// 文字列のIDから作る(insertの.idで指定したもの等)。max_lenを超える場合はerror.TclError。
        pub fn of(s: []const u8) error{TclError}!Item {
            if (s.len > max_len) return error.TclError;
            var result: Item = .{ .len = @intCast(s.len) };
            @memcpy(result.buf[0..s.len], s);
            return result;
        }

        pub fn id(self: *const Item) []const u8 {
            return self.buf[0..self.len];
        }

        pub fn eql(a: Item, b: Item) bool {
            return std.mem.eql(u8, a.id(), b.id());
        }

        pub fn toTclObj(self: Item, _: *Interp) Error!*tcl.Obj {
            return value.string(self.id());
        }
    };

    /// 木の列(1列目、項目のtextを表示する列)の列ID。
    pub const tree_column = "#0";

    /// -show。木の列と見出し行のどちらを表示するか。
    pub const Show = struct {
        tree: bool = false,
        headings: bool = false,

        pub const tree_headings: Show = .{ .tree = true, .headings = true };
        pub const tree_only: Show = .{ .tree = true };
        pub const headings_only: Show = .{ .headings = true };

        pub fn toTclObj(self: Show, interp: *Interp) Error!*tcl.Obj {
            if (self.tree and self.headings) return value.toObj(interp, .{ "tree", "headings" });
            if (self.tree) return value.string("tree");
            if (self.headings) return value.string("headings");
            return value.string("");
        }
    };

    pub const SelectMode = enum { extended, browse, none };

    pub const Options = struct {
        /// 木の列以外の列ID(値はinsertの.valuesで列の順に与える)。
        columns: ?[]const []const u8 = null,
        /// 表示する列とその順序(省略時は全列)。
        displaycolumns: ?[]const []const u8 = null,
        show: ?Show = null,
        selectmode: ?SelectMode = null,
        /// 表示する行数。
        height: ?i32 = null,
        padding: ?types.Padding = null,
        xscrollcommand: ?scroll.Setter = null,
        yscrollcommand: ?scroll.Setter = null,
        style: ?[]const u8 = null,
        cursor: ?[]const u8 = null,
        takefocus: ?bool = null,
    };

    /// insert/itemで設定する項目の内容。
    pub const ItemOptions = struct {
        /// 木の列に表示する文字列。
        text: ?[]const u8 = null,
        image: ?PhotoImage = null,
        /// columnsの順の各列の値。
        values: ?[]const []const u8 = null,
        /// 子を展開して表示するか。
        open: ?bool = null,
        tags: ?[]const []const u8 = null,
    };

    pub const InsertOptions = struct {
        /// 項目のIDを指定する(省略時はTkが "I001" 等を割り当てる)。Item.max_len以下。
        id: ?[]const u8 = null,
        text: ?[]const u8 = null,
        image: ?PhotoImage = null,
        values: ?[]const []const u8 = null,
        open: ?bool = null,
        tags: ?[]const []const u8 = null,
    };

    pub const HeadingOptions = struct {
        text: ?[]const u8 = null,
        image: ?PhotoImage = null,
        anchor: ?types.Anchor = null,
        /// 見出しをクリックした時に呼ばれる(並べ替え等)。Treeviewの破棄時に解放される。
        command: ?callback.Callback = null,
    };

    pub const ColumnOptions = struct {
        width: ?i32 = null,
        minwidth: ?i32 = null,
        /// ウィンドウの伸縮に合わせて幅を変えるか。
        stretch: ?bool = null,
        anchor: ?types.Anchor = null,
    };

    pub const TagOptions = struct {
        foreground: ?[]const u8 = null,
        background: ?[]const u8 = null,
        font: ?[]const u8 = null,
    };

    /// insertの位置。
    pub const Position = union(enum) {
        pos: usize,
        end,

        pub fn at(i: usize) Position {
            return .{ .pos = i };
        }

        pub fn toTclObj(self: Position, interp: *Interp) Error!*tcl.Obj {
            return switch (self) {
                .pos => |i| value.toObj(interp, i),
                .end => value.string("end"),
            };
        }
    };

    const M = widget.Methods(Treeview, Options);
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

    const S = common.Methods(Treeview);
    pub const setState = S.setState;
    pub const instate = S.instate;

    const X = scroll.XMethods(Treeview);
    pub const xview = X.view;
    pub const xviewMoveto = X.moveto;
    pub const xviewScroll = X.scroll;
    pub const xviewCommand = X.command;

    const Y = scroll.YMethods(Treeview);
    pub const yview = Y.view;
    pub const yviewMoveto = Y.moveto;
    pub const yviewScroll = Y.scroll;
    pub const yviewCommand = Y.command;

    pub fn init(master: anytype, opts: Options) Error!Treeview {
        return .{ .w = try .create(widget.asWidget(master), "ttk::treeview", opts) };
    }

    // ---- 列 ----

    /// 列の見出しを設定する(columnは列IDまたはtree_column)。
    pub fn heading(self: Treeview, column_id: []const u8, opts: HeadingOptions) Error!void {
        var owner_buf: [256]u8 = undefined;
        // コールバック名 "zt_cb<path>-heading-<column>-command" はTreeviewの破棄時に解放される
        const owner = std.fmt.bufPrint(&owner_buf, "{s}-heading-{s}", .{ self.w.path, column_id }) catch return error.OutOfMemory;
        var cmd: Cmd = .init(self.w.interp);
        defer cmd.deinit();
        try cmd.add(self.w.path);
        try cmd.add("heading");
        try cmd.add(column_id);
        try cmd.addOptions(owner, opts);
        _ = try cmd.eval();
    }

    /// 列の幅・配置を設定する。
    pub fn column(self: Treeview, column_id: []const u8, opts: ColumnOptions) Error!void {
        var cmd: Cmd = .init(self.w.interp);
        defer cmd.deinit();
        try cmd.add(self.w.path);
        try cmd.add("column");
        try cmd.add(column_id);
        try cmd.addOptions(self.w.path, opts);
        _ = try cmd.eval();
    }

    // ---- 項目 ----

    /// parentの子としてposの位置に項目を追加し、そのIDを返す。
    pub fn insert(self: Treeview, parent_item: Item, pos: Position, opts: InsertOptions) Error!Item {
        var cmd: Cmd = .init(self.w.interp);
        defer cmd.deinit();
        try cmd.add(self.w.path);
        try cmd.add("insert");
        try cmd.add(parent_item);
        try cmd.add(pos);
        try cmd.addOptions(self.w.path, opts);
        return self.toItem(try cmd.eval());
    }

    /// 項目の内容を変更する。
    pub fn item(self: Treeview, target: Item, opts: ItemOptions) Error!void {
        var cmd: Cmd = .init(self.w.interp);
        defer cmd.deinit();
        try cmd.add(self.w.path);
        try cmd.add("item");
        try cmd.add(target);
        try cmd.addOptions(self.w.path, opts);
        _ = try cmd.eval();
    }

    /// 項目のtext。次のTcl呼び出しまで有効。
    pub fn itemText(self: Treeview, target: Item) Error![]const u8 {
        return self.w.interp.call(.{ self.w.path, "item", target, "-text" });
    }

    /// 項目の各列の値をgpaで複製して返す(tk.freeStringsで解放)。
    pub fn itemValues(self: Treeview, gpa: std.mem.Allocator, target: Item) Error![][]u8 {
        return value.dupeStrings(gpa, try self.w.interp.callList(.{ self.w.path, "item", target, "-values" }));
    }

    /// 項目のcolumn列の値。次のTcl呼び出しまで有効。
    pub fn getValue(self: Treeview, target: Item, column_id: []const u8) Error![]const u8 {
        return self.w.interp.call(.{ self.w.path, "set", target, column_id });
    }

    pub fn setValue(self: Treeview, target: Item, column_id: []const u8, text: []const u8) Error!void {
        _ = try self.w.interp.call(.{ self.w.path, "set", target, column_id, text });
    }

    /// 項目(と子孫)を削除する。
    pub fn delete(self: Treeview, targets: []const Item) Error!void {
        _ = try self.w.interp.call(.{ self.w.path, "delete", targets });
    }

    /// 全項目を削除する。
    pub fn clear(self: Treeview) Error!void {
        const objs = try self.w.interp.callList(.{ self.w.path, "children", Item.root });
        if (objs.len == 0) return;
        const list = tcl.Tcl_GetObjResult(self.w.interp.raw);
        tcl.incrRefCount(list);
        defer tcl.decrRefCount(list);
        _ = try self.w.interp.call(.{ self.w.path, "delete", list });
    }

    /// 項目を木から外す(削除はせず、moveで戻せる)。
    pub fn detach(self: Treeview, targets: []const Item) Error!void {
        _ = try self.w.interp.call(.{ self.w.path, "detach", targets });
    }

    /// 項目をnew_parentの子のpos番目へ移動する。
    pub fn move(self: Treeview, target: Item, new_parent: Item, pos: Position) Error!void {
        _ = try self.w.interp.call(.{ self.w.path, "move", target, new_parent, pos });
    }

    pub fn exists(self: Treeview, target: Item) Error!bool {
        return std.mem.eql(u8, try self.w.interp.call(.{ self.w.path, "exists", target }), "1");
    }

    /// 親項目(最上位ならItem.root)。
    pub fn parent(self: Treeview, target: Item) Error!Item {
        return self.toItem(try self.w.interp.call(.{ self.w.path, "parent", target }));
    }

    /// 子項目をgpaで確保して返す。
    pub fn children(self: Treeview, gpa: std.mem.Allocator, target: Item) Error![]Item {
        return self.toItems(gpa, try self.w.interp.callList(.{ self.w.path, "children", target }));
    }

    /// 兄弟の中での位置。
    pub fn index(self: Treeview, target: Item) Error!usize {
        const result = try self.w.interp.call(.{ self.w.path, "index", target });
        return std.fmt.parseInt(usize, result, 10) catch self.w.interp.failWith("unexpected treeview index");
    }

    /// 次の兄弟。無ければnull。
    pub fn next(self: Treeview, target: Item) Error!?Item {
        return self.optionalItem(try self.w.interp.call(.{ self.w.path, "next", target }));
    }

    /// 前の兄弟。無ければnull。
    pub fn prev(self: Treeview, target: Item) Error!?Item {
        return self.optionalItem(try self.w.interp.call(.{ self.w.path, "prev", target }));
    }

    /// 項目が見えるよう親を展開してスクロールする。
    pub fn see(self: Treeview, target: Item) Error!void {
        _ = try self.w.interp.call(.{ self.w.path, "see", target });
    }

    /// Widget内のy座標にある項目。無ければnull。
    pub fn identifyRow(self: Treeview, y: i32) Error!?Item {
        return self.optionalItem(try self.w.interp.call(.{ self.w.path, "identify", "row", 0, y }));
    }

    // ---- フォーカス・選択 ----

    /// キーボード操作の対象項目。無ければnull。
    pub fn focus(self: Treeview) Error!?Item {
        return self.optionalItem(try self.w.interp.call(.{ self.w.path, "focus" }));
    }

    pub fn setFocus(self: Treeview, target: Item) Error!void {
        _ = try self.w.interp.call(.{ self.w.path, "focus", target });
    }

    /// 選択中の項目をgpaで確保して返す。
    pub fn selection(self: Treeview, gpa: std.mem.Allocator) Error![]Item {
        return self.toItems(gpa, try self.w.interp.callList(.{ self.w.path, "selection" }));
    }

    /// 選択をtargetsに置き換える。(項目のリストは1つのTclリスト引数として渡す)
    pub fn selectionSet(self: Treeview, targets: []const Item) Error!void {
        _ = try self.w.interp.call(.{ self.w.path, "selection", "set", targets });
    }

    pub fn selectionAdd(self: Treeview, targets: []const Item) Error!void {
        _ = try self.w.interp.call(.{ self.w.path, "selection", "add", targets });
    }

    pub fn selectionRemove(self: Treeview, targets: []const Item) Error!void {
        _ = try self.w.interp.call(.{ self.w.path, "selection", "remove", targets });
    }

    pub fn selectionToggle(self: Treeview, targets: []const Item) Error!void {
        _ = try self.w.interp.call(.{ self.w.path, "selection", "toggle", targets });
    }

    // ---- タグ ----

    pub fn tagConfigure(self: Treeview, tag: []const u8, opts: TagOptions) Error!void {
        var cmd: Cmd = .init(self.w.interp);
        defer cmd.deinit();
        try cmd.add(self.w.path);
        try cmd.add("tag");
        try cmd.add("configure");
        try cmd.add(tag);
        try cmd.addOptions(self.w.path, opts);
        _ = try cmd.eval();
    }

    pub fn tagHas(self: Treeview, tag: []const u8, target: Item) Error!bool {
        return std.mem.eql(u8, try self.w.interp.call(.{ self.w.path, "tag", "has", tag, target }), "1");
    }

    /// tagが付いた項目上でのイベントにcbを結び付ける。コールバックはTreeviewの破棄時に解放される。
    pub fn tagBind(self: Treeview, tag: []const u8, sequence: []const u8, cb: callback.EventCallback) Error!void {
        var buf: [512]u8 = undefined;
        const name = std.fmt.bufPrintSentinel(&buf, "zt_bind{s}|tag:{s}|{s}", .{ self.w.path, tag, sequence }, 0) catch
            return error.OutOfMemory;
        try callback.register(self.w.interp, name, cb);
        _ = try self.w.interp.call(.{ self.w.path, "tag", "bind", tag, sequence, .{name} ++ callback.Event.substitutions });
    }

    // ---- 内部 ----

    fn toItem(self: Treeview, s: []const u8) Error!Item {
        return Item.of(s) catch self.w.interp.failWith("treeview item id is longer than Item.max_len");
    }

    fn optionalItem(self: Treeview, s: []const u8) Error!?Item {
        return if (s.len == 0) null else try self.toItem(s);
    }

    fn toItems(self: Treeview, gpa: std.mem.Allocator, objs: []const *tcl.Obj) Error![]Item {
        const out = try gpa.alloc(Item, objs.len);
        errdefer gpa.free(out);
        for (objs, out) |obj, *it| it.* = try self.toItem(tcl.getString(obj));
        return out;
    }
};
