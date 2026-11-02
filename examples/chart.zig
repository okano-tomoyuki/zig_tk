//! Chartのサンプル: 50msごとに2つの系列へ点を追加し、直近300点を流れるように表示する。
//! 起動引数に dark を渡すと暗いテーマで起動する。
const std = @import("std");
const tk = @import("zig_tk");
const ttk = tk.ttk;

const App = struct {
    root: tk.Tk,
    chart: *tk.Chart,
    sine: tk.Chart.SeriesId,
    noise: tk.Chart.SeriesId,
    prng: std.Random.DefaultPrng,
    t: f64 = 0,
    running: tk.BooleanVar,

    fn tick(self: *App) !void {
        if (try self.running.get()) {
            self.t += 0.05;
            try self.chart.append(self.sine, self.t, @sin(self.t * 2) * 10 + 20);
            const r = self.prng.random().floatNorm(f64);
            try self.chart.append(self.noise, self.t, 15 + @cos(self.t * 0.7) * 4 + r);
        }
        _ = try self.root.after(50, tk.callback(self, tick));
    }
};

pub fn main(init: std.process.Init) !void {
    const root = try tk.Tk.init(init.gpa);
    defer root.deinit();
    try root.title("zig_tk chart");

    const args = try init.minimal.args.toSlice(init.arena.allocator());
    try root.setTheme(if (args.len > 1 and std.mem.eql(u8, args[1], "dark")) .sun_valley_dark else .sun_valley_light);

    const body = try ttk.Frame.init(root, .{ .padding = .all(8) });
    try body.pack(.{ .fill = .both, .expand = true });

    const chart = try tk.Chart.init(init.gpa, body, .{ .width = 560, .height = 320, .title = "センサーの値", .x_label = "時刻 [s]", .y_label = "温度 [°C]" });
    defer chart.deinit();
    try chart.pack(.{ .fill = .both, .expand = true });

    var app: App = .{
        .root = root,
        .chart = chart,
        .sine = try chart.addSeries(.{ .label = "センサーA", .max_points = 300 }),
        .noise = try chart.addSeries(.{ .label = "センサーB", .max_points = 300 }),
        .prng = .init(42),
        .running = try .init(root, .{ .value = true }),
    };
    const pause = try ttk.CheckbuttonOf(bool).init(body, .{ .text = "更新する", .variable = app.running, .style = "Switch.TCheckbutton" });
    try pause.pack(.{ .anchor = .e, .pady = 4 });

    try app.tick();
    root.mainloop();
}
