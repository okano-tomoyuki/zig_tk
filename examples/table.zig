//! Tableのサンプル: 構造体の配列を表で表示・編集する。
//! 見出しのクリックで並べ替え、セルのダブルクリックで編集(役割は選択肢から、在籍はダブルクリックで切り替え)。
//! 起動引数に dark を渡すと暗いテーマで起動する。
const std = @import("std");
const tk = @import("zig_tk");
const ttk = tk.ttk;

const Role = enum { developer, designer, manager, sales };

const Member = struct {
    name: []const u8,
    age: u32,
    role: Role,
    active: bool,
    rating: ?f64 = null,
};

const Members = tk.Table(Member);

const App = struct {
    table: *Members,
    status: tk.StringVar,

    fn edited(self: *App, row: usize, field: Members.Field) !void {
        const m = self.table.get(row);
        var buf: [128]u8 = undefined;
        try self.status.set(try std.fmt.bufPrint(&buf, "{s} の {s} を変更しました", .{ m.name, @tagName(field) }));
    }

    fn add(self: *App) !void {
        const i = try self.table.append(.{ .name = "新しいメンバー", .age = 20, .role = .developer, .active = true });
        try self.table.select(i);
        try self.table.beginEdit(i, .name);
    }

    fn remove(self: *App) !void {
        const sel = try self.table.selection(self.table.gpa);
        defer self.table.gpa.free(sel);
        var i = sel.len;
        while (i > 0) : (i -= 1) try self.table.remove(sel[i - 1]);
    }
};

pub fn main(init: std.process.Init) !void {
    const root = try tk.Tk.init(init.gpa);
    defer root.deinit();
    try root.title("zig_tk table");

    const args = try init.minimal.args.toSlice(init.arena.allocator());
    try root.setTheme(if (args.len > 1 and std.mem.eql(u8, args[1], "dark")) .sun_valley_dark else .sun_valley_light);

    const body = try ttk.Frame.init(root, .{ .padding = .all(12) });
    try body.pack(.{ .fill = .both, .expand = true });

    const toolbar = try ttk.Frame.init(body, .{});
    try toolbar.pack(.{ .fill = .x, .pady = 6 });

    const list = try ttk.Frame.init(body, .{});
    try list.pack(.{ .fill = .both, .expand = true });
    const table = try Members.init(init.gpa, list, .{
        .editable = true,
        .height = 8,
        .columns = &.{
            .{ .field = .name, .heading = "名前", .width = 160 },
            .{ .field = .age, .heading = "年齢", .width = 60 },
            .{ .field = .role, .heading = "役割", .width = 110 },
            .{ .field = .active, .heading = "在籍", .width = 60, .anchor = .center },
            .{ .field = .rating, .heading = "評価", .width = 70, .decimals = 1 },
        },
    });
    defer table.deinit();
    const sb = try ttk.Scrollbar.init(list, .{});
    try sb.attach(table.treeview(), .y);
    try sb.pack(.{ .side = .right, .fill = .y });
    try table.pack(.{ .side = .left, .fill = .both, .expand = true });

    try table.setRows(&.{
        .{ .name = "佐藤 花子", .age = 34, .role = .manager, .active = true, .rating = 4.5 },
        .{ .name = "鈴木 一郎", .age = 28, .role = .developer, .active = true, .rating = 4.0 },
        .{ .name = "高橋 美咲", .age = 25, .role = .designer, .active = true },
        .{ .name = "田中 健", .age = 41, .role = .sales, .active = false, .rating = 3.5 },
        .{ .name = "伊藤 さくら", .age = 31, .role = .developer, .active = true, .rating = 4.8 },
        .{ .name = "渡辺 大輔", .age = 37, .role = .developer, .active = false, .rating = 3.9 },
    });

    var app: App = .{ .table = table, .status = try .init(root, .{ .value = "見出しで並べ替え、ダブルクリックで編集" }) };
    table.onEdit(&app, App.edited);

    const add = try ttk.Button.init(toolbar, .{ .text = "追加", .style = "Accent.TButton", .command = tk.callback(&app, App.add) });
    try add.pack(.{ .side = .left });
    const del = try ttk.Button.init(toolbar, .{ .text = "選択行を削除", .command = tk.callback(&app, App.remove) });
    try del.pack(.{ .side = .left, .padx = 6 });
    const status = try ttk.Label.init(body, .{ .textvariable = app.status });
    try status.pack(.{ .anchor = .w, .pady = 6 });

    try table.sortBy(.age, false);
    root.mainloop();
}
