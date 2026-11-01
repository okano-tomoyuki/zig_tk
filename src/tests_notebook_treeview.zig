//! ttk::notebook と ttk::treeview のテスト。
const std = @import("std");
const testing = std.testing;
const tk = @import("root.zig");
const Treeview = tk.ttk.Treeview;
const Item = Treeview.Item;

fn initRoot() !tk.Tk {
    const root = try tk.Tk.init(testing.allocator);
    _ = try root.call(.{ "wm", "withdraw", "." });
    return root;
}

fn countCommands(root: tk.Tk, pattern: []const u8) ![]const u8 {
    return root.call(.{ "llength", try root.call(.{ "info", "commands", pattern }) });
}

test "notebook tabs" {
    const root = try initRoot();
    defer root.deinit();

    const nb = try tk.ttk.Notebook.init(root, .{ .width = 200, .height = 100 });
    try testing.expectEqual(null, try nb.selectedIndex());

    const pages = [_]tk.Frame{
        try tk.Frame.init(nb, .{}),
        try tk.Frame.init(nb, .{}),
        try tk.Frame.init(nb, .{}),
    };
    for (pages, [_][]const u8{ "One", "Two", "Three" }) |page, title| try nb.add(page, .{ .text = title });
    try testing.expectEqual(3, try nb.count());
    // 最初に追加したタブが選択される
    try testing.expectEqual(0, (try nb.selectedIndex()).?);

    try nb.select(pages[1]);
    try testing.expectEqual(1, (try nb.selectedIndex()).?);
    try nb.select(2);
    try testing.expectEqual(2, (try nb.selectedIndex()).?);
    try testing.expectEqual(2, try nb.index(pages[2]));

    try nb.tab(pages[0], .{ .text = "First", .state = .disabled });
    try testing.expectEqualStrings("First", try nb.tabCget(pages[0], "text"));
    try testing.expectEqualStrings("disabled", try nb.tabCget(0, "state"));

    try nb.hide(pages[1]);
    try testing.expectEqualStrings("hidden", try nb.tabCget(pages[1], "state"));

    try nb.forget(pages[0]);
    try testing.expectEqual(2, try nb.count());
    try nb.insert(0, pages[0], .{ .text = "Back" });
    try testing.expectEqual(0, try nb.index(pages[0]));
    try nb.insert(.end, pages[0], .{});
    try testing.expectEqual(2, try nb.index(pages[0]));
    try nb.enableTraversal();
}

test "notebook tab change event" {
    const root = try initRoot();
    defer root.deinit();

    const Counter = struct {
        n: u32 = 0,
        fn inc(self: *@This(), _: tk.Event) void {
            self.n += 1;
        }
    };
    var counter: Counter = .{};
    const nb = try tk.ttk.Notebook.init(root, .{});
    const a = try tk.Frame.init(nb, .{});
    const b = try tk.Frame.init(nb, .{});
    try nb.add(a, .{ .text = "A" });
    try nb.add(b, .{ .text = "B" });
    try nb.pack(.{});
    // 仮想イベントはマップされたウィンドウにしか配送されないため画面外に表示する
    try root.geometry("+-3000+-3000");
    try root.deiconify();
    try root.update();

    try nb.bind("<<NotebookTabChanged>>", tk.callback(&counter, Counter.inc));
    try nb.select(b);
    try root.update();
    try testing.expectEqual(1, counter.n);
}

test "treeview items and hierarchy" {
    const root = try initRoot();
    defer root.deinit();

    const tv = try Treeview.init(root, .{ .columns = &.{ "size", "kind" }, .show = .tree_headings, .selectmode = .extended });
    try tv.heading(Treeview.tree_column, .{ .text = "Name" });
    try tv.heading("size", .{ .text = "Size", .anchor = .e });
    try tv.column("size", .{ .width = 80, .anchor = .e, .stretch = false });

    const src = try tv.insert(.root, .end, .{ .text = "src", .open = true });
    const main_zig = try tv.insert(src, .end, .{ .text = "main.zig", .values = &.{ "1 KB", "zig" } });
    const util = try tv.insert(src, .at(0), .{ .text = "util.zig", .values = &.{ "2 KB", "zig" } });
    const readme = try tv.insert(.root, .end, .{ .id = "readme", .text = "README.md" });
    try testing.expectEqualStrings("readme", readme.id());

    {
        const kids = try tv.children(testing.allocator, src);
        defer testing.allocator.free(kids);
        try testing.expectEqual(2, kids.len);
        try testing.expect(kids[0].eql(util));
        try testing.expect(kids[1].eql(main_zig));
    }
    try testing.expect((try tv.parent(main_zig)).eql(src));
    try testing.expect((try tv.parent(src)).eql(.root));
    try testing.expect((try tv.next(util)).?.eql(main_zig));
    try testing.expectEqual(null, try tv.prev(util));
    try testing.expectEqual(1, try tv.index(main_zig));
    try testing.expect(try tv.exists(readme));

    try testing.expectEqualStrings("main.zig", try tv.itemText(main_zig));
    try testing.expectEqualStrings("1 KB", try tv.getValue(main_zig, "size"));
    try tv.setValue(main_zig, "size", "3 KB");
    {
        const values = try tv.itemValues(testing.allocator, main_zig);
        defer tk.freeStrings(testing.allocator, values);
        try testing.expectEqual(2, values.len);
        try testing.expectEqualStrings("3 KB", values[0]);
        try testing.expectEqualStrings("zig", values[1]);
    }
    try tv.item(readme, .{ .text = "README" });
    try testing.expectEqualStrings("README", try tv.itemText(readme));

    try tv.move(readme, src, .end);
    try testing.expect((try tv.parent(readme)).eql(src));
    try tv.detach(&.{readme});
    try testing.expect((try tv.parent(readme)).eql(.root));
    try tv.move(readme, .root, .at(0));

    try tv.delete(&.{util});
    try testing.expect(!try tv.exists(util));
    try tv.clear();
    try testing.expect(!try tv.exists(src));
    try testing.expect(!try tv.exists(main_zig));
}

test "treeview selection handles ids with spaces" {
    const root = try initRoot();
    defer root.deinit();

    const tv = try Treeview.init(root, .{ .selectmode = .extended });
    const a = try tv.insert(.root, .end, .{ .id = "item with spaces", .text = "a" });
    const b = try tv.insert(.root, .end, .{ .text = "b" });
    const c = try tv.insert(.root, .end, .{ .text = "c" });

    try tv.selectionSet(&.{ a, c });
    {
        const sel = try tv.selection(testing.allocator);
        defer testing.allocator.free(sel);
        try testing.expectEqual(2, sel.len);
        try testing.expectEqualStrings("item with spaces", sel[0].id());
        try testing.expect(sel[1].eql(c));
    }
    try tv.selectionToggle(&.{ a, b });
    try tv.selectionRemove(&.{c});
    try tv.selectionAdd(&.{a});
    {
        const sel = try tv.selection(testing.allocator);
        defer testing.allocator.free(sel);
        try testing.expectEqual(2, sel.len);
        try testing.expect(sel[0].eql(a));
        try testing.expect(sel[1].eql(b));
    }

    try tv.setFocus(b);
    try testing.expect((try tv.focus()).?.eql(b));

    const too_long: [Item.max_len + 1]u8 = @splat('x');
    try testing.expectError(error.TclError, Item.of(&too_long));
}

test "treeview tags and callbacks are released" {
    const root = try initRoot();
    defer root.deinit();

    const S = struct {
        fn noop() void {}
        fn noopEvent(_: tk.Event) void {}
    };
    const tv = try Treeview.init(root, .{ .columns = &.{"size"} });
    const row = try tv.insert(.root, .end, .{ .text = "row", .tags = &.{"odd"} });
    try tv.tagConfigure("odd", .{ .background = "lightgray" });
    try testing.expect(try tv.tagHas("odd", row));
    try testing.expectEqualStrings("lightgray", try root.call(.{ tv, "tag", "configure", "odd", "-background" }));

    try tv.heading("size", .{ .text = "Size", .command = tk.callbackFn(S.noop) });
    try tv.tagBind("odd", "<Double-1>", tk.callbackFn(S.noopEvent));
    try testing.expectEqualStrings("1", try countCommands(root, "::zt_cb*"));
    try testing.expectEqualStrings("1", try countCommands(root, "::zt_bind*"));

    // 見出しのcommandは "heading <col> -command" から呼べる
    _ = try root.call(.{try root.call(.{ tv, "heading", "size", "-command" })});

    try tv.destroy();
    try testing.expectEqualStrings("0", try countCommands(root, "::zt_cb*"));
    try testing.expectEqualStrings("0", try countCommands(root, "::zt_bind*"));
}
