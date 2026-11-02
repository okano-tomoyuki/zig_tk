const std = @import("std");
const testing = std.testing;
const tk = @import("root.zig");

fn initRoot() !tk.Tk {
    const root = try tk.Tk.init(testing.allocator);
    _ = try root.call(.{ "wm", "withdraw", "." });
    return root;
}

/// タグの付いたテキストアイテムの文字列を、Canvas上の並び順で ' ' 区切りにする。
fn texts(root: tk.Tk, chart: *const tk.Chart, tag: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(testing.allocator);
    const ids = try chart.canvas().findWithtag(testing.allocator, tag);
    defer testing.allocator.free(ids);
    for (ids, 0..) |id, i| {
        if (i > 0) try out.append(testing.allocator, ' ');
        try out.appendSlice(testing.allocator, try root.call(.{ chart.canvas(), "itemcget", id, "-text" }));
    }
    return out.toOwnedSlice(testing.allocator);
}

test "chart draws series, nice ticks and labels after the event loop goes idle" {
    const root = try initRoot();
    defer root.deinit();
    const chart = try tk.Chart.init(testing.allocator, root, .{ .title = "Temperature", .x_label = "t [s]", .y_label = "°C" });
    defer chart.deinit();
    try chart.pack(.{ .fill = .both, .expand = true });

    const a = try chart.addSeries(.{ .label = "A" });
    const b = try chart.addSeries(.{ .label = "B", .kind = .scatter, .color = "red" });
    for (0..11) |i| {
        const x: f64 = @floatFromInt(i);
        try chart.append(a, x, x);
        try chart.append(b, x, 10 - x);
    }
    // 追加しただけでは描かれず、暇になった時に1回だけ描かれる
    try testing.expectEqualStrings("", try root.call(.{ chart.canvas(), "find", "withtag", "series" }));
    try root.w.interp.update();

    // 折れ線は1本(11点)、散布図は点ごとの楕円
    const line = try chart.canvas().coords(testing.allocator, "series0");
    defer testing.allocator.free(line);
    try testing.expectEqual(11, line.len);
    const dots = try chart.canvas().findWithtag(testing.allocator, "series1");
    defer testing.allocator.free(dots);
    try testing.expectEqual(11, dots.len);
    try testing.expectEqualStrings("red", try chart.canvas().itemcget(dots[0], "fill"));

    // y: データ0〜10に5%の余白 → 2刻み。x: 0〜10ちょうど
    const yt = try texts(root, chart, "ytick");
    defer testing.allocator.free(yt);
    try testing.expectEqualStrings("0 2 4 6 8 10", yt);
    const xt = try texts(root, chart, "xtick");
    defer testing.allocator.free(xt);
    try testing.expect(std.mem.startsWith(u8, xt, "0 ") and std.mem.endsWith(u8, xt, " 10"));
    for ([_][]const u8{ "title", "xlabel", "ylabel" }, [_][]const u8{ "Temperature", "t [s]", "°C" }) |tag, want| {
        const got = try texts(root, chart, tag);
        defer testing.allocator.free(got);
        try testing.expectEqualStrings(want, got);
    }
    // 凡例: 枠 + (見本 + 名前) × 2
    const legend = try chart.canvas().findWithtag(testing.allocator, "legend");
    defer testing.allocator.free(legend);
    try testing.expectEqual(5, legend.len);
}

test "chart keeps at most max_points, honors fixed ranges and redraws once per idle" {
    const root = try initRoot();
    defer root.deinit();
    const chart = try tk.Chart.init(testing.allocator, root, .{ .legend = false });
    defer chart.deinit();
    try chart.pack(.{});

    const s = try chart.addSeries(.{ .max_points = 5 });
    for (0..10) |i| try chart.append(s, @floatFromInt(i), 1);
    try testing.expectEqual(5, chart.data(s).len);
    try testing.expectEqual(5, chart.data(s)[0].x);
    try chart.setData(s, &.{ .{ .x = 0, .y = 0 }, .{ .x = 1, .y = 1 }, .{ .x = 2, .y = 4 }, .{ .x = 3, .y = 9 }, .{ .x = 4, .y = 16 }, .{ .x = 5, .y = 25 } });
    try testing.expectEqual(5, chart.data(s).len);
    try testing.expectEqual(1, chart.data(s)[0].x);

    try chart.setYRange(.{ .min = 0, .max = 1 });
    try root.w.interp.update();
    const yt = try texts(root, chart, "ytick");
    defer testing.allocator.free(yt);
    try testing.expectEqualStrings("0.0 0.2 0.4 0.6 0.8 1.0", yt);
    // 描き直しのたびに前のアイテムは消える(系列の線は常に1本)
    try chart.append(s, 6, 0.5);
    try chart.redraw();
    try root.w.interp.update();
    const lines = try chart.canvas().findWithtag(testing.allocator, "series0");
    defer testing.allocator.free(lines);
    try testing.expectEqual(1, lines.len);

    try chart.clearSeries(s);
    try testing.expectEqual(0, chart.data(s).len);
}

test "chart follows the ttk theme colors and survives its parent being destroyed first" {
    const root = try initRoot();
    defer root.deinit();
    try root.setTheme(.sun_valley_dark);
    const frame = try tk.ttk.Frame.init(root, .{});
    const chart = try tk.Chart.init(testing.allocator, frame, .{});
    defer chart.deinit();
    _ = try chart.addSeries(.{});
    try root.w.interp.update();
    try testing.expectEqualStrings("#1c1c1c", try chart.canvas().w.cget("background"));

    // 親を先に破棄した後にデータを変えても、描き直しは何もせずに終わる
    try frame.destroy();
    try chart.append(@fromBackingInt(@intCast(0)), 1, 1);
    try root.w.interp.update();
}
