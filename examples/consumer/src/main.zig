const std = @import("std");
const tk = @import("zig_tk");

pub fn main(init: std.process.Init) !void {
    const root = try tk.Tk.init(init.gpa);
    defer root.deinit();
    try root.title("zig_tk consumer");

    const label = try tk.ttk.Label.init(root, .{ .text = "zig_tk をパッケージとして利用しています", .padding = .all(12) });
    try label.pack(.{});
    const quit = try tk.ttk.Button.init(root, .{ .text = "Quit", .command = tk.callback(&root, tk.Tk.quit) });
    try quit.pack(.{ .pady = 8 });

    root.mainloop();
}
