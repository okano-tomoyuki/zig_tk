//! Canvasのサンプル: ドラッグで線を描き、右クリックで全消去する。描いた線は "ink" タグでまとめる。
const std = @import("std");
const tk = @import("zig_tk");

const App = struct {
    canvas: tk.Canvas = undefined,
    last: ?tk.Canvas.Point = null,
    strokes: u32 = 0,

    fn press(self: *App, e: tk.Event) !void {
        self.last = .{ .x = @floatFromInt(e.x), .y = @floatFromInt(e.y) };
        self.strokes += 1;
    }

    fn drag(self: *App, e: tk.Event) !void {
        const here: tk.Canvas.Point = .{ .x = @floatFromInt(e.x), .y = @floatFromInt(e.y) };
        if (self.last) |prev| {
            const color = if (self.strokes % 2 == 0) "steelblue" else "tomato";
            _ = try self.canvas.createLine(&.{ prev, here }, .{ .fill = color, .width = 3, .capstyle = .round, .tags = &.{"ink"} });
        }
        self.last = here;
    }

    fn release(self: *App, _: tk.Event) !void {
        self.last = null;
    }

    fn clear(self: *App, _: tk.Event) !void {
        try self.canvas.delete("ink");
    }
};

pub fn main(init: std.process.Init) !void {
    const root = try tk.Tk.init(init.gpa);
    defer root.deinit();
    try root.title("zig_tk sketch");

    var app: App = .{};
    app.canvas = try tk.Canvas.init(root, .{ .width = 480, .height = 320, .background = "white" });
    try app.canvas.pack(.{ .fill = .both, .expand = true });
    _ = try app.canvas.createText(.{ .x = 240, .y = 16 }, .{ .text = "ドラッグで描画 / 右クリックで消去", .fill = "gray50" });

    try app.canvas.bind("<ButtonPress-1>", tk.callback(&app, App.press));
    try app.canvas.bind("<B1-Motion>", tk.callback(&app, App.drag));
    try app.canvas.bind("<ButtonRelease-1>", tk.callback(&app, App.release));
    try app.canvas.bind("<Button-3>", tk.callback(&app, App.clear));

    root.mainloop();
}
