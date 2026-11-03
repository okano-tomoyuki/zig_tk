//! ボタンを押すとラベルのカウントが増える最小サンプル。
const std = @import("std");
const tk = @import("zig_tk");

const App = struct {
    count: u32 = 0,
    label: tk.Label = undefined,

    fn onClick(self: *App) !void {
        self.count += 1;
        var buf: [64]u8 = undefined;
        try self.label.config(.{ .text = try std.fmt.bufPrint(&buf, "Clicked {d} times", .{self.count}) });
    }

    fn onEnter(self: *App, event: tk.Event) !void {
        _ = event;
        try self.label.config(.{ .foreground = "blue" });
    }

    fn onLeave(self: *App, event: tk.Event) !void {
        _ = event;
        try self.label.config(.{ .foreground = "black" });
    }
};

pub fn main(init: std.process.Init) !void {
    const root = try tk.Tk.init(init.gpa);
    defer root.deinit();
    try root.title("zig_tk hello");

    var app: App = .{};
    app.label = try tk.Label.init(root, .{ .text = "Hello, zig_tk!", .relief = .sunken, .padx = 8, .pady = 4 });
    try app.label.pack(.{ .side = .top, .fill = .x, .padx = .all(16), .pady = .all(8) });

    const buttons = try tk.Frame.init(root, .{});
    try buttons.pack(.{ .pady = .all(8) });

    const click = try tk.Button.init(buttons, .{ .text = "Click", .width = 10, .command = tk.callback(&app, App.onClick) });
    try click.grid(.{ .row = 0, .column = 0, .padx = .all(4) });
    try click.bind("<Enter>", tk.callback(&app, App.onEnter));
    try click.bind("<Leave>", tk.callback(&app, App.onLeave));

    const quit = try tk.Button.init(buttons, .{ .text = "Quit", .width = 10, .command = tk.callback(&root, tk.Tk.quit) });
    try quit.grid(.{ .row = 0, .column = 1, .padx = .all(4) });

    root.mainloop();
}
