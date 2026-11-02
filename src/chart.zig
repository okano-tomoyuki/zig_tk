//! Canvasに描く折れ線・散布図のグラフ。
//!
//!     const chart = try tk.Chart.init(gpa, root, .{ .title = "温度", .x_label = "時刻 [s]", .y_label = "°C" });
//!     defer chart.deinit();
//!     try chart.pack(.{ .fill = .both, .expand = true });
//!     const s = try chart.addSeries(.{ .label = "センサーA", .max_points = 300 });
//!     try chart.append(s, t, value);
//!
//! 軸の範囲と目盛りはデータから自動で決まる(setXRange/setYRangeで固定もできる)。
//! データを変更すると、イベントループが暇になった時に1回だけ描き直す(続けて追加しても描画は1回)。
//! ウィンドウの大きさが変わった時も描き直す。配色は現在のttkテーマの背景色・文字色に合わせる。
const std = @import("std");
const Allocator = std.mem.Allocator;
const tcl = @import("tcl.zig");
const widget = @import("widget.zig");
const callback = @import("callback.zig");
const interp_mod = @import("interp.zig");
const Error = interp_mod.Error;
const TimerId = interp_mod.TimerId;
const Widget = widget.Widget;
const Canvas = @import("widgets/canvas.zig").Canvas;
const Point = Canvas.Point;

pub const Chart = struct {
    /// グラフを描くCanvas。pack/grid/placeやbindはこのWidgetに対して行う。
    w: Widget,
    gpa: Allocator,
    /// 文字列オプションの複製の置き場。
    arena: std.heap.ArenaAllocator,
    title: ?[]const u8,
    x_label: ?[]const u8,
    y_label: ?[]const u8,
    x_range: ?Range,
    y_range: ?Range,
    legend: bool,
    grid_lines: bool,
    series: std.ArrayList(Series) = .empty,
    pending: ?TimerId = null,

    pub const Range = struct { min: f64, max: f64 };

    pub const Options = struct {
        /// 初期の大きさ(ピクセル)。
        width: i32 = 480,
        height: i32 = 300,
        title: ?[]const u8 = null,
        x_label: ?[]const u8 = null,
        y_label: ?[]const u8 = null,
        /// 軸の範囲。nullならデータから自動で決める。
        x_range: ?Range = null,
        y_range: ?Range = null,
        /// 系列の凡例を右上に表示する(labelが空の系列は表示しない)。
        legend: bool = true,
        /// 目盛りの位置に補助線を引く。
        grid: bool = true,
    };

    pub const Kind = enum { line, scatter };

    pub const SeriesOptions = struct {
        label: []const u8 = "",
        kind: Kind = .line,
        /// 線・点の色。nullなら系列の順に既定の配色から選ぶ。
        color: ?[]const u8 = null,
        /// 線の太さ(.line)、点の直径(.scatter)。
        width: f64 = 2,
        /// 保持する点の最大数。超えると古い点から捨てる(リアルタイム表示向け)。nullなら無制限。
        max_points: ?usize = null,
    };

    /// addSeriesが返す系列のID。
    pub const SeriesId = enum(u32) { _ };

    const Series = struct {
        label: []const u8,
        kind: Kind,
        color: []const u8,
        width: f64,
        max_points: ?usize,
        points: std.ArrayList(Point) = .empty,
    };

    /// 色覚の違いに配慮された配色(matplotlibのtab10)。
    const palette = [_][]const u8{ "#1f77b4", "#ff7f0e", "#2ca02c", "#d62728", "#9467bd", "#8c564b", "#e377c2", "#7f7f7f", "#bcbd22", "#17becf" };

    /// parentの子としてグラフを生成する。deinitで破棄する。
    pub fn init(gpa: Allocator, parent: anytype, opts: Options) Error!*Chart {
        const canvas_widget = try Canvas.init(parent, .{ .width = opts.width, .height = opts.height, .highlightthickness = 0 });
        errdefer canvas_widget.w.destroy() catch {};
        const self = try gpa.create(Chart);
        errdefer gpa.destroy(self);
        self.* = .{
            .w = canvas_widget.w,
            .gpa = gpa,
            .arena = .init(gpa),
            .title = null,
            .x_label = null,
            .y_label = null,
            .x_range = opts.x_range,
            .y_range = opts.y_range,
            .legend = opts.legend,
            .grid_lines = opts.grid,
        };
        errdefer self.arena.deinit();
        const a = self.arena.allocator();
        if (opts.title) |s| self.title = try a.dupe(u8, s);
        if (opts.x_label) |s| self.x_label = try a.dupe(u8, s);
        if (opts.y_label) |s| self.y_label = try a.dupe(u8, s);
        try self.w.bind("<Configure>", callback.callback(self, onConfigure));
        try self.scheduleRedraw();
        return self;
    }

    /// Canvasを(残っていれば)破棄し、データを解放する。
    pub fn deinit(self: *Chart) void {
        if (self.pending) |id| self.w.interp.afterCancel(id);
        if (self.w.winfoExists() catch false) self.w.destroy() catch {};
        for (self.series.items) |*s| s.points.deinit(self.gpa);
        self.series.deinit(self.gpa);
        self.arena.deinit();
        self.gpa.destroy(self);
    }

    pub fn pack(self: *const Chart, opts: widget.PackOptions) Error!void {
        return self.w.pack(opts);
    }

    pub fn grid(self: *const Chart, opts: widget.GridOptions) Error!void {
        return self.w.grid(opts);
    }

    pub fn place(self: *const Chart, opts: widget.PlaceOptions) Error!void {
        return self.w.place(opts);
    }

    /// 描画に使っているCanvas(独自のアイテムを重ねて描く場合等)。描き直しのたびに全アイテムが消える。
    pub fn canvas(self: *const Chart) Canvas {
        return .{ .w = self.w };
    }

    pub fn addSeries(self: *Chart, opts: SeriesOptions) Error!SeriesId {
        const a = self.arena.allocator();
        try self.series.append(self.gpa, .{
            .label = try a.dupe(u8, opts.label),
            .kind = opts.kind,
            .color = try a.dupe(u8, opts.color orelse palette[self.series.items.len % palette.len]),
            .width = opts.width,
            .max_points = opts.max_points,
        });
        try self.scheduleRedraw();
        return @fromBackingInt(@intCast(self.series.items.len - 1));
    }

    /// 系列に1点を追加する。max_pointsを超えた分は古い点から捨てる。
    pub fn append(self: *Chart, id: SeriesId, x: f64, y: f64) Error!void {
        const s = &self.series.items[@backingInt(id)];
        try s.points.append(self.gpa, .{ .x = x, .y = y });
        if (s.max_points) |max| {
            if (s.points.items.len > max) {
                const drop = s.points.items.len - max;
                std.mem.copyForwards(Point, s.points.items, s.points.items[drop..]);
                s.points.shrinkRetainingCapacity(max);
            }
        }
        try self.scheduleRedraw();
    }

    /// 系列の点をpointsで置き換える(max_pointsを超える分は先頭側を捨てる)。
    pub fn setData(self: *Chart, id: SeriesId, points: []const Point) Error!void {
        const s = &self.series.items[@backingInt(id)];
        const keep = if (s.max_points) |max| points[points.len -| max..] else points;
        s.points.clearRetainingCapacity();
        try s.points.appendSlice(self.gpa, keep);
        try self.scheduleRedraw();
    }

    /// 系列の点を全て消す。
    pub fn clearSeries(self: *Chart, id: SeriesId) Error!void {
        self.series.items[@backingInt(id)].points.clearRetainingCapacity();
        try self.scheduleRedraw();
    }

    /// 系列の現在の点(次に変更するまで有効)。
    pub fn data(self: *const Chart, id: SeriesId) []const Point {
        return self.series.items[@backingInt(id)].points.items;
    }

    /// x軸の範囲を固定する。nullでデータからの自動に戻す。
    pub fn setXRange(self: *Chart, range: ?Range) Error!void {
        self.x_range = range;
        try self.scheduleRedraw();
    }

    pub fn setYRange(self: *Chart, range: ?Range) Error!void {
        self.y_range = range;
        try self.scheduleRedraw();
    }

    fn onConfigure(self: *Chart, _: callback.Event) !void {
        try self.scheduleRedraw();
    }

    fn scheduleRedraw(self: *Chart) Error!void {
        if (self.pending != null) return;
        self.pending = try self.w.interp.afterIdle(callback.callback(self, onIdle));
    }

    fn onIdle(self: *Chart) !void {
        self.pending = null;
        // 親ごと破棄された後(deinit前)は何もしない
        if (!try self.w.winfoExists()) return;
        try self.redraw();
    }

    /// 今すぐ描き直す(通常はデータの変更時に自動で行われる)。
    pub fn redraw(self: *Chart) Error!void {
        const cv = self.canvas();
        try cv.delete(.all);

        var width: f64 = @floatFromInt(try self.w.winfo(.width));
        var height: f64 = @floatFromInt(try self.w.winfo(.height));
        // マップ前は1になるため要求サイズを使う
        if (width <= 1) width = @floatFromInt(try self.w.winfo(.reqwidth));
        if (height <= 1) height = @floatFromInt(try self.w.winfo(.reqheight));

        const colors = try self.themeColors();
        const bg = colors.bg.slice();
        const fg = colors.fg.slice();
        const sub = colors.mix(0.7);
        const frame = colors.mix(0.35);
        const grid_color = colors.mix(0.12);
        try self.w.configure(.{ .background = bg });

        const xr = self.x_range orelse self.autoRange(.x);
        const yr = self.y_range orelse self.autoRange(.y);

        // 余白: 上はタイトル、左はy軸の目盛りと軸名、下はx軸の目盛りと軸名の分
        const line_h: f64 = @floatFromInt(try self.fontLinespace("TkDefaultFont"));
        const pad = 10.0;
        var top = pad + line_h / 2;
        if (self.title != null) top += @as(f64, @floatFromInt(try self.fontLinespace("TkHeadingFont"))) + 4;
        var bottom = height - pad - line_h - 4;
        if (self.x_label != null) bottom -= line_h + 2;
        const right = width - pad - 12;

        const y_step = niceStep(yr.max - yr.min, @max(2, (bottom - top) / 50));
        var label_w: f64 = 0;
        var y_ticks: TickIter = .init(yr, y_step);
        while (y_ticks.next()) |v| {
            var buf: [32]u8 = undefined;
            label_w = @max(label_w, @as(f64, @floatFromInt(try self.textWidth(formatTick(&buf, v, y_step)))));
        }
        var left = pad + label_w + 8;
        if (self.y_label != null) left += line_h + 4;
        if (right - left < 10 or bottom - top < 10) return;

        const area: Area = .{ .left = left, .top = top, .right = right, .bottom = bottom, .xr = xr, .yr = yr };
        const x_step = niceStep(xr.max - xr.min, @max(2, (right - left) / 80));

        // 補助線
        if (self.grid_lines) {
            var x_ticks: TickIter = .init(xr, x_step);
            while (x_ticks.next()) |v| {
                const px = area.px(v);
                _ = try cv.createLine(&.{ .{ .x = px, .y = top }, .{ .x = px, .y = bottom } }, .{ .fill = grid_color.slice(), .tags = &.{"grid"} });
            }
            y_ticks = .init(yr, y_step);
            while (y_ticks.next()) |v| {
                const py = area.py(v);
                _ = try cv.createLine(&.{ .{ .x = left, .y = py }, .{ .x = right, .y = py } }, .{ .fill = grid_color.slice(), .tags = &.{"grid"} });
            }
        }

        // 系列
        var pixels: std.ArrayList(Point) = .empty;
        defer pixels.deinit(self.gpa);
        for (self.series.items, 0..) |s, i| {
            var tag_buf: [24]u8 = undefined;
            const tag = std.fmt.bufPrint(&tag_buf, "series{d}", .{i}) catch unreachable;
            pixels.clearRetainingCapacity();
            for (s.points.items) |p| try pixels.append(self.gpa, .{ .x = area.px(p.x), .y = area.py(p.y) });
            if (s.kind == .line and pixels.items.len >= 2) {
                _ = try cv.createLine(pixels.items, .{ .fill = s.color, .width = s.width, .joinstyle = .round, .capstyle = .round, .tags = &.{ "series", tag } });
            } else {
                const r = @max(s.width, 2) / 2 + @as(f64, if (s.kind == .scatter) 1 else 0);
                for (pixels.items) |p|
                    _ = try cv.createOval(.{ .x1 = p.x - r, .y1 = p.y - r, .x2 = p.x + r, .y2 = p.y + r }, .{ .fill = s.color, .outline = "", .tags = &.{ "series", tag } });
            }
        }

        // 範囲外にはみ出した線を、描画領域の外側を背景色で塗って隠す
        const mask = [_]Canvas.Box{
            .{ .x1 = -1, .y1 = -1, .x2 = width + 1, .y2 = top },
            .{ .x1 = -1, .y1 = bottom, .x2 = width + 1, .y2 = height + 1 },
            .{ .x1 = -1, .y1 = top, .x2 = left, .y2 = bottom },
            .{ .x1 = right, .y1 = top, .x2 = width + 1, .y2 = bottom },
        };
        for (mask) |b| _ = try cv.createRectangle(b, .{ .fill = bg, .outline = "" });

        // 枠・目盛り・軸名・タイトル
        _ = try cv.createRectangle(.{ .x1 = left, .y1 = top, .x2 = right, .y2 = bottom }, .{ .outline = frame.slice() });
        y_ticks = .init(yr, y_step);
        while (y_ticks.next()) |v| {
            var buf: [32]u8 = undefined;
            _ = try cv.createText(.{ .x = left - 6, .y = area.py(v) }, .{ .text = formatTick(&buf, v, y_step), .anchor = .e, .fill = sub.slice(), .tags = &.{"ytick"} });
        }
        var x_ticks: TickIter = .init(xr, x_step);
        while (x_ticks.next()) |v| {
            var buf: [32]u8 = undefined;
            _ = try cv.createText(.{ .x = area.px(v), .y = bottom + 4 }, .{ .text = formatTick(&buf, v, x_step), .anchor = .n, .fill = sub.slice(), .tags = &.{"xtick"} });
        }
        if (self.title) |t|
            _ = try cv.createText(.{ .x = (left + right) / 2, .y = pad }, .{ .text = t, .anchor = .n, .font = "TkHeadingFont", .fill = fg, .tags = &.{"title"} });
        if (self.x_label) |t|
            _ = try cv.createText(.{ .x = (left + right) / 2, .y = height - pad }, .{ .text = t, .anchor = .s, .fill = fg, .tags = &.{"xlabel"} });
        if (self.y_label) |t|
            _ = try cv.createText(.{ .x = pad, .y = (top + bottom) / 2 }, .{ .text = t, .anchor = .n, .angle = 90, .fill = fg, .tags = &.{"ylabel"} });

        if (self.legend) try self.drawLegend(cv, area, colors, frame, line_h);
    }

    fn drawLegend(self: *Chart, cv: Canvas, area: Area, colors: Colors, frame: Rgb, line_h: f64) Error!void {
        var widest: f64 = 0;
        var rows: f64 = 0;
        for (self.series.items) |s| {
            if (s.label.len == 0) continue;
            widest = @max(widest, @as(f64, @floatFromInt(try self.textWidth(s.label))));
            rows += 1;
        }
        if (rows == 0) return;
        const sample = 18.0;
        const x2 = area.right - 8;
        const x1 = x2 - (8 + sample + 6 + widest + 8);
        const y1 = area.top + 8;
        _ = try cv.createRectangle(.{ .x1 = x1, .y1 = y1, .x2 = x2, .y2 = y1 + rows * line_h + 8 }, .{ .fill = colors.bg.slice(), .outline = frame.slice(), .tags = &.{"legend"} });
        var y = y1 + 4 + line_h / 2;
        for (self.series.items) |s| {
            if (s.label.len == 0) continue;
            const sx = x1 + 8;
            switch (s.kind) {
                .line => _ = try cv.createLine(&.{ .{ .x = sx, .y = y }, .{ .x = sx + sample, .y = y } }, .{ .fill = s.color, .width = s.width, .tags = &.{"legend"} }),
                .scatter => _ = try cv.createOval(.{ .x1 = sx + sample / 2 - 3, .y1 = y - 3, .x2 = sx + sample / 2 + 3, .y2 = y + 3 }, .{ .fill = s.color, .outline = "", .tags = &.{"legend"} }),
            }
            _ = try cv.createText(.{ .x = sx + sample + 6, .y = y }, .{ .text = s.label, .anchor = .w, .fill = colors.fg.slice(), .tags = &.{"legend"} });
            y += line_h;
        }
    }

    const Axis = enum { x, y };

    /// 全系列の点を含む範囲。yは上下に5%の余白を取る。点が無ければ0〜1。
    fn autoRange(self: *const Chart, axis: Axis) Range {
        var lo = std.math.inf(f64);
        var hi = -std.math.inf(f64);
        for (self.series.items) |s| for (s.points.items) |p| {
            const v = if (axis == .x) p.x else p.y;
            if (!std.math.isFinite(v)) continue;
            lo = @min(lo, v);
            hi = @max(hi, v);
        };
        if (lo > hi) return .{ .min = 0, .max = 1 };
        if (lo == hi) {
            const d = if (lo == 0) 1 else @abs(lo) * 0.1;
            return .{ .min = lo - d, .max = hi + d };
        }
        if (axis == .x) return .{ .min = lo, .max = hi };
        const margin = (hi - lo) * 0.05;
        return .{ .min = lo - margin, .max = hi + margin };
    }

    fn fontLinespace(self: *Chart, font: []const u8) Error!i32 {
        return std.fmt.parseInt(i32, try self.w.interp.call(.{ "font", "metrics", font, "-linespace" }), 10) catch 16;
    }

    fn textWidth(self: *Chart, text: []const u8) Error!i32 {
        return std.fmt.parseInt(i32, try self.w.interp.call(.{ "font", "measure", "TkDefaultFont", text }), 10) catch 0;
    }

    /// 配色はttkのテーマから取る。テーマが値を持たなければ、classic Widgetの既定色を使う。
    fn themeColors(self: *Chart) Error!Colors {
        const interp = self.w.interp;
        var bg_name: ColorName = .{};
        bg_name.set(try interp.call(.{ "ttk::style", "lookup", ".", "-background" }));
        if (bg_name.len == 0) bg_name.set(try interp.call(.{ "option", "get", ".", "background", "Background" }));
        if (bg_name.len == 0) bg_name.set("white");
        var fg_name: ColorName = .{};
        fg_name.set(try interp.call(.{ "ttk::style", "lookup", ".", "-foreground" }));
        if (fg_name.len == 0) fg_name.set("black");
        return .{ .bg = try self.rgb(bg_name.slice()), .fg = try self.rgb(fg_name.slice()) };
    }

    fn rgb(self: *Chart, name: []const u8) Error!Rgb {
        const objs = try self.w.interp.callList(.{ "winfo", "rgb", self.w.path, name });
        var v: [3]u8 = .{ 0, 0, 0 };
        if (objs.len == 3) {
            for (objs, &v) |o, *out| out.* = @intCast((std.fmt.parseInt(u32, tcl.getString(o), 10) catch 0) >> 8);
        }
        return .init(v);
    }
};

/// 色の成分と、その "#rrggbb" 表記。
const Rgb = struct {
    v: [3]u8,
    hex: [7]u8,

    fn init(v: [3]u8) Rgb {
        var c: Rgb = .{ .v = v, .hex = undefined };
        _ = std.fmt.bufPrint(&c.hex, "#{x:0>2}{x:0>2}{x:0>2}", .{ v[0], v[1], v[2] }) catch unreachable;
        return c;
    }

    fn slice(self: *const Rgb) []const u8 {
        return &self.hex;
    }
};

const Colors = struct {
    bg: Rgb,
    fg: Rgb,

    /// 背景色から文字色へtだけ寄せた色(0で背景色、1で文字色)。
    fn mix(self: Colors, t: f64) Rgb {
        var v: [3]u8 = undefined;
        for (&v, self.bg.v, self.fg.v) |*o, b, f| {
            const x = @as(f64, @floatFromInt(b)) + (@as(f64, @floatFromInt(f)) - @as(f64, @floatFromInt(b))) * t;
            o.* = @intFromFloat(@round(std.math.clamp(x, 0, 255)));
        }
        return .init(v);
    }
};

/// Tclの結果(次の呼び出しで上書きされる)を保持するための色名の置き場。
const ColorName = struct {
    buf: [64]u8 = undefined,
    len: usize = 0,

    fn set(self: *ColorName, s: []const u8) void {
        self.len = @min(s.len, self.buf.len);
        @memcpy(self.buf[0..self.len], s[0..self.len]);
    }

    fn slice(self: *const ColorName) []const u8 {
        return self.buf[0..self.len];
    }
};

/// データ座標から描画領域内のピクセル座標への変換。
const Area = struct {
    left: f64,
    top: f64,
    right: f64,
    bottom: f64,
    xr: Chart.Range,
    yr: Chart.Range,

    fn px(self: Area, x: f64) f64 {
        return self.left + (x - self.xr.min) / (self.xr.max - self.xr.min) * (self.right - self.left);
    }

    fn py(self: Area, y: f64) f64 {
        return self.bottom - (y - self.yr.min) / (self.yr.max - self.yr.min) * (self.bottom - self.top);
    }
};

/// 範囲をおよそtarget個に区切る、1・2・5×10^n の刻み幅。
fn niceStep(span: f64, target: f64) f64 {
    if (!(span > 0) or !std.math.isFinite(span)) return 1;
    const raw = span / target;
    const mag = std.math.pow(f64, 10, @floor(std.math.log10(raw)));
    const n = raw / mag;
    const nice: f64 = if (n < 1.5) 1 else if (n < 3) 2 else if (n < 7) 5 else 10;
    return nice * mag;
}

/// 範囲内にある刻み幅stepの倍数を小さい順に返す。
const TickIter = struct {
    i: f64,
    end: f64,
    step: f64,

    fn init(r: Chart.Range, step: f64) TickIter {
        return .{ .i = @ceil(r.min / step - 1e-9), .end = @floor(r.max / step + 1e-9), .step = step };
    }

    fn next(self: *TickIter) ?f64 {
        if (self.i > self.end) return null;
        defer self.i += 1;
        return self.i * self.step;
    }
};

/// 刻み幅に応じた桁数で目盛りの値を書く(0.1刻みなら小数1桁)。
fn formatTick(buf: []u8, v: f64, step: f64) []const u8 {
    const decimals: usize = if (step >= 1) 0 else @intFromFloat(@min(10, @ceil(-std.math.log10(step) - 1e-9)));
    // -0 を 0 と書く
    const x = if (@abs(v) < step * 1e-6) 0 else v;
    return std.fmt.bufPrint(buf, "{d:.[1]}", .{ x, decimals }) catch "?";
}

test niceStep {
    try std.testing.expectEqual(2, niceStep(11, 5));
    try std.testing.expectEqual(0.5, niceStep(2.2, 5));
    try std.testing.expectEqual(100, niceStep(800, 8));
    try std.testing.expectApproxEqRel(0.02, niceStep(0.1, 5), 1e-12);
}

test formatTick {
    var buf: [32]u8 = undefined;
    try std.testing.expectEqualStrings("10", formatTick(&buf, 10, 2));
    try std.testing.expectEqualStrings("0.5", formatTick(&buf, 0.5, 0.5));
    try std.testing.expectEqualStrings("0.0", formatTick(&buf, -1e-17, 0.1));
    try std.testing.expectEqualStrings("0.25", formatTick(&buf, 0.25, 0.05));
}
