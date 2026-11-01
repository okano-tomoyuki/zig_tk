//! Notebook + Treeviewのサンプル。
//! タブ1: 入れ子の項目を持つTreeview(見出しクリックで並び順を反転、選択内容を下部に表示)
//! タブ2: メモ用のText
const std = @import("std");
const tk = @import("zig_tk");
const ttk = tk.ttk;
const Treeview = ttk.Treeview;

const App = struct {
    gpa: std.mem.Allocator,
    tree: Treeview = undefined,
    status: tk.StringVar,

    fn onSelect(self: *App, _: tk.Event) !void {
        const item = try self.tree.focus() orelse return;
        var name_buf: [128]u8 = undefined;
        const name = try std.fmt.bufPrint(&name_buf, "{s}", .{try self.tree.itemText(item)});
        var buf: [256]u8 = undefined;
        try self.status.set(try std.fmt.bufPrint(&buf, "{s} ({s})", .{ name, try self.tree.getValue(item, "size") }));
    }

    /// 最上位の項目の並び順を反転する。
    fn reverse(self: *App) !void {
        const items = try self.tree.children(self.gpa, .root);
        defer self.gpa.free(items);
        for (items, 0..) |item, i| try self.tree.move(item, .root, .at(items.len - 1 - i));
    }
};

pub fn main(init: std.process.Init) !void {
    const root = try tk.Tk.init(init.gpa);
    defer root.deinit();
    try root.title("zig_tk explorer");
    try root.geometry("480x360");

    var app: App = .{ .gpa = init.gpa, .status = try .init(root, .{ .value = "項目を選択してください" }) };

    const nb = try ttk.Notebook.init(root, .{ .padding = .all(4) });
    try nb.pack(.{ .fill = .both, .expand = true });

    // ---- タブ1: Treeview ----
    const files = try tk.Frame.init(nb, .{});
    try nb.add(files, .{ .text = "ファイル" });
    app.tree = try Treeview.init(files, .{ .columns = &.{ "size", "kind" }, .show = .tree_headings });
    try app.tree.heading(Treeview.tree_column, .{ .text = "名前 ⇅", .command = tk.callback(&app, App.reverse) });
    try app.tree.heading("size", .{ .text = "サイズ" });
    try app.tree.heading("kind", .{ .text = "種類" });
    try app.tree.column("size", .{ .width = 80, .anchor = .e, .stretch = false });
    try app.tree.column("kind", .{ .width = 80, .stretch = false });
    const sb = try ttk.Scrollbar.init(files, .{});
    try sb.attach(app.tree, .y);
    try sb.pack(.{ .side = .right, .fill = .y });
    try app.tree.pack(.{ .side = .left, .fill = .both, .expand = true });
    try app.tree.tagConfigure("dir", .{ .foreground = "navy" });
    try app.tree.bind("<<TreeviewSelect>>", tk.callback(&app, App.onSelect));

    const src = try app.tree.insert(.root, .end, .{ .text = "src", .values = &.{ "", "folder" }, .open = true, .tags = &.{"dir"} });
    const widgets = try app.tree.insert(src, .end, .{ .text = "widgets", .values = &.{ "", "folder" }, .tags = &.{"dir"} });
    for ([_][2][]const u8{ .{ "button.zig", "2 KB" }, .{ "canvas.zig", "18 KB" }, .{ "text.zig", "14 KB" } }) |f| {
        _ = try app.tree.insert(widgets, .end, .{ .text = f[0], .values = &.{ f[1], "zig" } });
    }
    for ([_][2][]const u8{ .{ "root.zig", "3 KB" }, .{ "interp.zig", "9 KB" }, .{ "value.zig", "5 KB" } }) |f| {
        _ = try app.tree.insert(src, .end, .{ .text = f[0], .values = &.{ f[1], "zig" } });
    }
    _ = try app.tree.insert(.root, .end, .{ .text = "build.zig", .values = &.{ "11 KB", "zig" } });
    _ = try app.tree.insert(.root, .end, .{ .text = "README.md", .values = &.{ "4 KB", "markdown" } });

    // ---- タブ2: メモ ----
    const notes = try tk.Frame.init(nb, .{});
    try nb.add(notes, .{ .text = "メモ" });
    const text = try tk.Text.init(notes, .{ .wrap = .word, .undo = true });
    try text.pack(.{ .fill = .both, .expand = true });
    try text.insert(.end, "ここにメモを書けます。");

    try nb.enableTraversal();
    const status = try ttk.Label.init(root, .{ .textvariable = app.status, .padding = .xy(6, 2) });
    try status.pack(.{ .fill = .x });

    root.mainloop();
}
