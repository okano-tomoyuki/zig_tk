const std = @import("std");
const PhotoImage = @import("../image.zig").PhotoImage;
const tcl = @import("../tcl.zig");
const types = @import("../types.zig");
const value = @import("../value.zig");
const widget = @import("../widget.zig");
const scroll = @import("../scroll.zig");
const callback = @import("../callback.zig");
const interp_mod = @import("../interp.zig");
const Interp = interp_mod.Interp;
const Cmd = interp_mod.Cmd;
const Error = interp_mod.Error;
const Widget = widget.Widget;

/// 複数行テキスト(Python tkinter.Text相当)。
/// 内容が変わると仮想イベント "<<Modified>>"(editModifiedがtrueになった時)が発生する。
pub const Text = struct {
    w: Widget,

    /// 位置の結果(行は1から、文字は0から数える)。
    pub const Pos = struct {
        line: u32,
        char: u32,

        fn parse(s: []const u8) ?Pos {
            const dot = std.mem.indexOfScalar(u8, s, '.') orelse return null;
            return .{
                .line = std.fmt.parseInt(u32, s[0..dot], 10) catch return null,
                .char = std.fmt.parseInt(u32, s[dot + 1 ..], 10) catch return null,
            };
        }
    };

    /// テキスト中の位置。基準位置に修飾子を付けて組み立てる。
    ///
    ///     text.insert(.end, "...")                       // 末尾
    ///     text.get(.at(1, 0), .end)                      // 1行目先頭から末尾まで
    ///     const I = tk.Text.Index;
    ///     text.delete(I.insert.lineStart(), I.insert.lineEnd())   // カーソル行
    ///
    /// 修飾子はTclでは "+Nl +Nc linestart" の順(行→文字→端)に適用される。
    pub const Index = struct {
        base: Base,
        lines: i32 = 0,
        chars: i32 = 0,
        edge: ?Edge = null,

        pub const Base = union(enum) {
            pos: Pos,
            end,
            insert,
            /// マウスポインタ下の文字。
            current,
            mark: []const u8,
            tag_first: []const u8,
            tag_last: []const u8,
        };

        pub const Edge = enum { linestart, lineend, wordstart, wordend };

        pub const end: Index = .{ .base = .end };
        pub const insert: Index = .{ .base = .insert };
        pub const current: Index = .{ .base = .current };

        pub fn at(line: u32, char: u32) Index {
            return .{ .base = .{ .pos = .{ .line = line, .char = char } } };
        }
        pub fn fromPos(p: Pos) Index {
            return .{ .base = .{ .pos = p } };
        }
        pub fn mark(name: []const u8) Index {
            return .{ .base = .{ .mark = name } };
        }
        /// タグが付いた最初の文字(タグが無ければTclエラー)。
        pub fn tagFirst(tag: []const u8) Index {
            return .{ .base = .{ .tag_first = tag } };
        }
        /// タグが付いた最後の文字の次。
        pub fn tagLast(tag: []const u8) Index {
            return .{ .base = .{ .tag_last = tag } };
        }

        pub fn plusChars(self: Index, n: i32) Index {
            var i = self;
            i.chars += n;
            return i;
        }
        pub fn plusLines(self: Index, n: i32) Index {
            var i = self;
            i.lines += n;
            return i;
        }
        pub fn lineStart(self: Index) Index {
            return self.withEdge(.linestart);
        }
        pub fn lineEnd(self: Index) Index {
            return self.withEdge(.lineend);
        }
        pub fn wordStart(self: Index) Index {
            return self.withEdge(.wordstart);
        }
        pub fn wordEnd(self: Index) Index {
            return self.withEdge(.wordend);
        }
        fn withEdge(self: Index, edge: Edge) Index {
            var i = self;
            i.edge = edge;
            return i;
        }

        pub fn toTclObj(self: Index, _: *Interp) Error!*tcl.Obj {
            var buf: [512]u8 = undefined;
            var w: std.Io.Writer = .fixed(&buf);
            writeBase(&w, self.base) catch return error.OutOfMemory;
            if (self.lines != 0) w.print(" {s}{d}l", .{ sign(self.lines), self.lines }) catch return error.OutOfMemory;
            if (self.chars != 0) w.print(" {s}{d}c", .{ sign(self.chars), self.chars }) catch return error.OutOfMemory;
            if (self.edge) |e| w.print(" {t}", .{e}) catch return error.OutOfMemory;
            return value.string(w.buffered());
        }

        fn writeBase(w: *std.Io.Writer, base: Base) std.Io.Writer.Error!void {
            switch (base) {
                .pos => |p| try w.print("{d}.{d}", .{ p.line, p.char }),
                .end, .insert, .current => try w.writeAll(@tagName(base)),
                .mark => |name| try w.writeAll(name),
                .tag_first => |tag| try w.print("{s}.first", .{tag}),
                .tag_last => |tag| try w.print("{s}.last", .{tag}),
            }
        }

        // 負数は {d} が "-" を付けるため、正数にだけ "+" を足す
        fn sign(n: i32) []const u8 {
            return if (n > 0) "+" else "";
        }
    };

    pub const Wrap = enum { none, char, word };

    pub const Options = struct {
        width: ?i32 = null,
        height: ?i32 = null,
        wrap: ?Wrap = null,
        /// Undo/Redoを有効にする。
        undo: ?bool = null,
        maxundo: ?i32 = null,
        autoseparators: ?bool = null,
        state: ?types.State = null,
        xscrollcommand: ?scroll.Setter = null,
        yscrollcommand: ?scroll.Setter = null,
        font: ?[]const u8 = null,
        foreground: ?[]const u8 = null,
        background: ?[]const u8 = null,
        insertbackground: ?[]const u8 = null,
        insertwidth: ?i32 = null,
        blockcursor: ?bool = null,
        selectforeground: ?[]const u8 = null,
        selectbackground: ?[]const u8 = null,
        inactiveselectbackground: ?[]const u8 = null,
        padx: ?i32 = null,
        pady: ?i32 = null,
        spacing1: ?i32 = null,
        spacing2: ?i32 = null,
        spacing3: ?i32 = null,
        /// タブ位置(Tkのtabs指定、例: "1c 2c")。
        tabs: ?[]const u8 = null,
        relief: ?types.Relief = null,
        borderwidth: ?i32 = null,
        highlightthickness: ?i32 = null,
        exportselection: ?bool = null,
        setgrid: ?bool = null,
        cursor: ?[]const u8 = null,
        takefocus: ?bool = null,
    };

    /// tagConfigureで設定できる書式。
    pub const TagOptions = struct {
        foreground: ?[]const u8 = null,
        background: ?[]const u8 = null,
        font: ?[]const u8 = null,
        underline: ?bool = null,
        overstrike: ?bool = null,
        justify: ?types.Justify = null,
        lmargin1: ?i32 = null,
        lmargin2: ?i32 = null,
        rmargin: ?i32 = null,
        spacing1: ?i32 = null,
        spacing2: ?i32 = null,
        spacing3: ?i32 = null,
        /// 上付き(正)/下付き(負)のずらし量。
        offset: ?i32 = null,
        relief: ?types.Relief = null,
        borderwidth: ?i32 = null,
        /// trueにすると文字を表示しない(折りたたみ等)。
        elide: ?bool = null,
        wrap: ?Wrap = null,
        selectforeground: ?[]const u8 = null,
        selectbackground: ?[]const u8 = null,
    };

    pub const SearchOptions = struct {
        backwards: bool = false,
        regexp: bool = false,
        nocase: bool = false,
        /// 検索を打ち切る位置(省略時は末尾/先頭で折り返す)。
        stop: ?Index = null,
    };

    pub const Compare = enum {
        lt,
        le,
        eq,
        ne,
        ge,
        gt,

        fn op(self: Compare) []const u8 {
            return switch (self) {
                .lt => "<",
                .le => "<=",
                .eq => "==",
                .ne => "!=",
                .ge => ">=",
                .gt => ">",
            };
        }
    };

    /// tagNextrange等が返す範囲。
    pub const Range = struct { first: Pos, last: Pos };

    const M = widget.Methods(Text, Options);
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

    const X = scroll.XMethods(Text);
    pub const xview = X.view;
    pub const xviewMoveto = X.moveto;
    pub const xviewScroll = X.scroll;
    pub const xviewCommand = X.command;

    const Y = scroll.YMethods(Text);
    pub const yview = Y.view;
    pub const yviewMoveto = Y.moveto;
    pub const yviewScroll = Y.scroll;
    pub const yviewCommand = Y.command;

    pub fn init(parent: anytype, opts: Options) Error!Text {
        return .{ .w = try .create(widget.asWidget(parent), "text", opts) };
    }

    // ---- 内容 ----

    /// posにtextを挿入する。tagsを付けて挿入することもできる。
    pub fn insert(self: Text, pos: Index, text: []const u8) Error!void {
        _ = try self.w.interp.call(.{ self.w.path, "insert", pos, text });
    }

    pub fn insertTagged(self: Text, pos: Index, text: []const u8, tags: []const []const u8) Error!void {
        _ = try self.w.interp.call(.{ self.w.path, "insert", pos, text, tags });
    }

    /// first〜last(lastを含まない)の文字列。lastがnullならfirstの1文字。次のTcl呼び出しまで有効。
    /// 注意: Textの末尾には常に改行が1つあるため、get(.at(1, 0), .end)は末尾に"\n"が付く。
    pub fn get(self: Text, first: Index, last: ?Index) Error![]const u8 {
        if (last) |l| return self.w.interp.call(.{ self.w.path, "get", first, l });
        return self.w.interp.call(.{ self.w.path, "get", first });
    }

    /// 全文(末尾の自動改行を除く)。次のTcl呼び出しまで有効。
    pub fn content(self: Text) Error![]const u8 {
        return self.get(.at(1, 0), Index.end.plusChars(-1));
    }

    pub fn delete(self: Text, first: Index, last: ?Index) Error!void {
        if (last) |l| {
            _ = try self.w.interp.call(.{ self.w.path, "delete", first, l });
        } else {
            _ = try self.w.interp.call(.{ self.w.path, "delete", first });
        }
    }

    /// 全文を削除する。
    pub fn clear(self: Text) Error!void {
        return self.delete(.at(1, 0), .end);
    }

    /// first〜lastをtextで置き換える。
    pub fn replace(self: Text, first: Index, last: Index, text: []const u8) Error!void {
        _ = try self.w.interp.call(.{ self.w.path, "replace", first, last, text });
    }

    /// iを "行.文字" の位置に解決する。
    pub fn index(self: Text, i: Index) Error!Pos {
        const result = try self.w.interp.call(.{ self.w.path, "index", i });
        return Pos.parse(result) orelse self.w.interp.failWith("unexpected text index");
    }

    pub fn compare(self: Text, a: Index, op: Compare, b: Index) Error!bool {
        return std.mem.eql(u8, try self.w.interp.call(.{ self.w.path, "compare", a, op.op(), b }), "1");
    }

    /// iが見えるようにスクロールする。
    pub fn see(self: Text, i: Index) Error!void {
        _ = try self.w.interp.call(.{ self.w.path, "see", i });
    }

    /// patternをstartから探し、見つかった位置を返す。
    pub fn search(self: Text, pattern: []const u8, start: Index, opts: SearchOptions) Error!?Pos {
        var cmd: Cmd = .init(self.w.interp);
        defer cmd.deinit();
        try cmd.add(self.w.path);
        try cmd.add("search");
        if (opts.backwards) try cmd.add("-backwards");
        if (opts.regexp) try cmd.add("-regexp");
        if (opts.nocase) try cmd.add("-nocase");
        try cmd.add("--");
        try cmd.add(pattern);
        try cmd.add(start);
        if (opts.stop) |stop| try cmd.add(stop);
        const result = try cmd.eval();
        if (result.len == 0) return null;
        return Pos.parse(result) orelse self.w.interp.failWith("unexpected text index");
    }

    pub const ImageAlign = enum { top, center, bottom, baseline };

    pub const ImageOptions = struct {
        /// 行の中での縦位置(既定 center)。
        @"align": ?ImageAlign = null,
        padx: ?i32 = null,
        pady: ?i32 = null,
    };

    /// posに画像を1文字分として挿入する。
    pub fn imageCreate(self: Text, pos: Index, image: PhotoImage, opts: ImageOptions) Error!void {
        var cmd: Cmd = .init(self.w.interp);
        defer cmd.deinit();
        try cmd.add(self.w.path);
        try cmd.add("image");
        try cmd.add("create");
        try cmd.add(pos);
        try cmd.addOptions(self.w.path, .{ .image = image });
        try cmd.addOptions(self.w.path, opts);
        _ = try cmd.eval();
    }

    /// posに既存のWidgetを埋め込む(childはこのTextの子として生成したもの)。
    pub fn windowCreate(self: Text, pos: Index, child: anytype) Error!void {
        _ = try self.w.interp.call(.{ self.w.path, "window", "create", pos, "-window", widget.asWidget(child) });
    }

    // ---- タグ ----

    pub fn tagAdd(self: Text, tag: []const u8, first: Index, last: ?Index) Error!void {
        if (last) |l| {
            _ = try self.w.interp.call(.{ self.w.path, "tag", "add", tag, first, l });
        } else {
            _ = try self.w.interp.call(.{ self.w.path, "tag", "add", tag, first });
        }
    }

    pub fn tagRemove(self: Text, tag: []const u8, first: Index, last: ?Index) Error!void {
        if (last) |l| {
            _ = try self.w.interp.call(.{ self.w.path, "tag", "remove", tag, first, l });
        } else {
            _ = try self.w.interp.call(.{ self.w.path, "tag", "remove", tag, first });
        }
    }

    /// タグそのものを削除する(書式・bindも消える)。
    pub fn tagDelete(self: Text, tag: []const u8) Error!void {
        _ = try self.w.interp.call(.{ self.w.path, "tag", "delete", tag });
    }

    pub fn tagConfigure(self: Text, tag: []const u8, opts: TagOptions) Error!void {
        var cmd: Cmd = .init(self.w.interp);
        defer cmd.deinit();
        try cmd.add(self.w.path);
        try cmd.add("tag");
        try cmd.add("configure");
        try cmd.add(tag);
        try cmd.addOptions(self.w.path, opts);
        _ = try cmd.eval();
    }

    /// タグが付いた文字の上でのイベントにcbを結び付ける。コールバックはTextの破棄時に解放される。
    pub fn tagBind(self: Text, tag: []const u8, sequence: []const u8, cb: callback.EventCallback) Error!void {
        var buf: [512]u8 = undefined;
        const name = std.fmt.bufPrintSentinel(&buf, "zt_bind{s}|tag:{s}|{s}", .{ self.w.path, tag, sequence }, 0) catch
            return error.OutOfMemory;
        try callback.register(self.w.interp, name, cb);
        _ = try self.w.interp.call(.{ self.w.path, "tag", "bind", tag, sequence, .{name} ++ callback.Event.substitutions });
    }

    /// first以降で最初にtagが付いている範囲。無ければnull。
    pub fn tagNextrange(self: Text, tag: []const u8, first: Index) Error!?Range {
        const objs = try self.w.interp.callList(.{ self.w.path, "tag", "nextrange", tag, first });
        if (objs.len != 2) return null;
        return .{
            .first = Pos.parse(tcl.getString(objs[0])) orelse return self.w.interp.failWith("unexpected text index"),
            .last = Pos.parse(tcl.getString(objs[1])) orelse return self.w.interp.failWith("unexpected text index"),
        };
    }

    // ---- マーク ----

    pub fn markSet(self: Text, name: []const u8, pos: Index) Error!void {
        _ = try self.w.interp.call(.{ self.w.path, "mark", "set", name, pos });
    }

    pub fn markUnset(self: Text, name: []const u8) Error!void {
        _ = try self.w.interp.call(.{ self.w.path, "mark", "unset", name });
    }

    // ---- Undo / 変更フラグ ----

    /// 直前の編集を取り消す。取り消せるものが無い場合はerror.TclError。
    pub fn editUndo(self: Text) Error!void {
        _ = try self.w.interp.call(.{ self.w.path, "edit", "undo" });
    }

    pub fn editRedo(self: Text) Error!void {
        _ = try self.w.interp.call(.{ self.w.path, "edit", "redo" });
    }

    /// Undo/Redoの履歴を消去する。
    pub fn editReset(self: Text) Error!void {
        _ = try self.w.interp.call(.{ self.w.path, "edit", "reset" });
    }

    /// Undoの区切りを入れる(autoseparatorsがfalseの時に使う)。
    pub fn editSeparator(self: Text) Error!void {
        _ = try self.w.interp.call(.{ self.w.path, "edit", "separator" });
    }

    /// 最後にsetEditModified(false)してから内容が変わったか。
    pub fn editModified(self: Text) Error!bool {
        return std.mem.eql(u8, try self.w.interp.call(.{ self.w.path, "edit", "modified" }), "1");
    }

    pub fn setEditModified(self: Text, modified: bool) Error!void {
        _ = try self.w.interp.call(.{ self.w.path, "edit", "modified", modified });
    }
};
