const std = @import("std");
const tcl = @import("../tcl.zig");
const types = @import("../types.zig");
const value = @import("../value.zig");
const widget = @import("../widget.zig");
const scroll = @import("../scroll.zig");
const interp_mod = @import("../interp.zig");
const Cmd = interp_mod.Cmd;
const Error = interp_mod.Error;
const Widget = widget.Widget;
const ListIndex = types.ListIndex;

/// classic Tk listbox(Python tkinter.Listbox相当)。
/// 選択が変わると仮想イベント "<<ListboxSelect>>" が発生する(bindで受け取る)。
pub const Listbox = struct {
    w: Widget,

    pub const SelectMode = enum {
        /// 1行だけ。ドラッグで選択行が移動する(既定)。
        browse,
        /// 1行だけ。
        single,
        /// クリックごとに行の選択を切り替える。
        multiple,
        /// Shift/Ctrlで範囲・追加選択できる。
        extended,
    };

    pub const ActiveStyle = enum { dotbox, none, underline };

    pub const Options = struct {
        selectmode: ?SelectMode = null,
        /// 表示する行数。
        height: ?i32 = null,
        /// 表示する幅(平均的な文字数)。
        width: ?i32 = null,
        activestyle: ?ActiveStyle = null,
        xscrollcommand: ?scroll.Setter = null,
        yscrollcommand: ?scroll.Setter = null,
        state: ?types.State = null,
        justify: ?types.Justify = null,
        font: ?[]const u8 = null,
        foreground: ?[]const u8 = null,
        background: ?[]const u8 = null,
        selectforeground: ?[]const u8 = null,
        selectbackground: ?[]const u8 = null,
        disabledforeground: ?[]const u8 = null,
        highlightthickness: ?i32 = null,
        highlightcolor: ?[]const u8 = null,
        highlightbackground: ?[]const u8 = null,
        relief: ?types.Relief = null,
        borderwidth: ?i32 = null,
        exportselection: ?bool = null,
        setgrid: ?bool = null,
        cursor: ?[]const u8 = null,
        takefocus: ?bool = null,
    };

    /// itemconfigureで行ごとに設定できる色。
    pub const ItemOptions = struct {
        foreground: ?[]const u8 = null,
        background: ?[]const u8 = null,
        selectforeground: ?[]const u8 = null,
        selectbackground: ?[]const u8 = null,
    };

    const M = widget.Methods(Listbox, Options);
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

    const X = scroll.XMethods(Listbox);
    pub const xview = X.view;
    pub const xviewMoveto = X.moveto;
    pub const xviewScroll = X.scroll;
    pub const xviewCommand = X.command;

    const Y = scroll.YMethods(Listbox);
    pub const yview = Y.view;
    pub const yviewMoveto = Y.moveto;
    pub const yviewScroll = Y.scroll;
    pub const yviewCommand = Y.command;

    pub fn init(parent: anytype, opts: Options) Error!Listbox {
        return .{ .w = try .create(widget.asWidget(parent), "listbox", opts) };
    }

    /// pos(の前)にlinesを挿入する。
    pub fn insert(self: Listbox, pos: ListIndex, lines: []const []const u8) Error!void {
        var cmd: Cmd = .init(self.w.interp);
        defer cmd.deinit();
        try cmd.add(self.w.path);
        try cmd.add("insert");
        try cmd.add(pos);
        for (lines) |line| try cmd.add(line);
        _ = try cmd.eval();
    }

    /// 末尾に1行追加する。
    pub fn append(self: Listbox, item: []const u8) Error!void {
        return self.insert(.end, &.{item});
    }

    /// first〜last(lastを含む)の行を削除する。lastがnullならfirstの1行のみ。
    pub fn delete(self: Listbox, first: ListIndex, last: ?ListIndex) Error!void {
        if (last) |l| {
            _ = try self.w.interp.call(.{ self.w.path, "delete", first, l });
        } else {
            _ = try self.w.interp.call(.{ self.w.path, "delete", first });
        }
    }

    /// 全行を削除する。
    pub fn clear(self: Listbox) Error!void {
        return self.delete(.at(0), .end);
    }

    /// i行目の文字列。次のTcl呼び出しまで有効。
    pub fn get(self: Listbox, i: ListIndex) Error![]const u8 {
        return self.w.interp.call(.{ self.w.path, "get", i });
    }

    /// 全行をgpaで複製して返す(tk.freeStringsで解放)。
    pub fn items(self: Listbox, gpa: std.mem.Allocator) Error![][]u8 {
        return value.dupeStrings(gpa, try self.w.interp.callList(.{ self.w.path, "get", 0, "end" }));
    }

    /// 行数。
    pub fn size(self: Listbox) Error!usize {
        return parseIndex(try self.w.interp.call(.{ self.w.path, "size" }));
    }

    /// 選択されている行番号(昇順)をgpaで確保して返す。
    pub fn curselection(self: Listbox, gpa: std.mem.Allocator) Error![]usize {
        const objs = try self.w.interp.callList(.{ self.w.path, "curselection" });
        const out = try gpa.alloc(usize, objs.len);
        errdefer gpa.free(out);
        for (objs, out) |obj, *i| i.* = try parseIndex(tcl.getString(obj));
        return out;
    }

    /// 選択されている最初の行。未選択ならnull(single/browseモードで便利)。
    pub fn selectedIndex(self: Listbox) Error!?usize {
        const objs = try self.w.interp.callList(.{ self.w.path, "curselection" });
        return if (objs.len == 0) null else try parseIndex(tcl.getString(objs[0]));
    }

    /// first〜last(lastを含む)を選択に加える。<<ListboxSelect>>は発生しない。
    pub fn selectionSet(self: Listbox, first: ListIndex, last: ?ListIndex) Error!void {
        return self.selection("set", first, last);
    }

    pub fn selectionClear(self: Listbox, first: ListIndex, last: ?ListIndex) Error!void {
        return self.selection("clear", first, last);
    }

    pub fn selectionIncludes(self: Listbox, i: ListIndex) Error!bool {
        return std.mem.eql(u8, try self.w.interp.call(.{ self.w.path, "selection", "includes", i }), "1");
    }

    pub fn selectionAnchor(self: Listbox, i: ListIndex) Error!void {
        _ = try self.w.interp.call(.{ self.w.path, "selection", "anchor", i });
    }

    fn selection(self: Listbox, op: []const u8, first: ListIndex, last: ?ListIndex) Error!void {
        if (last) |l| {
            _ = try self.w.interp.call(.{ self.w.path, "selection", op, first, l });
        } else {
            _ = try self.w.interp.call(.{ self.w.path, "selection", op, first });
        }
    }

    /// キーボード操作の対象行にする。
    pub fn activate(self: Listbox, i: ListIndex) Error!void {
        _ = try self.w.interp.call(.{ self.w.path, "activate", i });
    }

    /// i行目が見えるようにスクロールする。
    pub fn see(self: Listbox, i: ListIndex) Error!void {
        _ = try self.w.interp.call(.{ self.w.path, "see", i });
    }

    /// iを行番号に解決する(.endは行数を返す)。
    pub fn index(self: Listbox, i: ListIndex) Error!usize {
        return parseIndex(try self.w.interp.call(.{ self.w.path, "index", i }));
    }

    /// Widget内のy座標に最も近い行。
    pub fn nearest(self: Listbox, y: i32) Error!usize {
        return parseIndex(try self.w.interp.call(.{ self.w.path, "nearest", y }));
    }

    pub fn itemconfigure(self: Listbox, i: ListIndex, opts: ItemOptions) Error!void {
        var cmd: Cmd = .init(self.w.interp);
        defer cmd.deinit();
        try cmd.add(self.w.path);
        try cmd.add("itemconfigure");
        try cmd.add(i);
        try cmd.addOptions(self.w.path, opts);
        _ = try cmd.eval();
    }

    fn parseIndex(s: []const u8) Error!usize {
        return std.fmt.parseInt(usize, s, 10) catch error.TclError;
    }
};
