//! after(タイマー)と標準ダイアログのサンプル。
const std = @import("std");
const tk = @import("zig_tk");
const ttk = tk.ttk;

const App = struct {
    root: tk.Tk,
    status: tk.StringVar,
    elapsed: tk.StringVar,
    seconds: u32 = 0,
    swatch: tk.Frame = undefined,

    /// 1秒ごとに自分自身を再予約して経過時間を更新する。
    fn tick(self: *App) !void {
        self.seconds += 1;
        var buf: [32]u8 = undefined;
        try self.elapsed.set(try std.fmt.bufPrint(&buf, "{d} 秒経過", .{self.seconds}));
        _ = try self.root.after(1000, tk.callback(self, App.tick));
    }

    fn ask(self: *App) !void {
        const answer = try tk.messagebox.askyesnocancel(self.root, "確認", "保存しますか?", .{ .detail = "キャンセルすると何もしません" });
        try self.status.set(if (answer) |yes| (if (yes) "はい" else "いいえ") else "キャンセル");
    }

    fn open(self: *App) !void {
        const types = [_]tk.filedialog.FileType{
            .{ .name = "Zig source", .patterns = &.{ ".zig", ".zon" } },
            .{ .name = "All files", .patterns = &.{"*"} },
        };
        const path = try tk.filedialog.askopenfilename(self.root, .{ .title = "ファイルを開く", .filetypes = &types });
        try self.status.set(path orelse "(キャンセル)");
    }

    fn pickColor(self: *App) !void {
        const color = try tk.colorchooser.askcolor(self.root, .{ .initialcolor = .{ .r = 0x33, .g = 0x66, .b = 0x99 } }) orelse return;
        var buf: [7]u8 = undefined;
        try self.swatch.config(.{ .background = color.hex(&buf) });
        try self.status.set(color.hex(&buf));
    }
};

pub fn main(init: std.process.Init) !void {
    const root = try tk.Tk.init(init.gpa);
    defer root.deinit();
    try root.title("zig_tk dialogs");

    var app: App = .{
        .root = root,
        .status = try .init(root, .{ .value = "ボタンを押してください" }),
        .elapsed = try .init(root, .{ .value = "0 秒経過" }),
    };

    const body = try tk.Frame.init(root, .{ .padx = 12, .pady = 12 });
    try body.pack(.{ .fill = .both, .expand = true });

    const clock = try ttk.Label.init(body, .{ .textvariable = app.elapsed });
    try clock.grid(.{ .row = 0, .column = 0, .columnspan = 3, .pady = .all(4) });

    const buttons = [_]struct { []const u8, tk.Callback }{
        .{ "質問", tk.callback(&app, App.ask) },
        .{ "開く", tk.callback(&app, App.open) },
        .{ "色", tk.callback(&app, App.pickColor) },
    };
    for (buttons, 0..) |entry, i| {
        const b = try ttk.Button.init(body, .{ .text = entry[0], .command = entry[1] });
        try b.grid(.{ .row = 1, .column = @intCast(i), .padx = .all(4) });
    }

    app.swatch = try tk.Frame.init(body, .{ .width = 200, .height = 24, .relief = .sunken, .borderwidth = 1 });
    try app.swatch.grid(.{ .row = 2, .column = 0, .columnspan = 3, .pady = .all(6) });

    const status = try ttk.Label.init(body, .{ .textvariable = app.status, .foreground = "gray25" });
    try status.grid(.{ .row = 3, .column = 0, .columnspan = 3 });

    _ = try root.after(1000, tk.callback(&app, App.tick));
    root.mainloop();
}
