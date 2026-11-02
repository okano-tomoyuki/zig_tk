//! 構造体の配列をそのまま表示・編集する表(ttk::treeviewを使う)。
//!
//!     const Person = struct { name: []const u8, age: u32, role: Role, active: bool };
//!     const table = try tk.Table(Person).init(gpa, root, .{ .editable = true });
//!     defer table.deinit();
//!     try table.setRows(&people);
//!
//! 列は行の型のフィールドからcomptimeに作る。見出しをクリックするとその列で並べ替える(もう一度で逆順)。
//! editableなら、セルのダブルクリックで編集できる。入力はフィールドの型に変換して戻す
//! (変換できない入力は確定しない)。enumは選択肢から選び、boolはダブルクリックで切り替える。
//!
//! 使えるフィールドの型: []const u8、整数、浮動小数点数、bool、enum と、それらのoptional(空欄がnull)。
const std = @import("std");
const Allocator = std.mem.Allocator;
const tcl = @import("tcl.zig");
const types = @import("types.zig");
const widget = @import("widget.zig");
const callback = @import("callback.zig");
const interp_mod = @import("interp.zig");
const Error = interp_mod.Error;
const Widget = widget.Widget;
const Treeview = @import("ttk/treeview.zig").Treeview;
const Entry = @import("ttk/entry.zig").Entry;
const Combobox = @import("ttk/combobox.zig").Combobox;

pub fn Table(comptime Row: type) type {
    const info = @typeInfo(Row).@"struct";
    comptime for (info.field_names, info.field_types) |name, T| checkFieldType(Row, name, T);

    return struct {
        const Self = @This();

        /// 表を表示するTreeview。pack/grid/placeやスクロールバーの接続はこのWidgetに対して行う。
        w: Widget,
        gpa: Allocator,
        /// 行の文字列フィールドの複製の置き場(setRowsで作り直す)。
        strings: std.heap.ArenaAllocator,
        rows: std.ArrayList(Row) = .empty,
        columns: []const Field,
        editable: bool,
        sort: ?Sort = null,
        editing: ?Editing = null,
        on_edit: ?OnEdit = null,
        /// 編集できない列(Column.editable = false)。
        locked: std.EnumSet(Field) = .empty,
        /// 浮動小数点数の列の小数の桁数(Column.decimals)。
        decimals: std.EnumArray(Field, ?u8) = .initFill(null),

        /// 行の型のフィールド。
        pub const Field = std.meta.FieldEnum(Row);

        pub const Column = struct {
            field: Field,
            /// 見出しの文字列。nullならフィールド名。
            heading: ?[]const u8 = null,
            width: ?i32 = null,
            /// 文字の寄せ。nullなら数値は右寄せ、それ以外は左寄せ。
            anchor: ?types.Anchor = null,
            /// 浮動小数点数の小数の桁数。nullなら必要なだけ表示する。
            decimals: ?u8 = null,
            /// falseならeditableでもこの列は編集できない。
            editable: bool = true,
        };

        pub const Options = struct {
            /// 表示する列と並び。nullなら全フィールドを宣言順に表示する。
            columns: ?[]const Column = null,
            /// 表示する行数。
            height: ?i32 = null,
            selectmode: ?Treeview.SelectMode = null,
            /// ダブルクリックでセルを編集できるようにする。
            editable: bool = false,
        };

        const Sort = struct { field: Field, descending: bool };
        const Editing = struct { row: usize, field: Field, editor: Widget };
        const OnEdit = struct {
            ctx: ?*anyopaque,
            func: *const fn (ctx: ?*anyopaque, row: usize, field: Field) anyerror!void,
        };

        /// parentの子として表を生成する。deinitで破棄する。
        pub fn init(gpa: Allocator, parent: anytype, opts: Options) Error!*Self {
            const self = try gpa.create(Self);
            errdefer gpa.destroy(self);
            const columns = try gpa.alloc(Field, if (opts.columns) |c| c.len else info.field_names.len);
            errdefer gpa.free(columns);
            if (opts.columns) |cs| {
                for (cs, columns) |c, *f| f.* = c.field;
            } else {
                for (columns, 0..) |*f, i| f.* = @fromBackingInt(@intCast(i));
            }

            var ids: [info.field_names.len][]const u8 = undefined;
            for (columns, 0..) |f, i| ids[i] = @tagName(f);
            const tree = try Treeview.init(parent, .{
                .columns = ids[0..columns.len],
                .show = .headings_only,
                .height = opts.height,
                .selectmode = opts.selectmode,
            });
            errdefer tree.destroy() catch {};
            self.* = .{ .w = tree.w, .gpa = gpa, .strings = .init(gpa), .columns = columns, .editable = opts.editable };

            for (columns, 0..) |f, i| {
                const spec: Column = if (opts.columns) |cs| cs[i] else .{ .field = f };
                try tree.heading(@tagName(f), .{ .text = spec.heading orelse @tagName(f), .command = sortCallback(self, f) });
                try tree.column(@tagName(f), .{ .width = spec.width, .anchor = spec.anchor orelse if (isNumeric(f)) .e else .w });
                if (!spec.editable) self.locked.insert(f);
                self.decimals.set(f, spec.decimals);
            }
            try tree.bind("<Double-1>", callback.callback(self, onDoubleClick));
            return self;
        }

        /// Treeviewを(残っていれば)破棄し、行を解放する。
        pub fn deinit(self: *Self) void {
            if (self.w.winfoExists() catch false) self.w.destroy() catch {};
            self.rows.deinit(self.gpa);
            self.strings.deinit();
            self.gpa.free(self.columns);
            self.gpa.destroy(self);
        }

        pub fn pack(self: *const Self, opts: widget.PackOptions) Error!void {
            return self.w.pack(opts);
        }

        pub fn grid(self: *const Self, opts: widget.GridOptions) Error!void {
            return self.w.grid(opts);
        }

        pub fn place(self: *const Self, opts: widget.PlaceOptions) Error!void {
            return self.w.place(opts);
        }

        /// 表示に使っているTreeview(スクロールバーの接続、タグの色付け等)。
        pub fn treeview(self: *const Self) Treeview {
            return .{ .w = self.w };
        }

        /// 編集されたときにfunc(ctx, 行の位置, フィールド)を呼ぶ。例: table.onEdit(&app, App.edited)
        pub fn onEdit(self: *Self, ctx: anytype, comptime func: fn (@TypeOf(ctx), usize, Field) anyerror!void) void {
            const Wrap = struct {
                fn call(p: ?*anyopaque, row: usize, field: Field) anyerror!void {
                    return func(@ptrCast(@alignCast(p.?)), row, field);
                }
            };
            self.on_edit = .{ .ctx = @ptrCast(@constCast(ctx)), .func = Wrap.call };
        }

        /// 全ての行をrowsで置き換える(文字列フィールドは複製する)。並べ替えの状態は解除される。
        pub fn setRows(self: *Self, rows: []const Row) Error!void {
            try self.endEdit(false);
            self.rows.clearRetainingCapacity();
            _ = self.strings.reset(.retain_capacity);
            try self.rows.ensureTotalCapacity(self.gpa, rows.len);
            for (rows) |r| self.rows.appendAssumeCapacity(try self.copyRow(r));
            self.sort = null;
            try self.updateHeadings();
            try self.rebuild();
        }

        /// 行を末尾に追加し、その位置を返す。
        pub fn append(self: *Self, row: Row) Error!usize {
            try self.rows.append(self.gpa, try self.copyRow(row));
            const i = self.rows.items.len - 1;
            try self.insertItem(i);
            return i;
        }

        /// i番目(表示順)の行を置き換える。
        pub fn set(self: *Self, i: usize, row: Row) Error!void {
            self.rows.items[i] = try self.copyRow(row);
            try self.refreshItem(i);
        }

        /// i番目(表示順)の行を削除する。
        pub fn remove(self: *Self, i: usize) Error!void {
            try self.endEdit(false);
            _ = self.rows.orderedRemove(i);
            try self.rebuild();
        }

        /// 表示順の全ての行(次に変更するまで有効)。文字列フィールドは表が所有する。
        pub fn items(self: *const Self) []const Row {
            return self.rows.items;
        }

        pub fn get(self: *const Self, i: usize) Row {
            return self.rows.items[i];
        }

        pub fn len(self: *const Self) usize {
            return self.rows.items.len;
        }

        /// 選択中の行の位置(表示順、昇順)。gpaで確保して返す。
        pub fn selection(self: *const Self, gpa: Allocator) Error![]usize {
            const sel = try self.treeview().selection(gpa);
            defer gpa.free(sel);
            const out = try gpa.alloc(usize, sel.len);
            errdefer gpa.free(out);
            for (sel, out) |item, *o| o.* = itemIndex(item) orelse return error.TclError;
            std.mem.sort(usize, out, {}, std.sort.asc(usize));
            return out;
        }

        /// i番目の行を選択して見える位置までスクロールする。
        pub fn select(self: *const Self, i: usize) Error!void {
            const item = itemOf(i);
            try self.treeview().selectionSet(&.{item});
            try self.treeview().setFocus(item);
            try self.treeview().see(item);
        }

        /// fieldの列で並べ替える(見出しのクリックと同じ。行の位置も並べ替え後の順になる)。
        pub fn sortBy(self: *Self, field: Field, descending: bool) Error!void {
            try self.endEdit(false);
            switch (field) {
                inline else => |f| {
                    const Cmp = struct {
                        fn less(desc: bool, a: Row, b: Row) bool {
                            const x = @field(a, @tagName(f));
                            const y = @field(b, @tagName(f));
                            return if (desc) lessValue(@TypeOf(x), y, x) else lessValue(@TypeOf(x), x, y);
                        }
                    };
                    std.mem.sort(Row, self.rows.items, descending, Cmp.less);
                },
            }
            self.sort = .{ .field = field, .descending = descending };
            try self.updateHeadings();
            for (0..self.rows.items.len) |i| try self.refreshItem(i);
        }

        fn sortCallback(self: *Self, field: Field) callback.Callback {
            return switch (field) {
                inline else => |f| callback.callback(self, struct {
                    fn toggle(t: *Self) !void {
                        const desc = if (t.sort) |s| s.field == f and !s.descending else false;
                        try t.sortBy(f, desc);
                    }
                }.toggle),
            };
        }

        /// 並べ替え中の列の見出しに ▲/▼ を付ける。
        fn updateHeadings(self: *Self) Error!void {
            const tree = self.treeview();
            for (self.columns) |f| {
                var base_buf: [256]u8 = undefined;
                const base = try self.headingBase(f, &base_buf);
                var buf: [256]u8 = undefined;
                const text = if (self.sort) |s| (if (s.field == f)
                    std.fmt.bufPrint(&buf, "{s} {s}", .{ base, if (s.descending) "▼" else "▲" }) catch base
                else
                    base) else base;
                try tree.heading(@tagName(f), .{ .text = text });
            }
        }

        /// 見出しの文字列から並べ替えの印を除いたもの(bufに複製する)。
        fn headingBase(self: *Self, f: Field, buf: []u8) Error![]const u8 {
            var text = try self.w.interp.call(.{ self.w.path, "heading", @tagName(f), "-text" });
            inline for (.{ " ▲", " ▼" }) |mark| {
                if (std.mem.endsWith(u8, text, mark)) text = text[0 .. text.len - mark.len];
            }
            const n = @min(text.len, buf.len);
            @memcpy(buf[0..n], text[0..n]);
            return buf[0..n];
        }

        // ---- Treeviewとの同期 ----
        // 項目のIDは行の位置("0", "1", ...)。rowsの並びと表示の並びは常に一致させる。

        fn itemOf(i: usize) Treeview.Item {
            var buf: [24]u8 = undefined;
            return Treeview.Item.of(std.fmt.bufPrint(&buf, "{d}", .{i}) catch unreachable) catch unreachable;
        }

        fn itemIndex(item: Treeview.Item) ?usize {
            return std.fmt.parseInt(usize, item.id(), 10) catch null;
        }

        fn rebuild(self: *Self) Error!void {
            try self.treeview().clear();
            for (0..self.rows.items.len) |i| try self.insertItem(i);
        }

        fn insertItem(self: *Self, i: usize) Error!void {
            var texts: Texts = undefined;
            const values = texts.of(self, self.rows.items[i]);
            const item = itemOf(i);
            _ = try self.treeview().insert(.root, .end, .{ .id = item.id(), .values = values });
        }

        fn refreshItem(self: *Self, i: usize) Error!void {
            var texts: Texts = undefined;
            try self.treeview().item(itemOf(i), .{ .values = texts.of(self, self.rows.items[i]) });
        }

        /// 1行分のセルの文字列(スタック上に置く)。
        const Texts = struct {
            buf: [info.field_names.len][64]u8,
            slices: [info.field_names.len][]const u8,

            fn of(self: *Texts, table: *const Self, row: Row) []const []const u8 {
                for (table.columns, 0..) |f, i| self.slices[i] = table.formatCell(row, f, &self.buf[i]);
                return self.slices[0..table.columns.len];
            }
        };

        fn formatCell(self: *const Self, row: Row, f: Field, buf: []u8) []const u8 {
            return switch (f) {
                inline else => |x| formatValue(@FieldType(Row, @tagName(x)), @field(row, @tagName(x)), self.decimals.get(f), buf),
            };
        }

        fn copyRow(self: *Self, row: Row) Error!Row {
            var out = row;
            inline for (info.field_names, info.field_types) |name, T| {
                if (comptime T == []const u8) @field(out, name) = try self.strings.allocator().dupe(u8, @field(row, name));
                if (comptime T == ?[]const u8) {
                    if (@field(row, name)) |s| @field(out, name) = try self.strings.allocator().dupe(u8, s);
                }
            }
            return out;
        }

        fn isNumeric(f: Field) bool {
            return switch (f) {
                inline else => |x| switch (@typeInfo(unwrap(@FieldType(Row, @tagName(x))))) {
                    .int, .float => true,
                    else => false,
                },
            };
        }

        // ---- 編集 ----

        fn onDoubleClick(self: *Self, e: callback.Event) !void {
            if (!self.editable) return;
            const item = (try self.treeview().identifyRow(e.y)) orelse return;
            const row = itemIndex(item) orelse return;
            const col_id = try self.w.interp.call(.{ self.w.path, "identify", "column", e.x, e.y });
            // "#1" から始まる表示上の列番号
            if (col_id.len < 2) return;
            const col = (std.fmt.parseInt(usize, col_id[1..], 10) catch return) -| 1;
            if (col >= self.columns.len) return;
            const field = self.columns[col];
            if (self.locked.contains(field)) return;
            try self.beginEdit(row, field);
        }

        /// i番目の行のfieldの編集を始める(ダブルクリックと同じ)。boolは編集せずに切り替える。
        pub fn beginEdit(self: *Self, row: usize, field: Field) Error!void {
            try self.endEdit(true);
            switch (field) {
                inline else => |f| {
                    const T = @FieldType(Row, @tagName(f));
                    if (T == bool) {
                        @field(self.rows.items[row], @tagName(f)) = !@field(self.rows.items[row], @tagName(f));
                        try self.refreshItem(row);
                        return self.notifyEdit(row, field);
                    }
                    try self.openEditor(row, field, choicesOf(T));
                },
            }
        }

        fn openEditor(self: *Self, row: usize, field: Field, choices: ?[]const []const u8) Error!void {
            try self.treeview().see(itemOf(row));
            const box = try self.w.interp.callList(.{ self.w.path, "bbox", itemOf(row), @tagName(field) });
            if (box.len != 4) return;
            var r: [4]i32 = undefined;
            for (box, &r) |o, *v| v.* = std.fmt.parseInt(i32, tcl.getString(o), 10) catch return;

            var buf: [64]u8 = undefined;
            const current = self.formatCell(self.rows.items[row], field, &buf);
            const editor: Widget = if (choices) |values| blk: {
                const cb = try Combobox.init(self.w, .{ .values = values, .state = .readonly });
                try cb.set(current);
                try cb.bind("<<ComboboxSelected>>", callback.callback(self, onEditorKey));
                break :blk cb.w;
            } else blk: {
                const entry = try Entry.init(self.w, .{});
                try entry.insert(.end, current);
                try entry.selectionRange(.at(0), .end);
                break :blk entry.w;
            };
            self.editing = .{ .row = row, .field = field, .editor = editor };
            try editor.place(.{ .x = r[0], .y = r[1], .width = r[2], .height = r[3] });
            try editor.bind("<Return>", callback.callback(self, onEditorKey));
            try editor.bind("<KP_Enter>", callback.callback(self, onEditorKey));
            try editor.bind("<Escape>", callback.callback(self, onEditorCancel));
            try editor.bind("<FocusOut>", callback.callback(self, onEditorFocusOut));
            _ = try self.w.interp.call(.{ "focus", editor.path });
        }

        fn onEditorKey(self: *Self, _: callback.Event) !void {
            try self.endEdit(true);
        }

        fn onEditorCancel(self: *Self, _: callback.Event) !void {
            try self.endEdit(false);
        }

        fn onEditorFocusOut(self: *Self, _: callback.Event) !void {
            // Comboboxの一覧を開いた時もフォーカスが移るが、その時は閉じない
            const ed = self.editing orelse return;
            const focus = try self.w.interp.call(.{"focus"});
            if (std.mem.startsWith(u8, focus, ed.editor.path)) return;
            try self.endEdit(true);
        }

        /// 編集中なら、commitがtrueなら確定、falseなら取り消して閉じる(Enter/Escapeと同じ)。
        /// 確定できない入力ならベルを鳴らして編集を続ける。編集中でなければ何もしない。
        pub fn endEdit(self: *Self, commit: bool) Error!void {
            const ed = self.editing orelse return;
            if (commit) {
                const text = try self.w.interp.call(.{ ed.editor.path, "get" });
                if (!try self.store(ed.row, ed.field, text)) {
                    _ = try self.w.interp.call(.{"bell"});
                    _ = try self.w.interp.call(.{ "focus", ed.editor.path });
                    return;
                }
            }
            self.editing = null;
            // 実行中のbindから自分自身を破棄しないよう、暇になってから破棄する
            _ = try self.w.interp.call(.{ "after", "idle", .{ "destroy", ed.editor.path } });
            _ = try self.w.interp.call(.{ "focus", self.w.path });
            if (commit) {
                try self.refreshItem(ed.row);
                try self.notifyEdit(ed.row, ed.field);
            }
        }

        /// textをfieldの型に変換してrow番目の行へ入れる。変換できなければfalse。
        fn store(self: *Self, row: usize, field: Field, text: []const u8) Error!bool {
            switch (field) {
                inline else => |f| {
                    const T = @FieldType(Row, @tagName(f));
                    const v = parseValue(T, text, self.strings.allocator()) catch |err| {
                        if (@as(anyerror, err) == error.OutOfMemory) return error.OutOfMemory;
                        return false;
                    };
                    @field(self.rows.items[row], @tagName(f)) = v;
                    return true;
                },
            }
        }

        fn notifyEdit(self: *Self, row: usize, field: Field) Error!void {
            const h = self.on_edit orelse return;
            h.func(h.ctx, row, field) catch |err| {
                var buf: [128]u8 = undefined;
                return self.w.interp.failWith(std.fmt.bufPrint(&buf, "zig_tk: onEdit failed: error.{s}", .{@errorName(err)}) catch "zig_tk: onEdit failed");
            };
        }
    };
}

fn unwrap(comptime T: type) type {
    return if (@typeInfo(T) == .optional) @typeInfo(T).optional.child else T;
}

fn checkFieldType(comptime Row: type, comptime name: []const u8, comptime T: type) void {
    const U = unwrap(T);
    switch (@typeInfo(U)) {
        .int, .float, .bool, .@"enum" => {},
        else => if (U != []const u8)
            @compileError("Table(" ++ @typeName(Row) ++ "): field '" ++ name ++ "' has unsupported type " ++ @typeName(T)),
    }
}

/// enum(とそのoptional)の選択肢。optionalなら先頭に空欄(null)を置く。
fn choicesOf(comptime T: type) ?[]const []const u8 {
    const U = unwrap(T);
    if (@typeInfo(U) != .@"enum") return null;
    const names = comptime blk: {
        const tags = @typeInfo(U).@"enum".field_names;
        const opt = @typeInfo(T) == .optional;
        var out: [tags.len + @intFromBool(opt)][]const u8 = undefined;
        if (opt) out[0] = "";
        for (tags, 0..) |t, i| out[i + @intFromBool(opt)] = t;
        const final = out;
        break :blk final;
    };
    return &names;
}

fn formatValue(comptime T: type, v: T, decimals: ?u8, buf: []u8) []const u8 {
    if (T == []const u8) return v;
    return switch (@typeInfo(T)) {
        .optional => |o| if (v) |x| formatValue(o.child, x, decimals, buf) else "",
        .int => std.fmt.bufPrint(buf, "{d}", .{v}) catch "?",
        .float => (if (decimals) |d| std.fmt.bufPrint(buf, "{d:.[1]}", .{ v, d }) else std.fmt.bufPrint(buf, "{d}", .{v})) catch "?",
        .bool => if (v) "✔" else "",
        .@"enum" => @tagName(v),
        else => unreachable,
    };
}

fn parseValue(comptime T: type, text: []const u8, strings: Allocator) !T {
    if (T == []const u8) return strings.dupe(u8, text);
    const trimmed = std.mem.trim(u8, text, " \t");
    return switch (@typeInfo(T)) {
        .optional => |o| if (trimmed.len == 0) null else try parseValue(o.child, text, strings),
        .int => std.fmt.parseInt(T, trimmed, 10),
        .float => std.fmt.parseFloat(T, trimmed),
        .bool => if (std.mem.eql(u8, trimmed, "true") or std.mem.eql(u8, trimmed, "✔")) true else if (std.mem.eql(u8, trimmed, "false") or trimmed.len == 0) false else error.InvalidCharacter,
        .@"enum" => std.meta.stringToEnum(T, trimmed) orelse error.InvalidCharacter,
        else => unreachable,
    };
}

/// 並べ替えの比較。nullは最小、文字列は辞書順、enumは宣言順。
fn lessValue(comptime T: type, a: T, b: T) bool {
    if (T == []const u8) return std.mem.order(u8, a, b) == .lt;
    return switch (@typeInfo(T)) {
        .optional => |o| if (a) |x| (if (b) |y| lessValue(o.child, x, y) else false) else b != null,
        .int, .float => a < b,
        .bool => !a and b,
        .@"enum" => @backingInt(a) < @backingInt(b),
        else => unreachable,
    };
}

test parseValue {
    const gpa = std.testing.allocator;
    try std.testing.expectEqual(42, try parseValue(u32, " 42 ", gpa));
    try std.testing.expectError(error.InvalidCharacter, parseValue(u32, "x", gpa));
    try std.testing.expectEqual(null, try parseValue(?f64, "", gpa));
    try std.testing.expectEqual(1.5, (try parseValue(?f64, "1.5", gpa)).?);
    const E = enum { a, b };
    try std.testing.expectEqual(E.b, try parseValue(E, "b", gpa));
    try std.testing.expect(lessValue(?u32, null, 0));
    try std.testing.expect(!lessValue(?u32, 1, null));
    try std.testing.expect(lessValue([]const u8, "abc", "abd"));
}

test formatValue {
    var buf: [32]u8 = undefined;
    try std.testing.expectEqualStrings("4.0", formatValue(?f64, 4, 1, &buf));
    try std.testing.expectEqualStrings("4", formatValue(?f64, 4, null, &buf));
    try std.testing.expectEqualStrings("", formatValue(?f64, null, 1, &buf));
}
