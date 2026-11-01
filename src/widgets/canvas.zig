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

/// 図形描画領域(Python tkinter.Canvas相当)。
///
/// 操作対象(target)には次のいずれかを渡せる:
///   - create*が返すItemId
///   - タグ名の文字列(そのタグが付いた全アイテム)
///   - .all(全アイテム) / .current(マウスポインタ下のアイテム)
///
///     const rect = try canvas.createRectangle(.{ .x1 = 10, .y1 = 10, .x2 = 60, .y2 = 40 }, .{ .fill = "red", .tags = &.{"shape"} });
///     try canvas.move(rect, 5, 0);
///     try canvas.itemconfigure("shape", tk.Canvas.ShapeOptions{ .outline = "blue" });
///     try canvas.delete(.all);
pub const Canvas = struct {
    w: Widget,

    /// アイテムのID(create*の戻り値)。
    pub const ItemId = enum(u32) {
        _,

        pub fn toTclObj(self: ItemId, _: *Interp) Error!*tcl.Obj {
            return tcl.Tcl_NewWideIntObj(@intFromEnum(self));
        }
    };

    pub const Point = struct {
        x: f64,
        y: f64,
    };

    /// 矩形領域(左上x1,y1と右下x2,y2)。
    pub const Box = struct {
        x1: f64,
        y1: f64,
        x2: f64,
        y2: f64,

        pub fn toTclObj(self: Box, interp: *Interp) Error!*tcl.Obj {
            return value.toObj(interp, .{ self.x1, self.y1, self.x2, self.y2 });
        }
    };

    pub const ItemState = enum { normal, disabled, hidden };
    pub const Arrow = enum { none, first, last, both };
    pub const CapStyle = enum { butt, projecting, round };
    pub const JoinStyle = enum { bevel, miter, round };
    pub const ArcStyle = enum { pieslice, chord, arc };

    pub const Options = struct {
        width: ?i32 = null,
        height: ?i32 = null,
        background: ?[]const u8 = null,
        /// スクロールできる範囲(キャンバス座標)。
        scrollregion: ?Box = null,
        /// trueならscrollregionの外へはスクロールしない。
        confine: ?bool = null,
        xscrollcommand: ?scroll.Setter = null,
        yscrollcommand: ?scroll.Setter = null,
        xscrollincrement: ?i32 = null,
        yscrollincrement: ?i32 = null,
        /// アイテムに「近い」と見なす距離(既定 1.0)。
        closeenough: ?f64 = null,
        state: ?ItemState = null,
        relief: ?types.Relief = null,
        borderwidth: ?i32 = null,
        highlightthickness: ?i32 = null,
        cursor: ?[]const u8 = null,
        takefocus: ?bool = null,
    };

    /// 矩形(rectangle)・楕円(oval)のオプション。
    pub const ShapeOptions = struct {
        fill: ?[]const u8 = null,
        outline: ?[]const u8 = null,
        width: ?f64 = null,
        /// 破線パターン(例: "-" "." "4 2")。
        dash: ?[]const u8 = null,
        activefill: ?[]const u8 = null,
        activeoutline: ?[]const u8 = null,
        disabledfill: ?[]const u8 = null,
        tags: ?[]const []const u8 = null,
        state: ?ItemState = null,
    };

    pub const PolygonOptions = struct {
        fill: ?[]const u8 = null,
        outline: ?[]const u8 = null,
        width: ?f64 = null,
        dash: ?[]const u8 = null,
        /// 頂点をなめらかな曲線でつなぐ。
        smooth: ?bool = null,
        joinstyle: ?JoinStyle = null,
        activefill: ?[]const u8 = null,
        activeoutline: ?[]const u8 = null,
        tags: ?[]const []const u8 = null,
        state: ?ItemState = null,
    };

    pub const LineOptions = struct {
        fill: ?[]const u8 = null,
        width: ?f64 = null,
        dash: ?[]const u8 = null,
        arrow: ?Arrow = null,
        capstyle: ?CapStyle = null,
        joinstyle: ?JoinStyle = null,
        smooth: ?bool = null,
        splinesteps: ?i32 = null,
        activefill: ?[]const u8 = null,
        tags: ?[]const []const u8 = null,
        state: ?ItemState = null,
    };

    pub const ArcOptions = struct {
        /// 開始角度(度、3時方向が0で反時計回り)。
        start: ?f64 = null,
        /// 角度の範囲(度)。
        extent: ?f64 = null,
        style: ?ArcStyle = null,
        fill: ?[]const u8 = null,
        outline: ?[]const u8 = null,
        width: ?f64 = null,
        dash: ?[]const u8 = null,
        activefill: ?[]const u8 = null,
        tags: ?[]const []const u8 = null,
        state: ?ItemState = null,
    };

    pub const TextItemOptions = struct {
        text: ?[]const u8 = null,
        font: ?[]const u8 = null,
        fill: ?[]const u8 = null,
        anchor: ?types.Anchor = null,
        justify: ?types.Justify = null,
        /// 折り返す幅(0なら折り返さない)。
        width: ?f64 = null,
        /// 回転角度(度)。
        angle: ?f64 = null,
        underline: ?i32 = null,
        activefill: ?[]const u8 = null,
        tags: ?[]const []const u8 = null,
        state: ?ItemState = null,
    };

    pub const ImageItemOptions = struct {
        anchor: ?types.Anchor = null,
        /// マウスポインタが重なっている間に表示する画像。
        activeimage: ?PhotoImage = null,
        disabledimage: ?PhotoImage = null,
        tags: ?[]const []const u8 = null,
        state: ?ItemState = null,
    };

    pub const WindowItemOptions = struct {
        anchor: ?types.Anchor = null,
        width: ?i32 = null,
        height: ?i32 = null,
        tags: ?[]const []const u8 = null,
        state: ?ItemState = null,
    };

    const M = widget.Methods(Canvas, Options);
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

    const X = scroll.XMethods(Canvas);
    pub const xview = X.view;
    pub const xviewMoveto = X.moveto;
    pub const xviewScroll = X.scroll;
    pub const xviewCommand = X.command;

    const Y = scroll.YMethods(Canvas);
    pub const yview = Y.view;
    pub const yviewMoveto = Y.moveto;
    pub const yviewScroll = Y.scroll;
    pub const yviewCommand = Y.command;

    pub fn init(parent: anytype, opts: Options) Error!Canvas {
        return .{ .w = try .create(widget.asWidget(parent), "canvas", opts) };
    }

    // ---- アイテムの作成 ----

    pub fn createRectangle(self: Canvas, box: Box, opts: ShapeOptions) Error!ItemId {
        const pts = boxPoints(box);
        return self.create("rectangle", &pts, opts, .{});
    }

    /// boxに内接する楕円。
    pub fn createOval(self: Canvas, box: Box, opts: ShapeOptions) Error!ItemId {
        const pts = boxPoints(box);
        return self.create("oval", &pts, opts, .{});
    }

    /// boxに内接する楕円の弧。
    pub fn createArc(self: Canvas, box: Box, opts: ArcOptions) Error!ItemId {
        const pts = boxPoints(box);
        return self.create("arc", &pts, opts, .{});
    }

    /// 2点以上を結ぶ折れ線。
    pub fn createLine(self: Canvas, points: []const Point, opts: LineOptions) Error!ItemId {
        return self.create("line", points, opts, .{});
    }

    /// 3点以上を頂点とする多角形。
    pub fn createPolygon(self: Canvas, points: []const Point, opts: PolygonOptions) Error!ItemId {
        return self.create("polygon", points, opts, .{});
    }

    pub fn createText(self: Canvas, at: Point, opts: TextItemOptions) Error!ItemId {
        return self.create("text", &.{at}, opts, .{});
    }

    /// atに画像を配置する(既定ではatが画像の中心)。
    pub fn createImage(self: Canvas, at: Point, image: PhotoImage, opts: ImageItemOptions) Error!ItemId {
        return self.create("image", &.{at}, opts, .{ .image = image });
    }

    /// atに既存のWidgetを配置する(childはこのCanvasの子として生成したもの)。
    pub fn createWindow(self: Canvas, at: Point, child: anytype, opts: WindowItemOptions) Error!ItemId {
        return self.create("window", &.{at}, opts, .{ .window = widget.asWidget(child) });
    }

    fn create(self: Canvas, kind: []const u8, points: []const Point, opts: anytype, extra: anytype) Error!ItemId {
        var cmd: Cmd = .init(self.w.interp);
        defer cmd.deinit();
        try cmd.add(self.w.path);
        try cmd.add("create");
        try cmd.add(kind);
        try addPoints(&cmd, points);
        try cmd.addOptions(self.w.path, opts);
        try cmd.addOptions(self.w.path, extra);
        return self.parseId(try cmd.eval());
    }

    fn boxPoints(box: Box) [2]Point {
        return .{ .{ .x = box.x1, .y = box.y1 }, .{ .x = box.x2, .y = box.y2 } };
    }

    fn addPoints(cmd: *Cmd, points: []const Point) Error!void {
        for (points) |p| {
            try cmd.add(p.x);
            try cmd.add(p.y);
        }
    }

    // ---- アイテムの操作 ----

    pub fn delete(self: Canvas, target: anytype) Error!void {
        checkTarget(target);
        _ = try self.w.interp.call(.{ self.w.path, "delete", target });
    }

    /// 全アイテムを削除する。
    pub fn clear(self: Canvas) Error!void {
        return self.delete(.all);
    }

    /// targetを(dx, dy)だけ移動する。
    pub fn move(self: Canvas, target: anytype, dx: f64, dy: f64) Error!void {
        checkTarget(target);
        _ = try self.w.interp.call(.{ self.w.path, "move", target, dx, dy });
    }

    /// targetのbbox(枠線込み)の左上が(x, y)に来るよう移動する。
    pub fn moveto(self: Canvas, target: anytype, x: f64, y: f64) Error!void {
        checkTarget(target);
        _ = try self.w.interp.call(.{ self.w.path, "moveto", target, x, y });
    }

    /// (x0, y0)を中心にtargetの座標をsx, sy倍する。
    pub fn scale(self: Canvas, target: anytype, x0: f64, y0: f64, sx: f64, sy: f64) Error!void {
        checkTarget(target);
        _ = try self.w.interp.call(.{ self.w.path, "scale", target, x0, y0, sx, sy });
    }

    /// targetの(最初のアイテムの)座標をgpaで確保して返す。
    pub fn coords(self: Canvas, gpa: std.mem.Allocator, target: anytype) Error![]Point {
        checkTarget(target);
        const objs = try self.w.interp.callList(.{ self.w.path, "coords", target });
        const out = try gpa.alloc(Point, objs.len / 2);
        errdefer gpa.free(out);
        for (out, 0..) |*p, i| {
            p.* = .{ .x = try self.parseDouble(objs[2 * i]), .y = try self.parseDouble(objs[2 * i + 1]) };
        }
        return out;
    }

    /// targetの座標を置き換える。
    pub fn setCoords(self: Canvas, target: anytype, points: []const Point) Error!void {
        checkTarget(target);
        var cmd: Cmd = .init(self.w.interp);
        defer cmd.deinit();
        try cmd.add(self.w.path);
        try cmd.add("coords");
        try cmd.add(target);
        try addPoints(&cmd, points);
        _ = try cmd.eval();
    }

    /// targetのオプションを変更する。optsにはアイテムの種類に合うOptions(ShapeOptions等)を渡す。
    pub fn itemconfigure(self: Canvas, target: anytype, opts: anytype) Error!void {
        checkTarget(target);
        var cmd: Cmd = .init(self.w.interp);
        defer cmd.deinit();
        try cmd.add(self.w.path);
        try cmd.add("itemconfigure");
        try cmd.add(target);
        try cmd.addOptions(self.w.path, opts);
        _ = try cmd.eval();
    }

    /// targetのオプション値(例: itemcget(rect, "fill"))。次のTcl呼び出しまで有効。
    pub fn itemcget(self: Canvas, target: anytype, option: []const u8) Error![]const u8 {
        checkTarget(target);
        var buf: [64]u8 = undefined;
        const name = std.fmt.bufPrint(&buf, "-{s}", .{option}) catch return error.OutOfMemory;
        return self.w.interp.call(.{ self.w.path, "itemcget", target, name });
    }

    /// アイテムの種類("rectangle" "line" 等)。次のTcl呼び出しまで有効。
    pub fn itemType(self: Canvas, id: ItemId) Error![]const u8 {
        return self.w.interp.call(.{ self.w.path, "type", id });
    }

    /// targetを最前面へ。
    pub fn raiseItems(self: Canvas, target: anytype) Error!void {
        checkTarget(target);
        _ = try self.w.interp.call(.{ self.w.path, "raise", target });
    }

    /// targetを最背面へ。
    pub fn lowerItems(self: Canvas, target: anytype) Error!void {
        checkTarget(target);
        _ = try self.w.interp.call(.{ self.w.path, "lower", target });
    }

    // ---- タグ ----

    /// targetにtagを付ける。
    pub fn addtag(self: Canvas, tag: []const u8, target: anytype) Error!void {
        checkTarget(target);
        _ = try self.w.interp.call(.{ self.w.path, "addtag", tag, "withtag", target });
    }

    /// targetからtagを外す。
    pub fn dtag(self: Canvas, target: anytype, tag: []const u8) Error!void {
        checkTarget(target);
        _ = try self.w.interp.call(.{ self.w.path, "dtag", target, tag });
    }

    /// targetの(最初のアイテムの)タグをgpaで複製して返す(tk.freeStringsで解放)。
    pub fn gettags(self: Canvas, gpa: std.mem.Allocator, target: anytype) Error![][]u8 {
        checkTarget(target);
        return value.dupeStrings(gpa, try self.w.interp.callList(.{ self.w.path, "gettags", target }));
    }

    /// target上でのイベントにcbを結び付ける。コールバックはCanvasの破棄時に解放される。
    pub fn tagBind(self: Canvas, target: anytype, sequence: []const u8, cb: callback.EventCallback) Error!void {
        checkTarget(target);
        var tbuf: [256]u8 = undefined;
        var buf: [512]u8 = undefined;
        const name = std.fmt.bufPrintSentinel(&buf, "zt_bind{s}|item:{s}|{s}", .{ self.w.path, try targetText(&tbuf, target), sequence }, 0) catch
            return error.OutOfMemory;
        try callback.register(self.w.interp, name, cb);
        _ = try self.w.interp.call(.{ self.w.path, "bind", target, sequence, .{name} ++ callback.Event.substitutions });
    }

    // ---- 検索 ----

    /// 全アイテム(描画順)。
    pub fn findAll(self: Canvas, gpa: std.mem.Allocator) Error![]ItemId {
        return self.findIds(gpa, .{ self.w.path, "find", "all" });
    }

    pub fn findWithtag(self: Canvas, gpa: std.mem.Allocator, target: anytype) Error![]ItemId {
        checkTarget(target);
        return self.findIds(gpa, .{ self.w.path, "find", "withtag", target });
    }

    /// boxと重なるアイテム。
    pub fn findOverlapping(self: Canvas, gpa: std.mem.Allocator, box: Box) Error![]ItemId {
        return self.findIds(gpa, .{ self.w.path, "find", "overlapping", box.x1, box.y1, box.x2, box.y2 });
    }

    /// boxに完全に含まれるアイテム。
    pub fn findEnclosed(self: Canvas, gpa: std.mem.Allocator, box: Box) Error![]ItemId {
        return self.findIds(gpa, .{ self.w.path, "find", "enclosed", box.x1, box.y1, box.x2, box.y2 });
    }

    /// (x, y)に最も近いアイテム。アイテムが無ければnull。
    pub fn findClosest(self: Canvas, x: f64, y: f64) Error!?ItemId {
        const objs = try self.w.interp.callList(.{ self.w.path, "find", "closest", x, y });
        return if (objs.len == 0) null else try self.parseId(tcl.getString(objs[0]));
    }

    /// targetを囲む矩形。アイテムが無ければnull。
    pub fn bbox(self: Canvas, target: anytype) Error!?Box {
        checkTarget(target);
        const objs = try self.w.interp.callList(.{ self.w.path, "bbox", target });
        if (objs.len != 4) return null;
        return .{
            .x1 = try self.parseDouble(objs[0]),
            .y1 = try self.parseDouble(objs[1]),
            .x2 = try self.parseDouble(objs[2]),
            .y2 = try self.parseDouble(objs[3]),
        };
    }

    /// Widget上のx座標(イベントのx等)をキャンバス座標に変換する(スクロール分を加味)。
    pub fn canvasx(self: Canvas, screen_x: f64) Error!f64 {
        return self.parseDoubleStr(try self.w.interp.call(.{ self.w.path, "canvasx", screen_x }));
    }

    pub fn canvasy(self: Canvas, screen_y: f64) Error!f64 {
        return self.parseDoubleStr(try self.w.interp.call(.{ self.w.path, "canvasy", screen_y }));
    }

    // ---- 内部 ----

    fn findIds(self: Canvas, gpa: std.mem.Allocator, words: anytype) Error![]ItemId {
        const objs = try self.w.interp.callList(words);
        const out = try gpa.alloc(ItemId, objs.len);
        errdefer gpa.free(out);
        for (objs, out) |obj, *id| id.* = try self.parseId(tcl.getString(obj));
        return out;
    }

    fn parseId(self: Canvas, s: []const u8) Error!ItemId {
        const n = std.fmt.parseInt(u32, s, 10) catch return self.w.interp.failWith("unexpected canvas item id");
        return @enumFromInt(n);
    }

    fn parseDouble(self: Canvas, obj: *tcl.Obj) Error!f64 {
        var v: f64 = 0;
        if (tcl.Tcl_GetDoubleFromObj(self.w.interp.raw, obj, &v) != tcl.OK) return self.w.interp.fail();
        return v;
    }

    fn parseDoubleStr(self: Canvas, s: []const u8) Error!f64 {
        return std.fmt.parseFloat(f64, s) catch self.w.interp.failWith("unexpected number");
    }

    /// 操作対象として受け付ける型(ItemId / タグ文字列 / .all / .current)をコンパイル時に検査する。
    fn checkTarget(target: anytype) void {
        const T = @TypeOf(target);
        if (T == ItemId) return;
        if (T == @TypeOf(.all)) {
            // enumリテラルはコンパイル時に値が確定しているため、.all/.current以外を弾ける
            if (target != .all and target != .current)
                @compileError("zig_tk: canvas target literal must be .all or .current, got ." ++ @tagName(target));
            return;
        }
        switch (@typeInfo(T)) {
            .pointer => |p| {
                if (p.size == .slice and p.child == u8) return;
                if (p.size == .one and @typeInfo(p.child) == .array and @typeInfo(p.child).array.child == u8) return;
            },
            else => {},
        }
        @compileError("zig_tk: canvas target must be an ItemId, a tag string, .all or .current, got " ++ @typeName(T));
    }

    fn targetText(buf: []u8, target: anytype) Error![]const u8 {
        const T = @TypeOf(target);
        if (T == ItemId) return std.fmt.bufPrint(buf, "{d}", .{@intFromEnum(target)}) catch error.OutOfMemory;
        if (T == @TypeOf(.all)) return @tagName(target);
        return target;
    }
};
