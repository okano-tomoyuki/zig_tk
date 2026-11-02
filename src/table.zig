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
//!
//! 行はZig側に持ち、Treeviewには見えている行の分だけ項目を置く(仮想化)。行数が数十万でも、
//! 行の設定・並べ替え・削除・スクロールのTcl呼び出しは見えている行数分で済む。
//! そのため選択・カーソル移動・ホイールでのスクロールはこの型が受け持ち、縦のスクロールバーも内蔵する。
const std = @import("std");
const Allocator = std.mem.Allocator;
const tcl = @import("tcl.zig");
const types = @import("types.zig");
const widget = @import("widget.zig");
const callback = @import("callback.zig");
const interp_mod = @import("interp.zig");
const Error = interp_mod.Error;
const TimerId = interp_mod.TimerId;
const Widget = widget.Widget;
const Treeview = @import("ttk/treeview.zig").Treeview;
const Frame = @import("ttk/frame.zig").Frame;
const Scrollbar = @import("ttk/scrollbar.zig").Scrollbar;
const Entry = @import("ttk/entry.zig").Entry;
const Combobox = @import("ttk/combobox.zig").Combobox;

pub fn Table(comptime Row: type) type {
    const info = @typeInfo(Row).@"struct";
    comptime for (info.field_names, info.field_types) |name, T| checkFieldType(Row, name, T);

    return struct {
        const Self = @This();

        /// 表全体(Treeviewとスクロールバーを入れたFrame)。pack/grid/placeはこのWidgetに対して行う。
        w: Widget,
        tree: Widget,
        scrollbar: Widget,
        gpa: Allocator,
        /// 行の文字列フィールドの複製の置き場(setRowsで作り直す)。
        strings: std.heap.ArenaAllocator,
        rows: std.ArrayList(Row) = .empty,
        /// 行ごとの選択状態(rowsと同じ長さ)。
        selected: std.DynamicBitSetUnmanaged = .{},
        columns: []const Field,
        editable: bool,
        selectmode: Treeview.SelectMode,
        /// 表示している先頭の行。
        top: usize = 0,
        /// 一度に表示できる行数(Treeviewの高さから求める)。
        capacity: usize,
        /// Treeviewに置いている項目の数(項目のIDは "0", "1", ... で、top+IDの行を表示する)。
        shown: usize = 0,
        /// キーボード操作の現在行と、範囲選択の起点。
        cursor: ?usize = null,
        anchor: ?usize = null,
        sort: ?Sort = null,
        editing: ?Editing = null,
        on_edit: ?OnEdit = null,
        on_select: ?OnSelect = null,
        /// 編集できない列(Column.editable = false)。
        locked: std.EnumSet(Field) = .empty,
        /// 浮動小数点数の列の小数の桁数(Column.decimals)。
        decimals: std.EnumArray(Field, ?u8) = .initFill(null),
        pending_layout: ?TimerId = null,

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
            /// 表示する行数(表の高さ)。
            height: i32 = 10,
            /// .extended(既定、Shift/Ctrlで複数選択)、.browse(1行だけ)、.none(選択しない)。
            selectmode: Treeview.SelectMode = .extended,
            /// ダブルクリックでセルを編集できるようにする。
            editable: bool = false,
        };

        const Sort = struct { field: Field, descending: bool };
        const Editing = struct { row: usize, field: Field, editor: Widget };
        const OnEdit = struct {
            ctx: ?*anyopaque,
            func: *const fn (ctx: ?*anyopaque, row: usize, field: Field) anyerror!void,
        };
        const OnSelect = struct {
            ctx: ?*anyopaque,
            func: *const fn (ctx: ?*anyopaque) anyerror!void,
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

            const frame = try Frame.init(parent, .{});
            errdefer frame.destroy() catch {};
            var ids: [info.field_names.len][]const u8 = undefined;
            for (columns, 0..) |f, i| ids[i] = @tagName(f);
            // 選択はこの型が受け持つため、Treeview自身には選択させない
            const tree = try Treeview.init(frame, .{ .columns = ids[0..columns.len], .show = .headings_only, .height = opts.height, .selectmode = .none });
            const sb = try Scrollbar.init(frame, .{});
            try tree.grid(.{ .row = 0, .column = 0, .sticky = .nsew });
            try sb.grid(.{ .row = 0, .column = 1, .sticky = .ns });
            try frame.gridRowconfigure(0, .{ .weight = 1 });
            try frame.gridColumnconfigure(0, .{ .weight = 1 });

            self.* = .{
                .w = frame.w,
                .tree = tree.w,
                .scrollbar = sb.w,
                .gpa = gpa,
                .strings = .init(gpa),
                .columns = columns,
                .editable = opts.editable,
                .selectmode = opts.selectmode,
                .capacity = @intCast(@max(1, opts.height)),
            };

            for (columns, 0..) |f, i| {
                const spec: Column = if (opts.columns) |cs| cs[i] else .{ .field = f };
                try tree.heading(@tagName(f), .{ .text = spec.heading orelse @tagName(f), .command = sortCallback(self, f) });
                try tree.column(@tagName(f), .{ .width = spec.width, .anchor = spec.anchor orelse if (isNumeric(f)) .e else .w });
                if (!spec.editable) self.locked.insert(f);
                self.decimals.set(f, spec.decimals);
            }

            // スクロールバーの -command は "moveto f" / "scroll n units|pages" を付けて呼ばれる
            var name_buf: [256]u8 = undefined;
            const scroll_cmd = std.fmt.bufPrintSentinel(&name_buf, "zt_cb{s}-yview", .{frame.w.path}, 0) catch return error.OutOfMemory;
            try frame.w.interp.createCommand(scroll_cmd, scrollProc, self, null);
            _ = try frame.w.interp.call(.{ sb.w.path, "configure", "-command", scroll_cmd });

            try tree.bind("<Configure>", callback.callback(self, onConfigure));
            try tree.bind("<Double-1>", callback.callback(self, onDoubleClick));
            try tree.bind("<ButtonPress-1>", callback.callback(self, onClick));
            try tree.bind("<Control-ButtonPress-1>", callback.callback(self, onControlClick));
            try tree.bind("<Shift-ButtonPress-1>", callback.callback(self, onShiftClick));
            // 以下はTreeview自身の処理(見えている項目の中だけで動く)を止めて置き換える
            try self.bindBreak("<MouseWheel>", onWheel);
            try self.bindBreak("<Button-4>", onWheelUp);
            try self.bindBreak("<Button-5>", onWheelDown);
            try self.bindBreak("<Up>", onKey);
            try self.bindBreak("<Down>", onKey);
            try self.bindBreak("<Prior>", onKey);
            try self.bindBreak("<Next>", onKey);
            try self.bindBreak("<Home>", onKey);
            try self.bindBreak("<End>", onKey);
            try self.bindBreak("<Shift-Up>", onShiftKey);
            try self.bindBreak("<Shift-Down>", onShiftKey);
            try self.bindBreak("<Shift-Prior>", onShiftKey);
            try self.bindBreak("<Shift-Next>", onShiftKey);
            try self.bindBreak("<Shift-Home>", onShiftKey);
            try self.bindBreak("<Shift-End>", onShiftKey);
            try self.bindBreak("<Control-a>", onSelectAll);
            try self.render();
            return self;
        }

        /// 表を(残っていれば)破棄し、行を解放する。
        pub fn deinit(self: *Self) void {
            if (self.pending_layout) |id| self.w.interp.afterCancel(id);
            if (self.w.winfoExists() catch false) self.w.destroy() catch {};
            self.rows.deinit(self.gpa);
            self.selected.deinit(self.gpa);
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

        /// 表示に使っているTreeview(タグの色付け等)。項目は見えている行の分しか無い点に注意。
        pub fn treeview(self: *const Self) Treeview {
            return .{ .w = self.tree };
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

        /// 利用者の操作で選択が変わったときにfunc(ctx)を呼ぶ(selectionで現在の選択を得る)。
        pub fn onSelect(self: *Self, ctx: anytype, comptime func: fn (@TypeOf(ctx)) anyerror!void) void {
            const Wrap = struct {
                fn call(p: ?*anyopaque) anyerror!void {
                    return func(@ptrCast(@alignCast(p.?)));
                }
            };
            self.on_select = .{ .ctx = @ptrCast(@constCast(ctx)), .func = Wrap.call };
        }

        // ---- 行 ----

        /// 全ての行をrowsで置き換える(文字列フィールドは複製する)。選択と並べ替えの状態は解除される。
        pub fn setRows(self: *Self, rows: []const Row) Error!void {
            try self.endEdit(false);
            self.rows.clearRetainingCapacity();
            _ = self.strings.reset(.retain_capacity);
            try self.rows.ensureTotalCapacity(self.gpa, rows.len);
            for (rows) |r| self.rows.appendAssumeCapacity(try self.copyRow(r));
            try self.selected.resize(self.gpa, rows.len, false);
            self.selected.unsetAll();
            self.top = 0;
            self.cursor = null;
            self.anchor = null;
            self.sort = null;
            try self.updateHeadings();
            try self.render();
        }

        /// 行を末尾に追加し、その位置を返す。
        pub fn append(self: *Self, row: Row) Error!usize {
            try self.rows.append(self.gpa, try self.copyRow(row));
            try self.selected.resize(self.gpa, self.rows.items.len, false);
            try self.render();
            return self.rows.items.len - 1;
        }

        /// i番目(表示順)の行を置き換える。
        pub fn set(self: *Self, i: usize, row: Row) Error!void {
            self.rows.items[i] = try self.copyRow(row);
            try self.render();
        }

        /// i番目(表示順)の行を削除する。
        pub fn remove(self: *Self, i: usize) Error!void {
            try self.endEdit(false);
            _ = self.rows.orderedRemove(i);
            // 選択状態を1行ずつ前へ詰める
            var j = i;
            while (j < self.rows.items.len) : (j += 1) self.selected.setValue(j, self.selected.isSet(j + 1));
            try self.selected.resize(self.gpa, self.rows.items.len, false);
            if (self.cursor) |c| self.cursor = if (c > i) c - 1 else if (c == i) null else c;
            if (self.anchor) |a| self.anchor = if (a > i) a - 1 else if (a == i) null else a;
            try self.render();
        }

        /// 選択中の行を全て削除する(行数に比例する時間で済む)。
        pub fn removeSelected(self: *Self) Error!void {
            try self.endEdit(false);
            var kept: usize = 0;
            for (self.rows.items, 0..) |row, i| {
                if (self.selected.isSet(i)) continue;
                self.rows.items[kept] = row;
                kept += 1;
            }
            self.rows.shrinkRetainingCapacity(kept);
            try self.selected.resize(self.gpa, kept, false);
            self.selected.unsetAll();
            self.cursor = null;
            self.anchor = null;
            try self.render();
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

        // ---- 選択とスクロール ----

        /// 選択中の行の位置(表示順、昇順)。gpaで確保して返す。
        pub fn selection(self: *const Self, gpa: Allocator) Error![]usize {
            const out = try gpa.alloc(usize, self.selected.count());
            var it = self.selected.iterator(.{});
            var k: usize = 0;
            while (it.next()) |i| : (k += 1) out[k] = i;
            return out;
        }

        /// i番目の行だけを選択し、見える位置までスクロールする。
        pub fn select(self: *Self, i: usize) Error!void {
            self.selected.unsetAll();
            if (self.selectmode != .none) self.selected.set(i);
            self.cursor = i;
            self.anchor = i;
            self.scrollIntoView(i);
            try self.render();
        }

        /// 選択を全て解除する。
        pub fn clearSelection(self: *Self) Error!void {
            self.selected.unsetAll();
            try self.render();
        }

        /// i番目の行が見える位置までスクロールする。
        pub fn see(self: *Self, i: usize) Error!void {
            self.scrollIntoView(i);
            try self.render();
        }

        /// 表示している先頭の行をiにする(行数を超えないよう調整する)。
        pub fn scrollTo(self: *Self, i: usize) Error!void {
            if (self.editing != null) try self.endEdit(true);
            self.top = i;
            try self.render();
        }

        fn scrollBy(self: *Self, delta: isize) Error!void {
            const t: isize = @intCast(self.top);
            try self.scrollTo(@intCast(@max(0, t + delta)));
        }

        fn scrollIntoView(self: *Self, i: usize) void {
            if (i < self.top) self.top = i else if (i >= self.top + self.capacity) self.top = i + 1 - self.capacity;
        }

        fn maxTop(self: *const Self) usize {
            return self.rows.items.len -| self.capacity;
        }

        /// スクロールバーの -command。"moveto 0.5" / "scroll 1 units" / "scroll -1 pages"。
        fn scrollProc(client_data: tcl.ClientData, raw: *tcl.Interp, objc: c_int, objv: [*]const *tcl.Obj) callconv(.c) c_int {
            const self: *Self = @ptrCast(@alignCast(client_data.?));
            const args = objv[1..@intCast(objc)];
            self.handleScroll(args) catch {
                const msg = "zig_tk: Table scroll failed";
                tcl.Tcl_SetObjResult(raw, tcl.Tcl_NewStringObj(msg, msg.len));
                return tcl.ERROR;
            };
            return tcl.OK;
        }

        fn handleScroll(self: *Self, args: []const *tcl.Obj) Error!void {
            if (args.len == 2 and std.mem.eql(u8, tcl.getString(args[0]), "moveto")) {
                const f = std.fmt.parseFloat(f64, tcl.getString(args[1])) catch return;
                const n: f64 = @floatFromInt(self.rows.items.len);
                return self.scrollTo(@intFromFloat(@max(0, @round(std.math.clamp(f, 0, 1) * n))));
            }
            if (args.len == 3 and std.mem.eql(u8, tcl.getString(args[0]), "scroll")) {
                const n = std.fmt.parseInt(isize, tcl.getString(args[1]), 10) catch return;
                const page: isize = @intCast(@max(1, self.capacity -| 1));
                return self.scrollBy(if (std.mem.eql(u8, tcl.getString(args[2]), "pages")) n * page else n);
            }
        }

        fn onWheel(self: *Self, e: callback.Event) !void {
            // Windowsでは1目盛り120。それより細かい(タッチパッド等)ものは向きだけ使う
            const notches = if (@abs(e.delta) >= 120) @divTrunc(e.delta, 120) else std.math.sign(e.delta);
            try self.scrollBy(-notches * 3);
        }

        fn onWheelUp(self: *Self, _: callback.Event) !void {
            try self.scrollBy(-3);
        }

        fn onWheelDown(self: *Self, _: callback.Event) !void {
            try self.scrollBy(3);
        }

        fn onKey(self: *Self, e: callback.Event) !void {
            try self.moveCursor(e.keysym, false);
        }

        fn onShiftKey(self: *Self, e: callback.Event) !void {
            try self.moveCursor(e.keysym, self.selectmode == .extended);
        }

        fn moveCursor(self: *Self, keysym: []const u8, extend: bool) Error!void {
            const n = self.rows.items.len;
            if (n == 0) return;
            const page = @max(1, self.capacity -| 1);
            const cur = self.cursor orelse self.top;
            const next: usize = if (std.mem.eql(u8, keysym, "Up"))
                cur -| 1
            else if (std.mem.eql(u8, keysym, "Down"))
                @min(n - 1, if (self.cursor == null) cur else cur + 1)
            else if (std.mem.eql(u8, keysym, "Prior"))
                cur -| page
            else if (std.mem.eql(u8, keysym, "Next"))
                @min(n - 1, cur + page)
            else if (std.mem.eql(u8, keysym, "Home"))
                0
            else if (std.mem.eql(u8, keysym, "End"))
                n - 1
            else
                return;
            try self.endEdit(true);
            self.cursor = next;
            if (self.selectmode != .none) {
                if (extend) {
                    self.selectRange(self.anchor orelse cur, next);
                } else {
                    self.selected.unsetAll();
                    self.selected.set(next);
                    self.anchor = next;
                }
            }
            self.scrollIntoView(next);
            try self.render();
            if (self.selectmode != .none) try self.notifySelect();
        }

        fn selectRange(self: *Self, a: usize, b: usize) void {
            self.selected.unsetAll();
            self.selected.setRangeValue(.{ .start = @min(a, b), .end = @max(a, b) + 1 }, true);
        }

        fn onSelectAll(self: *Self, _: callback.Event) !void {
            if (self.selectmode != .extended) return;
            self.selected.setRangeValue(.{ .start = 0, .end = self.rows.items.len }, true);
            try self.render();
            try self.notifySelect();
        }

        const ClickKind = enum { plain, toggle, range };

        fn onClick(self: *Self, e: callback.Event) !void {
            try self.click(e, .plain);
        }

        fn onControlClick(self: *Self, e: callback.Event) !void {
            try self.click(e, .toggle);
        }

        fn onShiftClick(self: *Self, e: callback.Event) !void {
            try self.click(e, .range);
        }

        fn click(self: *Self, e: callback.Event, kind: ClickKind) Error!void {
            const region = try self.w.interp.call(.{ self.tree.path, "identify", "region", e.x, e.y });
            if (!std.mem.eql(u8, region, "cell") and !std.mem.eql(u8, region, "tree")) return;
            const row = (try self.rowAt(e.y)) orelse return;
            if (self.editing) |ed| if (ed.row != row) try self.endEdit(true);
            self.cursor = row;
            switch (self.selectmode) {
                .none => {},
                .browse => {
                    self.selected.unsetAll();
                    self.selected.set(row);
                    self.anchor = row;
                },
                .extended => switch (kind) {
                    .plain => {
                        self.selected.unsetAll();
                        self.selected.set(row);
                        self.anchor = row;
                    },
                    .toggle => {
                        self.selected.toggle(row);
                        self.anchor = row;
                    },
                    .range => self.selectRange(self.anchor orelse row, row),
                },
            }
            _ = try self.w.interp.call(.{ "focus", self.tree.path });
            try self.render();
            if (self.selectmode != .none) try self.notifySelect();
        }

        /// Treeview上のy座標にある行の位置。
        fn rowAt(self: *Self, y: i32) Error!?usize {
            const item = (try self.treeview().identifyRow(y)) orelse return null;
            const slot = std.fmt.parseInt(usize, item.id(), 10) catch return null;
            const row = self.top + slot;
            return if (row < self.rows.items.len) row else null;
        }

        fn notifySelect(self: *Self) Error!void {
            const h = self.on_select orelse return;
            h.func(h.ctx) catch |err| return self.callbackFailed("onSelect", err);
        }

        // ---- 並べ替え ----

        /// fieldの列で並べ替える(見出しのクリックと同じ)。行の位置も並べ替え後の順になり、選択は行に付いて動く。
        pub fn sortBy(self: *Self, field: Field, descending: bool) Error!void {
            try self.endEdit(false);
            const n = self.rows.items.len;
            // 行と選択状態を同じ順に並べ替えるため、位置の並びを作って並べ替える
            const order = try self.gpa.alloc(usize, n);
            defer self.gpa.free(order);
            for (order, 0..) |*o, i| o.* = i;
            switch (field) {
                inline else => |f| {
                    const Ctx = struct {
                        rows: []const Row,
                        desc: bool,
                        fn less(ctx: @This(), a: usize, b: usize) bool {
                            const x = @field(ctx.rows[a], @tagName(f));
                            const y = @field(ctx.rows[b], @tagName(f));
                            return if (ctx.desc) lessValue(@TypeOf(x), y, x) else lessValue(@TypeOf(x), x, y);
                        }
                    };
                    std.sort.pdq(usize, order, Ctx{ .rows = self.rows.items, .desc = descending }, Ctx.less);
                },
            }
            const sorted = try self.gpa.alloc(Row, n);
            defer self.gpa.free(sorted);
            var sel: std.DynamicBitSetUnmanaged = try .initEmpty(self.gpa, n);
            defer sel.deinit(self.gpa);
            var new_cursor: ?usize = null;
            var new_anchor: ?usize = null;
            for (order, 0..) |old, i| {
                sorted[i] = self.rows.items[old];
                if (self.selected.isSet(old)) sel.set(i);
                if (self.cursor == old) new_cursor = i;
                if (self.anchor == old) new_anchor = i;
            }
            @memcpy(self.rows.items, sorted);
            std.mem.swap(std.DynamicBitSetUnmanaged, &self.selected, &sel);
            self.cursor = new_cursor;
            self.anchor = new_anchor;
            self.sort = .{ .field = field, .descending = descending };
            try self.updateHeadings();
            try self.render();
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
            var text = try self.w.interp.call(.{ self.tree.path, "heading", @tagName(f), "-text" });
            inline for (.{ " ▲", " ▼" }) |mark| {
                if (std.mem.endsWith(u8, text, mark)) text = text[0 .. text.len - mark.len];
            }
            const n = @min(text.len, buf.len);
            @memcpy(buf[0..n], text[0..n]);
            return buf[0..n];
        }

        // ---- 表示 ----

        fn slotItem(slot: usize) Treeview.Item {
            var buf: [24]u8 = undefined;
            return Treeview.Item.of(std.fmt.bufPrint(&buf, "{d}", .{slot}) catch unreachable) catch unreachable;
        }

        /// 見えている行をTreeviewの項目へ反映する。Tclの呼び出しは表示できる行数分だけ。
        fn render(self: *Self) Error!void {
            const tree = self.treeview();
            const n = self.rows.items.len;
            self.top = @min(self.top, self.maxTop());
            const want = @min(self.capacity, n - self.top);
            while (self.shown > want) {
                self.shown -= 1;
                try tree.delete(&.{slotItem(self.shown)});
            }
            var visible_sel: std.ArrayList(Treeview.Item) = .empty;
            defer visible_sel.deinit(self.gpa);
            for (0..want) |slot| {
                const row = self.top + slot;
                var texts: Texts = undefined;
                const values = texts.of(self, self.rows.items[row]);
                const item = slotItem(slot);
                if (slot < self.shown) {
                    try tree.item(item, .{ .values = values });
                } else {
                    _ = try tree.insert(.root, .end, .{ .id = item.id(), .values = values });
                }
                if (self.selected.isSet(row)) try visible_sel.append(self.gpa, item);
            }
            self.shown = want;
            try tree.selectionSet(visible_sel.items);
            if (self.cursor) |c| if (c >= self.top and c < self.top + want) try tree.setFocus(slotItem(c - self.top));

            // スクロールバーのつまみ: 全体のうち見えている範囲
            const total: f64 = @floatFromInt(@max(n, 1));
            const first: f64 = @as(f64, @floatFromInt(self.top)) / total;
            const last: f64 = if (n == 0) 1 else @as(f64, @floatFromInt(self.top + want)) / total;
            _ = try self.w.interp.call(.{ self.scrollbar.path, "set", first, last });
        }

        fn onConfigure(self: *Self, _: callback.Event) !void {
            if (self.pending_layout != null) return;
            self.pending_layout = try self.w.interp.afterIdle(callback.callback(self, layout));
        }

        /// Treeviewの高さから表示できる行数を求め直す(大きさが変わった時)。
        fn layout(self: *Self) !void {
            self.pending_layout = null;
            if (!try self.tree.winfoExists()) return;
            // 1行目の項目の位置と高さを測る(行が無ければ一時的に項目を置く)
            const probe = self.shown == 0;
            if (probe) _ = try self.treeview().insert(.root, .end, .{ .id = "0" });
            var box: [4]i32 = undefined;
            const objs = try self.w.interp.callList(.{ self.tree.path, "bbox", "0" });
            const measured = objs.len == 4;
            if (measured) {
                for (objs, &box) |o, *v| v.* = std.fmt.parseInt(i32, tcl.getString(o), 10) catch 0;
            }
            if (probe) try self.treeview().delete(&.{slotItem(0)});
            if (!measured) return;
            const y0 = box[1];
            const h = box[3];
            const height = try self.tree.winfo(.height);
            if (h <= 0 or height <= y0) return;
            // 下端の余白(テーマにより1〜数ピクセル)は左端の余白(bboxのx)と同じ。途切れる行は数えない
            const fits: usize = @intCast(@max(1, @divTrunc(height - y0 - box[0], h)));
            if (fits == self.capacity) return;
            self.capacity = fits;
            try self.render();
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

        /// Treeview自身のbind(見えている項目の中だけで動く)を止めて、cbだけを実行するbind。
        fn bindBreak(self: *Self, comptime sequence: []const u8, comptime func: fn (*Self, callback.Event) anyerror!void) Error!void {
            var buf: [256]u8 = undefined;
            // widget.bindと同じ名前の規則にして、破棄時にまとめて解放されるようにする
            const name = std.fmt.bufPrintSentinel(&buf, "zt_bind{s}|{s}", .{ self.tree.path, sequence }, 0) catch return error.OutOfMemory;
            try callback.register(self.w.interp, name, callback.callback(self, func));
            var script_buf: [512]u8 = undefined;
            const subs = comptime blk: {
                var s: []const u8 = "";
                for (callback.Event.substitutions) |sub| s = s ++ " " ++ sub;
                break :blk s;
            };
            const script = std.fmt.bufPrint(&script_buf, "{s}{s}; break", .{ name, subs }) catch return error.OutOfMemory;
            _ = try self.w.interp.call(.{ "bind", self.tree.path, sequence, script });
        }

        // ---- 編集 ----

        fn onDoubleClick(self: *Self, e: callback.Event) !void {
            if (!self.editable) return;
            const row = (try self.rowAt(e.y)) orelse return;
            const col_id = try self.w.interp.call(.{ self.tree.path, "identify", "column", e.x, e.y });
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
                        try self.render();
                        return self.notifyEdit(row, field);
                    }
                    try self.openEditor(row, field, choicesOf(T));
                },
            }
        }

        fn openEditor(self: *Self, row: usize, field: Field, choices: ?[]const []const u8) Error!void {
            try self.see(row);
            const box = try self.w.interp.callList(.{ self.tree.path, "bbox", slotItem(row - self.top), @tagName(field) });
            if (box.len != 4) return;
            var r: [4]i32 = undefined;
            for (box, &r) |o, *v| v.* = std.fmt.parseInt(i32, tcl.getString(o), 10) catch return;

            var buf: [64]u8 = undefined;
            const current = self.formatCell(self.rows.items[row], field, &buf);
            const editor: Widget = if (choices) |values| blk: {
                const cb = try Combobox.init(self.tree, .{ .values = values, .state = .readonly });
                try cb.set(current);
                try cb.bind("<<ComboboxSelected>>", callback.callback(self, onEditorKey));
                break :blk cb.w;
            } else blk: {
                const entry = try Entry.init(self.tree, .{});
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
            _ = try self.w.interp.call(.{ "focus", self.tree.path });
            if (commit) {
                try self.render();
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
            h.func(h.ctx, row, field) catch |err| return self.callbackFailed("onEdit", err);
        }

        fn callbackFailed(self: *Self, comptime what: []const u8, err: anyerror) Error {
            var buf: [128]u8 = undefined;
            return self.w.interp.failWith(std.fmt.bufPrint(&buf, "zig_tk: " ++ what ++ " failed: error.{s}", .{@errorName(err)}) catch "zig_tk: " ++ what ++ " failed");
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
