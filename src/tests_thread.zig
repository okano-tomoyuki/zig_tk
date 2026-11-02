const std = @import("std");
const testing = std.testing;
const tk = @import("root.zig");

fn initRoot() !tk.Tk {
    const root = try tk.Tk.init(testing.allocator);
    _ = try root.call(.{ "wm", "withdraw", "." });
    return root;
}

const Line = struct {
    text: tk.Text,
    buf: [32]u8,
    len: usize,
    done: *std.atomic.Value(u32),
    quit_after: u32,
    root: tk.Tk,

    fn append(self: Line) !void {
        try self.text.insert(.end, self.buf[0..self.len]);
        if (self.done.fetchAdd(1, .monotonic) + 1 == self.quit_after) try self.root.quit();
    }
};

fn worker(root: tk.Tk, text: tk.Text, done: *std.atomic.Value(u32), id: usize, count: usize, total: u32) void {
    std.debug.assert(!root.w.interp.isOwnerThread());
    for (0..count) |i| {
        var line: Line = .{ .text = text, .buf = undefined, .len = 0, .done = done, .quit_after = total, .root = root };
        line.len = (std.fmt.bufPrint(&line.buf, "t{d}-{d}\n", .{ id, i }) catch unreachable).len;
        root.post(line, Line.append) catch unreachable;
    }
}

test "post from several worker threads runs every job on the interpreter thread" {
    const root = try initRoot();
    // quitでルートは破棄されるが、インタプリタはdeinitまで残る
    defer root.deinit();
    try testing.expect(root.w.interp.isOwnerThread());

    const text = try tk.Text.init(root, .{});
    var done: std.atomic.Value(u32) = .init(0);
    const per_thread = 50;
    const n_threads = 3;

    var threads: [n_threads]std.Thread = undefined;
    for (&threads, 0..) |*t, id|
        t.* = try std.Thread.spawn(.{}, worker, .{ root, text, &done, id, per_thread, n_threads * per_thread });

    // 全ジョブの最後がルートを破棄してmainloopを抜ける
    root.mainloop();
    for (threads) |t| t.join();
    try testing.expectEqual(n_threads * per_thread, done.load(.monotonic));
}

const Recorder = struct {
    order_ok: bool = true,
    last: i64 = -1,

    fn record(self: *Recorder, n: i64) !void {
        if (n != self.last + 1) self.order_ok = false;
        self.last = n;
    }

    fn fail(_: *Recorder) !void {
        return error.Boom;
    }
};

const Numbered = struct {
    rec: *Recorder,
    n: i64,
    fn run(self: Numbered) !void {
        return self.rec.record(self.n);
    }
};

test "post keeps order, reports errors through bgerror and drops pending jobs on destroy" {
    {
        const root = try initRoot();
        defer root.deinit();
        _ = try root.call(.{ "proc", "bgerror", "msg", "set ::zt_bgerr $msg" });

        var rec: Recorder = .{};
        // 生成したスレッド自身からpostしてもよい
        for (0..20) |i| try root.post(Numbered{ .rec = &rec, .n = @intCast(i) }, Numbered.run);
        try root.post(&rec, Recorder.fail);
        try root.w.interp.update();
        try root.w.interp.update();
        try testing.expect(rec.order_ok);
        try testing.expectEqual(19, rec.last);
        try testing.expect(std.mem.indexOf(u8, try root.call(.{ "set", "::zt_bgerr" }), "error.Boom") != null);
    }
    {
        var rec: Recorder = .{};
        const root = try initRoot();
        try root.post(Numbered{ .rec = &rec, .n = 0 }, Numbered.run);
        root.deinit();
        // 破棄したインタプリタ宛てのジョブは、同じスレッドの次のインタプリタのイベントループでも実行されない
        const next = try initRoot();
        defer next.deinit();
        try next.w.interp.update();
        try testing.expectEqual(-1, rec.last);
    }
}
