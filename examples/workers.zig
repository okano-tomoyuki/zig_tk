//! 複数のワーカースレッドから一定間隔でTextへ行を追記するサンプル。
//!
//! Tcl_Interpは生成したスレッド以外から触ってはいけない。ワーカーの中で app.text.insert(...) を
//! 直接呼ぶと、Debug/ReleaseSafeビルドではpanicで止まる。ワーカーからは root.post で
//! Tkのスレッドへ処理を依頼する(postはどのスレッドから呼んでもよい)。
const std = @import("std");
const tk = @import("zig_tk");
const ttk = tk.ttk;

/// ワーカーからTkのスレッドへ渡す1行。postはこの値を丸ごと複製するので、ワーカー側の
/// バッファは送った直後に使い回してよい。
const Line = struct {
    text: tk.Text,
    buf: [64]u8,
    len: usize,

    fn append(self: Line) !void {
        try self.text.insert(.end, self.buf[0..self.len]);
        try self.text.see(.end);
    }
};

fn worker(io: std.Io, root: tk.Tk, text: tk.Text, running: *std.atomic.Value(bool), id: u32, interval_ms: i64) void {
    var count: u32 = 0;
    while (running.load(.acquire)) {
        io.sleep(.fromMilliseconds(interval_ms), .awake) catch return;
        if (!running.load(.acquire)) break;
        count += 1;
        var line: Line = .{ .text = text, .buf = undefined, .len = 0 };
        line.len = (std.fmt.bufPrint(&line.buf, "[thread {d}] line {d} (every {d}ms)\n", .{ id, count, interval_ms }) catch unreachable).len;
        root.post(line, Line.append) catch return;
    }
}

pub fn main(init: std.process.Init) !void {
    const root = try tk.Tk.init(init.gpa);
    defer root.deinit();
    try root.title("zig_tk workers");
    try root.geometry("480x320");

    const frame = try tk.Frame.init(root, .{});
    try frame.pack(.{ .fill = .both, .expand = true });
    const text = try tk.Text.init(frame, .{ .width = 50, .height = 16 });
    const sb = try ttk.Scrollbar.init(frame, .{});
    try sb.attach(text, .y);
    try sb.pack(.{ .side = .right, .fill = .y });
    try text.pack(.{ .side = .left, .fill = .both, .expand = true });

    // 間隔の異なる2つのワーカーから同じTextへ追記する
    var running: std.atomic.Value(bool) = .init(true);
    const t1 = try std.Thread.spawn(.{}, worker, .{ init.io, root, text, &running, 1, 300 });
    const t2 = try std.Thread.spawn(.{}, worker, .{ init.io, root, text, &running, 2, 700 });

    root.mainloop(); // ウィンドウを閉じると戻る

    // インタプリタを破棄する(defer root.deinit)前に、postする側を全て止める
    running.store(false, .release);
    t1.join();
    t2.join();
}
