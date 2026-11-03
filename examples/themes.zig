//! 同梱のテーマ(Sun Valley)のサンプル。右上のスイッチで明るい/暗いテーマを切り替える。
//! 起動引数に dark を渡すと暗いテーマで起動する。
const std = @import("std");
const tk = @import("zig_tk");
const ttk = tk.ttk;

const App = struct {
    root: tk.Tk,
    dark: tk.BooleanVar,

    fn toggleTheme(self: *App) !void {
        try self.root.setTheme(if (try self.dark.get()) .sun_valley_dark else .sun_valley_light);
    }
};

pub fn main(init: std.process.Init) !void {
    const root = try tk.Tk.init(init.gpa);
    defer root.deinit();
    try root.title("zig_tk themes");

    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const start_dark = args.len > 1 and std.mem.eql(u8, args[1], "dark");
    var app: App = .{ .root = root, .dark = try .init(root, .{ .value = start_dark }) };
    try app.toggleTheme();

    const body = try ttk.Frame.init(root, .{ .padding = .all(16) });
    try body.pack(.{ .fill = .both, .expand = true });

    // 左: チェックボタンとラジオボタン
    const choices = try ttk.Labelframe.init(body, .{ .text = "選択", .padding = .all(12) });
    try choices.grid(.{ .row = 0, .column = 0, .sticky = .nsew, .padx = .all(6) });
    const opt_a: tk.BooleanVar = try .init(root, .{ .value = true });
    const opt_b: tk.BooleanVar = try .init(root, .{});
    const c1 = try ttk.CheckbuttonOf(bool).init(choices, .{ .text = "自動保存", .variable = opt_a });
    try c1.grid(.{ .row = 0, .column = 0, .sticky = .{ .w = true }, .pady = .all(4) });
    const c2 = try ttk.CheckbuttonOf(bool).init(choices, .{ .text = "通知を表示", .variable = opt_b });
    try c2.grid(.{ .row = 1, .column = 0, .sticky = .{ .w = true }, .pady = .all(4) });
    const Size = enum { small, medium, large };
    const size: tk.Variable(Size) = try .init(root, .{ .value = .medium });
    inline for (.{ .{ "小", Size.small }, .{ "中", Size.medium }, .{ "大", Size.large } }, 2..) |r, row| {
        const rb = try ttk.RadiobuttonOf(Size).init(choices, .{ .text = r[0], .variable = size, .value = r[1] });
        try rb.grid(.{ .row = row, .column = 0, .sticky = .{ .w = true }, .pady = .all(4) });
    }

    // 中央: 入力欄とボタン
    const inputs = try ttk.Frame.init(body, .{});
    try inputs.grid(.{ .row = 0, .column = 1, .sticky = .nsew });
    const entry = try ttk.Entry.init(inputs, .{ .width = 22 });
    try entry.insert(.end, "テキストを入力");
    try entry.grid(.{ .row = 0, .column = 0, .sticky = .ew, .pady = .all(4) });
    const spin = try ttk.Spinbox.init(inputs, .{ .from = 0, .to = 100, .increment = 5, .width = 20 });
    try spin.set("25");
    try spin.grid(.{ .row = 1, .column = 0, .sticky = .ew, .pady = .all(4) });
    const combo = try ttk.Combobox.init(inputs, .{ .values = &.{ "Zig", "C", "Tcl" }, .state = .readonly, .width = 20 });
    try combo.setCurrent(0);
    try combo.grid(.{ .row = 2, .column = 0, .sticky = .ew, .pady = .all(4) });
    const button = try ttk.Button.init(inputs, .{ .text = "ボタン" });
    try button.grid(.{ .row = 3, .column = 0, .sticky = .ew, .pady = .all(4) });
    // Sun Valley はアクセントカラーのボタンとトグルボタンのスタイルを持つ
    const accent = try ttk.Button.init(inputs, .{ .text = "アクセントボタン", .style = "Accent.TButton" });
    try accent.grid(.{ .row = 4, .column = 0, .sticky = .ew, .pady = .all(4) });
    const toggle_var: tk.BooleanVar = try .init(root, .{});
    const toggle = try ttk.CheckbuttonOf(bool).init(inputs, .{ .text = "トグルボタン", .variable = toggle_var, .style = "Toggle.TButton" });
    try toggle.grid(.{ .row = 5, .column = 0, .sticky = .ew, .pady = .all(4) });

    // 右: テーマのスイッチ、スライダー、進捗、一覧
    const right = try ttk.Frame.init(body, .{});
    try right.grid(.{ .row = 0, .column = 2, .sticky = .nsew, .padx = .all(6) });
    const dark_switch = try ttk.CheckbuttonOf(bool).init(right, .{
        .text = "ダークモード",
        .variable = app.dark,
        .style = "Switch.TCheckbutton",
        .command = tk.callback(&app, App.toggleTheme),
    });
    try dark_switch.grid(.{ .row = 0, .column = 0, .sticky = .{ .e = true }, .pady = .all(4) });
    const level: tk.DoubleVar = try .init(root, .{ .value = 60 });
    const scale = try ttk.Scale.init(right, .{ .from = 0, .to = 100, .variable = level, .length = 220 });
    try scale.grid(.{ .row = 1, .column = 0, .sticky = .ew, .pady = .all(4) });
    const progress = try ttk.Progressbar.init(right, .{ .maximum = 100, .variable = level });
    try progress.grid(.{ .row = 2, .column = 0, .sticky = .ew, .pady = .all(4) });
    const tree = try ttk.Treeview.init(right, .{ .columns = &.{"size"}, .height = 5 });
    try tree.heading(ttk.Treeview.tree_column, .{ .text = "名前" });
    try tree.heading("size", .{ .text = "サイズ" });
    try tree.column(ttk.Treeview.tree_column, .{ .width = 130 });
    try tree.column("size", .{ .width = 70, .anchor = .e });
    const src = try tree.insert(.root, .end, .{ .text = "src", .open = true });
    _ = try tree.insert(src, .end, .{ .text = "root.zig", .values = &.{"4 KB"} });
    _ = try tree.insert(src, .end, .{ .text = "theme.zig", .values = &.{"3 KB"} });
    _ = try tree.insert(.root, .end, .{ .text = "README.md", .values = &.{"12 KB"} });
    try tree.grid(.{ .row = 3, .column = 0, .sticky = .nsew, .pady = .all(4) });

    root.mainloop();
}
