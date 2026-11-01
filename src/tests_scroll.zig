//! Listbox と Scrollbar/スクロール連携のテスト。
const std = @import("std");
const testing = std.testing;
const tk = @import("root.zig");

fn initRoot() !tk.Tk {
    const root = try tk.Tk.init(testing.allocator);
    _ = try root.call(.{ "wm", "withdraw", "." });
    return root;
}

test "listbox editing and reading" {
    const root = try initRoot();
    defer root.deinit();

    const lb = try tk.Listbox.init(root, .{});
    try lb.insert(.end, &.{ "zig", "c", "tcl" });
    try lb.append("with space");
    try lb.insert(.at(0), &.{"first"});
    try testing.expectEqual(5, try lb.size());
    try testing.expectEqualStrings("first", try lb.get(.at(0)));
    try testing.expectEqualStrings("with space", try lb.get(.end));

    const all = try lb.items(testing.allocator);
    defer tk.freeStrings(testing.allocator, all);
    try testing.expectEqual(5, all.len);
    try testing.expectEqualStrings("zig", all[1]);

    try lb.delete(.at(1), .at(2));
    try testing.expectEqualStrings("tcl", try lb.get(.at(1)));
    try testing.expectEqual(3, try lb.index(.end));
    try lb.clear();
    try testing.expectEqual(0, try lb.size());
}

test "listbox selection" {
    const root = try initRoot();
    defer root.deinit();

    const lb = try tk.Listbox.init(root, .{ .selectmode = .extended });
    try lb.insert(.end, &.{ "a", "b", "c", "d", "e" });
    try testing.expectEqual(null, try lb.selectedIndex());

    try lb.selectionSet(.at(1), .at(3));
    const sel = try lb.curselection(testing.allocator);
    defer testing.allocator.free(sel);
    try testing.expectEqualSlices(usize, &.{ 1, 2, 3 }, sel);
    try testing.expectEqual(1, (try lb.selectedIndex()).?);
    try testing.expect(try lb.selectionIncludes(.at(2)));
    try testing.expect(!try lb.selectionIncludes(.at(4)));

    try lb.selectionClear(.at(0), .end);
    try testing.expectEqual(null, try lb.selectedIndex());

    try lb.itemconfigure(.at(0), .{ .background = "yellow" });
    try testing.expectEqualStrings("yellow", try root.call(.{ lb, "itemcget", 0, "-background" }));
}

test "scrollbar attach links both directions" {
    const root = try initRoot();
    defer root.deinit();

    const lb = try tk.Listbox.init(root, .{ .height = 5 });
    for (0..100) |_| try lb.append("line");
    const sb = try tk.Scrollbar.init(root, .{});
    try sb.attach(lb, .y);
    try lb.pack(.{ .side = .left });
    try sb.pack(.{ .side = .right, .fill = .y });

    var buf: [64]u8 = undefined;
    try testing.expectEqualStrings(try std.fmt.bufPrint(&buf, "{s} set", .{sb.w.path}), try lb.cget(.yscrollcommand));
    try testing.expectEqualStrings(try std.fmt.bufPrint(&buf, "{s} yview", .{lb.w.path}), try sb.cget(.command));
    try testing.expectEqualStrings("vertical", try sb.cget(.orient));

    // yscrollcommandは再描画時に呼ばれるため、ウィンドウを(画面外に)表示しておく
    try root.geometry("+-3000+-3000");
    try root.deiconify();
    try root.update();

    try lb.yviewMoveto(0.5);
    try root.update();
    const view = try lb.yview();
    try testing.expectApproxEqAbs(0.5, view.first, 0.011);
    // 表示範囲の変化がyscrollcommand経由でスクロールバーに伝わっている
    const thumb = try sb.get();
    try testing.expectApproxEqAbs(view.first, thumb.first, 1e-9);
    try testing.expectApproxEqAbs(view.last, thumb.last, 1e-9);

    // 1unitの移動量はTkのバージョンで異なる(8.6は1行、9.0は表示上の都合で異なる場合がある)ため方向のみ確認する
    try lb.yviewScroll(5, .units);
    const after = (try lb.yview()).first;
    try testing.expect(after > view.first);
    try lb.yviewScroll(-1, .pages);
    try testing.expect((try lb.yview()).first < after);
}

test "typed scroll commands can be set via config" {
    const root = try initRoot();
    defer root.deinit();

    const entry = try tk.ttk.Entry.init(root, .{});
    const hsb = try tk.ttk.Scrollbar.init(root, .{ .orient = .horizontal, .command = entry.xviewCommand() });
    try entry.config(.{ .xscrollcommand = hsb.setter() });

    var buf: [64]u8 = undefined;
    try testing.expectEqualStrings(try std.fmt.bufPrint(&buf, "{s} xview", .{entry.w.path}), try hsb.cget(.command));
    try testing.expectEqualStrings(try std.fmt.bufPrint(&buf, "{s} set", .{hsb.w.path}), try entry.cget(.xscrollcommand));

    // attachでx方向に結ぶとorientもhorizontalになる
    const lb = try tk.Listbox.init(root, .{});
    const sb = try tk.Scrollbar.init(root, .{});
    try sb.attach(lb, .x);
    try testing.expectEqualStrings("horizontal", try sb.cget(.orient));
}
