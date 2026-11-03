//! Listbox + Scrollbarのサンプル: 入力欄から項目を追加・削除し、選択中の項目を表示する。
const std = @import("std");
const tk = @import("zig_tk");
const ttk = tk.ttk;

const App = struct {
    list: tk.Listbox = undefined,
    input: ttk.Entry = undefined,
    status: tk.StringVar,

    fn add(self: *App) !void {
        const text = try self.input.get();
        if (text.len == 0) return;
        try self.list.append(text);
        try self.list.see(.end);
        try self.input.delete(.at(0), .end);
    }

    fn addFromKey(self: *App, _: tk.Event) !void {
        try self.add();
    }

    fn remove(self: *App) !void {
        const i = try self.list.selectedIndex() orelse return;
        try self.list.delete(.at(i), null);
        try self.status.set("削除しました");
    }

    fn onSelect(self: *App, _: tk.Event) !void {
        const i = try self.list.selectedIndex() orelse return;
        var buf: [256]u8 = undefined;
        try self.status.set(try std.fmt.bufPrint(&buf, "{d}: {s}", .{ i, try self.list.get(.at(i)) }));
    }
};

pub fn main(init: std.process.Init) !void {
    const root = try tk.Tk.init(init.gpa);
    defer root.deinit();
    try root.title("zig_tk listbox");

    var app: App = .{ .status = try .init(root, .{ .value = "項目を選択してください" }) };

    const body = try tk.Frame.init(root, .{ .padx = 8, .pady = 8 });
    try body.pack(.{ .fill = .both, .expand = true });

    const list_frame = try tk.Frame.init(body, .{});
    try list_frame.pack(.{ .fill = .both, .expand = true });
    app.list = try tk.Listbox.init(list_frame, .{ .height = 8, .width = 30 });
    const sb = try ttk.Scrollbar.init(list_frame, .{});
    try sb.attach(app.list, .y);
    try app.list.pack(.{ .side = .left, .fill = .both, .expand = true });
    try sb.pack(.{ .side = .right, .fill = .y });
    try app.list.bind("<<ListboxSelect>>", tk.callback(&app, App.onSelect));

    for (0..30) |i| {
        var buf: [32]u8 = undefined;
        try app.list.append(try std.fmt.bufPrint(&buf, "item {d}", .{i}));
    }

    const controls = try tk.Frame.init(body, .{ .pady = 6 });
    try controls.pack(.{ .fill = .x });
    app.input = try ttk.Entry.init(controls, .{});
    try app.input.pack(.{ .side = .left, .fill = .x, .expand = true });
    try app.input.bind("<Return>", tk.callback(&app, App.addFromKey));
    const add = try ttk.Button.init(controls, .{ .text = "追加", .command = tk.callback(&app, App.add) });
    try add.pack(.{ .side = .left, .padx = .all(4) });
    const remove = try ttk.Button.init(controls, .{ .text = "削除", .command = tk.callback(&app, App.remove) });
    try remove.pack(.{ .side = .left });

    const status = try ttk.Label.init(body, .{ .textvariable = app.status });
    try status.pack(.{ .anchor = .w });

    root.mainloop();
}
