//! PhotoImage と、画像を使うWidgetオプションのテスト。
const std = @import("std");
const testing = std.testing;
const tk = @import("root.zig");

fn initRoot() !tk.Tk {
    const root = try tk.Tk.init(testing.allocator);
    _ = try root.call(.{ "wm", "withdraw", "." });
    return root;
}

const red: tk.Color = .{ .r = 255, .g = 0, .b = 0 };

test "photo image pixels" {
    const root = try initRoot();
    defer root.deinit();

    const img = try tk.PhotoImage.init(root, .{ .width = 4, .height = 3 });
    defer img.deinit();
    try testing.expectEqual(4, try img.width());
    try testing.expectEqual(3, try img.height());

    try img.put(red, .{ .x1 = 0, .y1 = 0, .x2 = 2, .y2 = 3 });
    try testing.expectEqual(red, try img.get(1, 2));
    try testing.expect(!try img.transparencyGet(0, 0));
    try img.transparencySet(0, 0, true);
    try testing.expect(try img.transparencyGet(0, 0));
    try img.transparencySet(0, 0, false);
    try testing.expect(!try img.transparencyGet(0, 0));

    const big = try img.zoom(2, 2);
    defer big.deinit();
    try testing.expectEqual(8, try big.width());
    try testing.expectEqual(red, try big.get(3, 5));
    const small = try big.subsample(4, 3);
    defer small.deinit();
    try testing.expectEqual(2, try small.width());

    try img.blank();
    try testing.expectEqual(4, try img.width());
}

test "photo image from in-memory data" {
    const root = try initRoot();
    defer root.deinit();

    // 2x1のPPM(左が青、右が緑)
    const ppm = "P6\n2 1\n255\n" ++ [_]u8{ 0, 0, 255, 0, 255, 0 };
    const img = try tk.PhotoImage.init(root, .{ .data = .{ .bytes = ppm }, .format = "ppm" });
    defer img.deinit();
    try testing.expectEqual(2, try img.width());
    try testing.expectEqual(tk.Color{ .r = 0, .g = 0, .b = 255 }, try img.get(0, 0));
    try testing.expectEqual(tk.Color{ .r = 0, .g = 255, .b = 0 }, try img.get(1, 0));

    // 不正なデータはTclError
    try testing.expectError(error.TclError, tk.PhotoImage.init(root, .{ .data = .{ .bytes = "not an image" } }));
}

test "images can be used by widgets" {
    const root = try initRoot();
    defer root.deinit();

    const img = try tk.PhotoImage.init(root, .{ .width = 8, .height = 8 });
    try img.put(red, .{ .x1 = 0, .y1 = 0, .x2 = 8, .y2 = 8 });

    const label = try tk.Label.init(root, .{ .image = img });
    try testing.expectEqualStrings(img.name(), try label.cget(.image));
    const button = try tk.ttk.Button.init(root, .{ .text = "Save", .image = img, .compound = .left });
    try testing.expectEqualStrings(img.name(), try button.cget(.image));

    const canvas = try tk.Canvas.init(root, .{});
    const item = try canvas.createImage(.{ .x = 10, .y = 10 }, img, .{ .anchor = .nw });
    try testing.expectEqualStrings("image", try canvas.itemType(item));

    const text = try tk.Text.init(root, .{});
    try text.insert(.end, "ab");
    try text.imageCreate(.at(1, 1), img, .{ .@"align" = .center, .padx = 2 });
    // 画像は1文字分の位置を占める
    try testing.expectEqual(tk.Text.Pos{ .line = 1, .char = 3 }, try text.index(tk.Text.Index.end.plusChars(-1)));

    const tv = try tk.ttk.Treeview.init(root, .{});
    const row = try tv.insert(.root, .end, .{ .text = "row", .image = img });
    try testing.expectEqualStrings(img.name(), try root.call(.{ tv, "item", row, "-image" }));

    const nb = try tk.ttk.Notebook.init(root, .{});
    const page = try tk.Frame.init(nb, .{});
    try nb.add(page, .{ .text = "Tab", .image = img, .compound = .left });
    try testing.expectEqualStrings(img.name(), try nb.tabCget(page, "image"));

    const menu = try tk.Menu.init(root, .{ .tearoff = false });
    try menu.addCommand(.{ .label = "Open", .image = img, .compound = .left });
    try testing.expectEqualStrings(img.name(), try menu.entrycget(.at(0), "image"));

    try root.iconphoto(img, true);

    // image namesにはTk自身が使う画像も含まれるため、削除した画像が無いことだけを確認する
    img.deinit();
    try testing.expectEqualStrings("-1", try root.call(.{ "lsearch", "-exact", try root.call(.{ "image", "names" }), img.name() }));
}
