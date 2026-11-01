//! Text と Canvas のテスト。
const std = @import("std");
const testing = std.testing;
const tk = @import("root.zig");
const I = tk.Text.Index;

fn initRoot() !tk.Tk {
    const root = try tk.Tk.init(testing.allocator);
    _ = try root.call(.{ "wm", "withdraw", "." });
    return root;
}

fn countBindCommands(root: tk.Tk) ![]const u8 {
    return root.call(.{ "eval", "llength [info commands ::zt_bind*]" });
}

test "text content and typed indices" {
    const root = try initRoot();
    defer root.deinit();

    const text = try tk.Text.init(root, .{ .wrap = .word, .width = 40, .height = 5 });
    try text.insert(.end, "hello\nworld");
    try testing.expectEqualStrings("hello\nworld", try text.content());
    try testing.expectEqualStrings("world", try text.get(.at(2, 0), .at(2, 5)));
    try testing.expectEqualStrings("h", try text.get(.at(1, 0), null));

    try testing.expectEqual(tk.Text.Pos{ .line = 3, .char = 0 }, try text.index(.end));
    try testing.expectEqual(tk.Text.Pos{ .line = 1, .char = 3 }, try text.index(I.at(1, 0).plusChars(3)));
    try testing.expectEqual(tk.Text.Pos{ .line = 2, .char = 5 }, try text.index(I.at(1, 1).plusLines(1).lineEnd()));
    try testing.expectEqual(tk.Text.Pos{ .line = 1, .char = 4 }, try text.index(I.at(2, 0).plusChars(-2)));
    try testing.expect(try text.compare(.at(1, 0), .lt, .end));

    // カーソル行を消す
    try text.markSet("insert", .at(2, 2));
    try text.delete(I.insert.lineStart(), I.insert.lineEnd());
    try testing.expectEqualStrings("hello\n", try text.content());

    try text.replace(.at(1, 0), .at(1, 5), "HELLO");
    try testing.expectEqualStrings("HELLO\n", try text.content());
    try text.clear();
    try testing.expectEqualStrings("", try text.content());
}

test "text search" {
    const root = try initRoot();
    defer root.deinit();

    const text = try tk.Text.init(root, .{});
    try text.insert(.end, "Zig and Tcl\nzig again");
    try testing.expectEqual(tk.Text.Pos{ .line = 1, .char = 8 }, (try text.search("Tcl", .at(1, 0), .{})).?);
    try testing.expectEqual(tk.Text.Pos{ .line = 2, .char = 0 }, (try text.search("zig", .at(1, 1), .{})).?);
    try testing.expectEqual(tk.Text.Pos{ .line = 1, .char = 0 }, (try text.search("ZIG", .at(1, 0), .{ .nocase = true })).?);
    try testing.expectEqual(tk.Text.Pos{ .line = 2, .char = 4 }, (try text.search("a[g]+", .at(1, 0), .{ .regexp = true, .stop = .end })).?);
    try testing.expectEqual(null, try text.search("rust", .at(1, 0), .{}));
}

test "text tags, marks and bindings" {
    const root = try initRoot();
    defer root.deinit();

    const text = try tk.Text.init(root, .{});
    try text.insertTagged(.end, "bold", &.{"b"});
    try text.insert(.end, " plain");
    try text.tagConfigure("b", .{ .font = "TkDefaultFont 10 bold", .foreground = "navy", .underline = true });
    try testing.expectEqualStrings("navy", try root.call(.{ text, "tag", "cget", "b", "-foreground" }));

    const range = (try text.tagNextrange("b", .at(1, 0))).?;
    try testing.expectEqual(tk.Text.Pos{ .line = 1, .char = 0 }, range.first);
    try testing.expectEqual(tk.Text.Pos{ .line = 1, .char = 4 }, range.last);
    try testing.expectEqual(tk.Text.Pos{ .line = 1, .char = 4 }, try text.index(I.tagLast("b")));

    try text.tagAdd("hl", .at(1, 5), I.at(1, 5).wordEnd());
    try testing.expectEqualStrings("plain", try text.get(I.tagFirst("hl"), I.tagLast("hl")));
    try text.tagRemove("hl", .at(1, 0), .end);
    try testing.expectEqual(null, try text.tagNextrange("hl", .at(1, 0)));

    try text.markSet("here", .at(1, 2));
    try testing.expectEqual(tk.Text.Pos{ .line = 1, .char = 2 }, try text.index(I.mark("here")));
    try text.markUnset("here");

    const S = struct {
        fn noop(_: tk.Event) void {}
    };
    try text.tagBind("b", "<Button-1>", tk.callbackFn(S.noop));
    try testing.expectEqualStrings("1", try countBindCommands(root));
    try text.destroy();
    try testing.expectEqualStrings("0", try countBindCommands(root));
}

test "text undo and modified flag" {
    const root = try initRoot();
    defer root.deinit();

    const text = try tk.Text.init(root, .{ .undo = true, .autoseparators = false });
    try testing.expect(!try text.editModified());
    try text.insert(.end, "first");
    try text.editSeparator();
    try text.insert(.end, " second");
    try testing.expect(try text.editModified());

    try text.editUndo();
    try testing.expectEqualStrings("first", try text.content());
    try text.editRedo();
    try testing.expectEqualStrings("first second", try text.content());

    try text.setEditModified(false);
    try testing.expect(!try text.editModified());
}

test "canvas items and coordinates" {
    const root = try initRoot();
    defer root.deinit();

    const canvas = try tk.Canvas.init(root, .{ .width = 200, .height = 100, .background = "white", .scrollregion = .{ .x1 = 0, .y1 = 0, .x2 = 500, .y2 = 500 } });
    try testing.expectEqualStrings("4", try root.call(.{ "llength", try canvas.cget(.scrollregion) }));

    const rect = try canvas.createRectangle(.{ .x1 = 10, .y1 = 10, .x2 = 60, .y2 = 40 }, .{ .fill = "red", .tags = &.{ "shape", "box" } });
    try testing.expectEqualStrings("rectangle", try canvas.itemType(rect));
    try canvas.move(rect, 5, -5);
    {
        const pts = try canvas.coords(testing.allocator, rect);
        defer testing.allocator.free(pts);
        try testing.expectEqualSlices(tk.Canvas.Point, &.{ .{ .x = 15, .y = 5 }, .{ .x = 65, .y = 35 } }, pts);
    }
    try canvas.setCoords(rect, &.{ .{ .x = 0, .y = 0 }, .{ .x = 20, .y = 20 } });
    // bboxは枠線の幅だけ外側に広がった近似の矩形を返す
    const box = (try canvas.bbox(rect)).?;
    try testing.expect(box.x1 <= 0 and box.y1 <= 0 and box.x2 >= 20 and box.y2 >= 20);
    try testing.expect(box.x1 >= -2 and box.x2 <= 22);
    // movetoは(座標ではなく)bboxの左上を指定位置に合わせる
    try canvas.moveto(rect, 30, 40);
    const moved = (try canvas.bbox(rect)).?;
    try testing.expectEqual(30, moved.x1);
    try testing.expectEqual(40, moved.y1);

    const line = try canvas.createLine(&.{ .{ .x = 0, .y = 0 }, .{ .x = 50, .y = 50 }, .{ .x = 100, .y = 0 } }, .{ .arrow = .last, .width = 2, .smooth = true });
    const oval = try canvas.createOval(.{ .x1 = 100, .y1 = 10, .x2 = 140, .y2 = 50 }, .{ .outline = "blue", .tags = &.{"shape"} });
    _ = try canvas.createPolygon(&.{ .{ .x = 0, .y = 90 }, .{ .x = 20, .y = 70 }, .{ .x = 40, .y = 90 } }, .{ .fill = "green" });
    _ = try canvas.createArc(.{ .x1 = 150, .y1 = 10, .x2 = 190, .y2 = 50 }, .{ .start = 0, .extent = 90, .style = .pieslice });
    const label = try canvas.createText(.{ .x = 100, .y = 80 }, .{ .text = "hello", .anchor = .center });
    const button = try tk.Button.init(canvas, .{ .text = "in canvas" });
    _ = try canvas.createWindow(.{ .x = 10, .y = 60 }, button, .{ .anchor = .nw });
    try testing.expectEqualStrings("line", try canvas.itemType(line));
    try testing.expect((try canvas.bbox(label)) != null);

    // タグ文字列での一括操作
    try canvas.itemconfigure("shape", tk.Canvas.ShapeOptions{ .outline = "purple" });
    try testing.expectEqualStrings("purple", try canvas.itemcget(rect, "outline"));
    try testing.expectEqualStrings("purple", try canvas.itemcget(oval, "outline"));
    {
        const shapes = try canvas.findWithtag(testing.allocator, "shape");
        defer testing.allocator.free(shapes);
        try testing.expectEqualSlices(tk.Canvas.ItemId, &.{ rect, oval }, shapes);
    }

    try canvas.addtag("special", oval);
    try canvas.dtag(oval, "shape");
    {
        const tags = try canvas.gettags(testing.allocator, oval);
        defer tk.freeStrings(testing.allocator, tags);
        try testing.expectEqual(1, tags.len);
        try testing.expectEqualStrings("special", tags[0]);
    }

    {
        // 塗りつぶしの無い楕円は枠線だけが当たり判定になるため、枠線上(左端の中央)で判定する
        const hits = try canvas.findOverlapping(testing.allocator, .{ .x1 = 99, .y1 = 29, .x2 = 101, .y2 = 31 });
        defer testing.allocator.free(hits);
        try testing.expect(std.mem.indexOfScalar(tk.Canvas.ItemId, hits, oval) != null);
    }
    try testing.expect((try canvas.findClosest(120, 30)) != null);

    try canvas.raiseItems(rect);
    try canvas.lowerItems("special");
    try canvas.delete(line);
    try canvas.clear();
    {
        const all = try canvas.findAll(testing.allocator);
        defer testing.allocator.free(all);
        try testing.expectEqual(0, all.len);
    }
    try testing.expectEqual(null, try canvas.bbox(.all));
}

test "canvas item bindings are released with the canvas" {
    const root = try initRoot();
    defer root.deinit();

    const S = struct {
        fn noop(_: tk.Event) void {}
    };
    const canvas = try tk.Canvas.init(root, .{});
    const rect = try canvas.createRectangle(.{ .x1 = 0, .y1 = 0, .x2 = 10, .y2 = 10 }, .{});
    try canvas.tagBind(rect, "<Enter>", tk.callbackFn(S.noop));
    try canvas.tagBind("shape", "<Leave>", tk.callbackFn(S.noop));
    try testing.expectEqualStrings("2", try countBindCommands(root));
    try canvas.destroy();
    try testing.expectEqualStrings("0", try countBindCommands(root));
}
