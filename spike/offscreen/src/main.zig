//! 技術検証: Tk の画面を画面外(offscreen)に描いて、画像と各Widgetの位置を取り出せるか。
//!
//!     tkrender <画面定義.json> <出力ディレクトリ>
//!
//! 1. 画面外(+-3000+-3000)で画面を組み、組み直し・描き直しの時間を計る
//! 2. 画面外のまま、各Widgetの位置(winfo)と画像を取り出す
//! 3. 画面上に移して同じ画面を取り込み、画面外の画像と画素単位で比べる
//!    (Windows: PrintWindow と、画面からのBitBlt。Linux: XComposite と、ウィンドウからの XGetImage)
//! 4. 画像(PNG)と結果(result.json)を出力する
const std = @import("std");
const builtin = @import("builtin");
const tk = @import("zig_tk");

const capture = if (builtin.os.tag == .windows) @import("capture_windows.zig") else @import("capture_x11.zig");

const WidgetSpec = struct {
    name: []const u8,
    parent: ?[]const u8 = null,
    /// Tkの生成コマンド(例: "ttk::button")。
    class: []const u8,
    options: std.json.ArrayHashMap([]const u8) = .{},
    /// ジオメトリマネージャ(pack / grid / place)。
    manager: []const u8 = "pack",
    layout: std.json.ArrayHashMap([]const u8) = .{},
};

const Spec = struct {
    title: []const u8 = "",
    geometry: []const u8 = "400x300",
    /// 全Widgetを作った後に評価するTcl(grid columnconfigure 等)。
    script: ?[]const u8 = null,
    /// 最後に評価するTcl(初期値の設定等)。
    after: ?[]const u8 = null,
    widgets: []const WidgetSpec,
};

const Rebuild = struct { min: i64, max: i64, avg: i64 };

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const arena = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(arena);
    if (args.len < 3) {
        std.debug.print("usage: tkrender <spec.json> <out_dir>\n", .{});
        return error.InvalidArguments;
    }
    const spec_text = try std.Io.Dir.cwd().readFileAlloc(io, args[1], arena, .unlimited);
    const spec = try std.json.parseFromSliceLeaky(Spec, arena, spec_text, .{});
    const out_dir = args[2];
    try std.Io.Dir.cwd().createDirPath(io, out_dir);

    capture.makeDpiAware();
    if (builtin.os.tag == .windows and args.len > 3 and std.mem.eql(u8, args[3], "embed")) {
        return runEmbed(gpa, arena, io, spec, out_dir);
    }
    if (builtin.os.tag == .windows and args.len > 4 and std.mem.eql(u8, args[3], "desktop")) {
        return runHiddenDesktop(gpa, arena, io, spec, out_dir, args[4]);
    }
    // Tkを起動する前の、前面(Windows)/入力フォーカス(X11)のウィンドウ
    const focus_before = focusNow();
    const root = try tk.Tk.init(gpa);
    defer root.deinit();
    try root.title(spec.title);

    // ---- 1. 画面外で組み立て、時間を計る ----
    // "override": ウィンドウマネージャの管理外にして、表示時にフォーカスを与えられないようにする(X11向けの検証)
    if (args.len > 3 and std.mem.eql(u8, args[3], "override")) _ = try root.call(.{ "wm", "overrideredirect", ".", 1 });
    try root.geometry(try std.fmt.allocPrint(arena, "{s}+-3000+-3000", .{spec.geometry}));
    var t0 = try nowUs(root);
    try build(root, spec);
    try root.update();
    const first_build_us = try nowUs(root) - t0;
    const focus_after_offscreen_map = focusNow();

    const iterations = 20;
    var rebuild: Rebuild = .{ .min = std.math.maxInt(i64), .max = 0, .avg = 0 };
    for (0..iterations) |_| {
        t0 = try nowUs(root);
        try build(root, spec);
        try root.update();
        const d = try nowUs(root) - t0;
        rebuild.min = @min(rebuild.min, d);
        rebuild.max = @max(rebuild.max, d);
        rebuild.avg += d;
    }
    rebuild.avg = @divTrunc(rebuild.avg, iterations);

    // オプションを1つ変えて描き直す(編集1回分)
    t0 = try nowUs(root);
    _ = try root.call(.{ "eval", "foreach w [winfo children .] { catch { $w configure -cursor {} } }" });
    try root.update();
    const edit_us = try nowUs(root) - t0;

    const width: u32 = @intCast(try root.w.winfo(.width));
    const height: u32 = @intCast(try root.w.winfo(.height));
    const geometry_json = try widgetGeometry(arena, root, spec);

    // ---- 2. 画面外のまま取り込む ----
    t0 = try nowUs(root);
    const off = captureOffscreen(gpa, root, width, height) catch |err| blk: {
        std.debug.print("offscreen capture failed: {t}\n", .{err});
        break :blk null;
    };
    defer if (off) |p| gpa.free(p);
    const off_capture_us = try nowUs(root) - t0;

    // ---- 2b. 画面内・不透明度0(利用者には見えない)で取り込む ----
    // 画面外のウィンドウにはOSが描画要求を送らずTkが描かないため、画面内に置いたまま透明にする。
    try root.geometry(try std.fmt.allocPrint(arena, "{d}x{d}+100+100", .{ width, height }));
    _ = try root.call(.{ "wm", "attributes", ".", "-alpha", 0.0 });
    if (builtin.os.tag == .windows) _ = try root.call(.{ "wm", "attributes", ".", "-toolwindow", 1 });
    try root.update();
    try waitMs(root, 300);
    const transparent = captureOffscreen(gpa, root, width, height) catch |err| blk: {
        std.debug.print("transparent capture failed: {t}\n", .{err});
        break :blk null;
    };
    defer if (transparent) |p| gpa.free(p);

    // 透明のウィンドウがフォーカスを奪っていないか・マウスを横取りしないか
    const focus_after_transparent = focusNow();
    var input_json: []const u8 = "null";
    if (builtin.os.tag == .windows) {
        const frame = try frameHandle(root);
        const cx = try root.w.winfo(.rootx) + @as(i32, @intCast(width / 2));
        const cy = try root.w.winfo(.rooty) + @as(i32, @intCast(height / 2));
        const hit_before = capture.hitTopLevel(cx, cy) == frame;
        capture.makeInputTransparent(frame);
        try root.update();
        const hit_after = capture.hitTopLevel(cx, cy) == frame;
        const recaptured = try captureOffscreen(gpa, root, width, height);
        defer gpa.free(recaptured);
        input_json = try std.fmt.allocPrint(arena,
            \\{{ "frame": {d}, "mouse_hits_window": {}, "mouse_hits_window_after_ex_transparent": {}, "capture_diff_after_ex_styles": {s} }}
        , .{ frame, hit_before, hit_after, try diffText(arena, recaptured, transparent) });
    }

    // 透明のまま編集→描画→取り込みを繰り返した時の1回あたりの時間(待ちなし)
    var edit_capture_total: i64 = 0;
    var edit_capture_diff_first: ?[]const u8 = null;
    for (0..10) |i| {
        t0 = try nowUs(root);
        _ = try root.call(.{ ".form.b_ok", "configure", "-text", if (i % 2 == 0) "Cancel" else "OK" });
        try root.update();
        const img = try captureOffscreen(gpa, root, width, height);
        edit_capture_total += try nowUs(root) - t0;
        if (i == 1) edit_capture_diff_first = try diffText(arena, img, transparent);
        gpa.free(img);
    }
    _ = try root.call(.{ "wm", "attributes", ".", "-alpha", 1.0 });

    // ---- 3. 画面上に移して取り込む ----
    try root.geometry(try std.fmt.allocPrint(arena, "{d}x{d}+100+100", .{ width, height }));
    try root.update();
    std.debug.print("debug: after move rootx={d} geo={s}\n", .{ try root.w.winfo(.rootx), try root.call(.{ "wm", "geometry", "." }) });
    _ = try root.call(.{ "wm", "attributes", ".", "-topmost", 1 });
    try root.update();
    std.debug.print("debug: after topmost rootx={d} geo={s}\n", .{ try root.w.winfo(.rootx), try root.call(.{ "wm", "geometry", "." }) });
    try waitMs(root, 500); // ウィンドウマネージャ・DWMが画面に出すまで待つ
    const geometry_on_json = try widgetGeometry(arena, root, spec);
    const on_self = captureOnscreenSelf(gpa, root, width, height) catch |err| blk: {
        std.debug.print("onscreen self capture failed: {t}\n", .{err});
        break :blk null;
    };
    defer if (on_self) |p| gpa.free(p);
    const on_truth = captureOnscreenTruth(gpa, root, width, height) catch |err| blk: {
        std.debug.print("onscreen truth capture failed: {t}\n", .{err});
        break :blk null;
    };
    defer if (on_truth) |p| gpa.free(p);

    if (builtin.os.tag == .windows) debug: {
        const dbg = capture.capture(gpa, .{ .screen = .{ .x = 0, .y = 0 } }, 800, 600) catch break :debug;
        defer gpa.free(dbg);
        try writePng(arena, root, out_dir, "debug_screen.png", dbg, 800, 600);
        std.debug.print("debug: rootx={d} rooty={d} mapped={} state={s}\n", .{ try root.w.winfo(.rootx), try root.w.winfo(.rooty), try root.w.winfoIsmapped(), try root.call(.{ "wm", "state", "." }) });
    }

    if (transparent != null and on_truth != null) {
        var min_x: u32 = width;
        var min_y: u32 = height;
        var max_x: u32 = 0;
        var max_y: u32 = 0;
        for (0..height) |y| for (0..width) |x| {
            const o = (y * width + x) * 3;
            if (!std.mem.eql(u8, transparent.?[o..][0..3], on_truth.?[o..][0..3])) {
                min_x = @min(min_x, @as(u32, @intCast(x)));
                min_y = @min(min_y, @as(u32, @intCast(y)));
                max_x = @max(max_x, @as(u32, @intCast(x)));
                max_y = @max(max_y, @as(u32, @intCast(y)));
            }
        };
        std.debug.print("debug: transparent vs truth diff bbox x={d}..{d} y={d}..{d}\n", .{ min_x, max_x, min_y, max_y });
    }

    // ---- 4. 比較と出力 ----
    try writePng(arena, root, out_dir, "offscreen.png", off, width, height);
    try writePng(arena, root, out_dir, "transparent.png", transparent, width, height);
    try writePng(arena, root, out_dir, "onscreen_self.png", on_self, width, height);
    try writePng(arena, root, out_dir, "onscreen_truth.png", on_truth, width, height);

    var out: std.ArrayList(u8) = .empty;
    try out.print(arena,
        \\{{
        \\  "platform": "{t}",
        \\  "tk": "{s}",
        \\  "tk_scaling": {s},
        \\  "size": [{d}, {d}],
        \\  "time_us": {{ "first_build": {d}, "rebuild_min": {d}, "rebuild_avg": {d}, "rebuild_max": {d}, "edit": {d}, "offscreen_capture": {d} }},
        \\  "diff_pixels": {{ "offscreen_vs_truth": {s}, "transparent_vs_truth": {s}, "onscreen_self_vs_truth": {s} }},
        \\  "edit_and_capture_us_avg": {d}, "edit_capture_no_wait_vs_transparent": {s},
        \\  "focus": {{ "before": {d}, "after_offscreen_map": {d}, "after_transparent_map": {d}, "own_window": {d} }},
        \\  "input": {s},
        \\  "geometry_same_offscreen_onscreen": {},
        \\  "widgets": {s}
        \\}}
        \\
    , .{
        builtin.os.tag,
        try root.call(.{ "info", "patchlevel" }),
        try dupe(arena, try root.call(.{ "tk", "scaling" })),
        width,
        height,
        first_build_us,
        rebuild.min,
        rebuild.avg,
        rebuild.max,
        edit_us,
        off_capture_us,
        try diffText(arena, off, on_truth),
        try diffText(arena, transparent, on_truth),
        try diffText(arena, on_self, on_truth),
        @divTrunc(edit_capture_total, 10),
        edit_capture_diff_first orelse "null",
        focus_before,
        focus_after_offscreen_map,
        focus_after_transparent,
        if (builtin.os.tag == .windows) try frameHandle(root) else try windowId(root),
        input_json,
        std.mem.eql(u8, geometry_json, geometry_on_json),
        geometry_json,
    });
    const result_path = try std.fmt.allocPrint(arena, "{s}/result.json", .{out_dir});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = result_path, .data = out.items });
    std.debug.print("{s}", .{out.items});
}

/// 画面を組み立てる親のパス("" ならルート "."、埋め込みでは ".host")。Tcl側でも $::base で参照できる。
var base: []const u8 = "";

/// specの画面を(既存の子を壊して)組み立てる。
fn build(root: tk.Tk, spec: Spec) !void {
    _ = try root.call(.{ "set", "::base", base });
    _ = try root.call(.{ "eval", "foreach w [winfo children [expr {$::base eq {} ? {.} : $::base}]] { destroy $w }" });
    var path_buf: [256]u8 = undefined;
    for (spec.widgets) |w| {
        const path = try widgetPath(&path_buf, w);
        var create: tk.Cmd = .init(root.w.interp);
        defer create.deinit();
        try create.add(w.class);
        try create.add(path);
        var it = w.options.map.iterator();
        while (it.next()) |e| {
            try create.add(e.key_ptr.*);
            try create.add(e.value_ptr.*);
        }
        _ = try create.eval();

        var place: tk.Cmd = .init(root.w.interp);
        defer place.deinit();
        try place.add(w.manager);
        try place.add(path);
        var lit = w.layout.map.iterator();
        while (lit.next()) |e| {
            try place.add(e.key_ptr.*);
            try place.add(e.value_ptr.*);
        }
        _ = try place.eval();
    }
    if (spec.script) |s| _ = try root.call(.{ "eval", s });
    if (spec.after) |s| _ = try root.call(.{ "eval", s });
}

fn widgetPath(buf: []u8, w: WidgetSpec) ![]const u8 {
    if (w.parent) |p| return std.fmt.bufPrint(buf, "{s}.{s}.{s}", .{ base, p, w.name });
    return std.fmt.bufPrint(buf, "{s}.{s}", .{ base, w.name });
}

/// 専用デスクトップ方式(Windows): Tkのスレッドを利用者に見えないデスクトップへ移してから、通常どおり表示して取り込む。
/// reference_pngは、通常のデスクトップで画面上に表示して取り込んだ画像(通常モードの onscreen_truth.png)。
fn runHiddenDesktop(gpa: std.mem.Allocator, arena: std.mem.Allocator, io: std.Io, spec: Spec, out_dir: []const u8, reference_png: []const u8) !void {
    var cls_buf: [128]u8 = undefined;
    std.debug.print("debug: foreground before: {s}\n", .{capture.describeForeground(&cls_buf)});
    // 利用者のデスクトップに残る監視スレッド(このスレッドが移った後も、元のデスクトップの前面を調べられる)
    var watch: capture.ForegroundWatch = .{};
    const watcher = try std.Thread.spawn(.{}, capture.watchForeground, .{&watch});
    try capture.useHiddenDesktop();
    const root = try tk.Tk.init(gpa);
    defer root.deinit();

    const t0 = try nowUs(root);
    try root.geometry(try std.fmt.allocPrint(arena, "{s}+100+100", .{spec.geometry}));
    try build(root, spec);
    try root.update();
    const first_build_us = try nowUs(root) - t0;
    try waitMs(root, 300);
    std.debug.print("debug: foreground after: {s} own={}\n", .{ capture.describeForeground(&cls_buf), capture.foregroundIsOwn() });

    const width: u32 = @intCast(try root.w.winfo(.width));
    const height: u32 = @intCast(try root.w.winfo(.height));
    var edit_total: i64 = 0;
    for (0..10) |i| {
        const t = try nowUs(root);
        _ = try root.call(.{ ".form.b_ok", "configure", "-text", if (i % 2 == 0) "Cancel" else "OK" });
        try root.update();
        gpa.free(try capture.capture(gpa, .{ .print_window = try frameHandle(root) }, width, height));
        edit_total += try nowUs(root) - t;
    }
    _ = try root.call(.{ ".form.b_ok", "configure", "-text", "OK" });
    try root.update();
    const img = try capture.capture(gpa, .{ .print_window = try frameHandle(root) }, width, height);
    defer gpa.free(img);
    watch.done.store(true, .release);
    watcher.join();
    try writePng(arena, root, out_dir, "desktop.png", img, width, height);

    // 基準の画像と画素単位で比べる(角丸の写り込みがある下端3行は除く)
    const ref = try tk.PhotoImage.init(root, .{ .file = reference_png });
    defer ref.deinit();
    var diff: usize = 0;
    for (0..height - 3) |y| for (0..width) |x| {
        const c = try ref.get(@intCast(x), @intCast(y));
        const o = (y * width + x) * 3;
        if (c.r != img[o] or c.g != img[o + 1] or c.b != img[o + 2]) diff += 1;
    };
    const text = try std.fmt.allocPrint(arena,
        \\{{
        \\  "mode": "hidden_desktop",
        \\  "time_us": {{ "first_build": {d}, "edit_and_capture_avg": {d} }},
        \\  "foreground_stolen": {},
        \\  "user_desktop_watch": {{ "samples": {d}, "foreground_changed": {}, "own_window_became_foreground": {} }},
        \\  "diff_pixels_vs_reference_excluding_bottom_3_rows": {d}
        \\}}
        \\
    , .{ first_build_us, @divTrunc(edit_total, 10), capture.foregroundIsOwn(), watch.samples, watch.changed, watch.own, diff });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = try std.fmt.allocPrint(arena, "{s}/result_desktop.json", .{out_dir}), .data = text });
    std.debug.print("{s}", .{text});
}

/// 埋め込み方式(Windows):アクティブにならない透明なWin32ウィンドウを作り、
/// その中に `toplevel .host -use <HWND>` でTkの画面を埋め込む。ルート "." は表示しない。
/// Tkの最初のトップレベル表示時のアクティブ化(SetActiveWindow)が起きないため、フォーカスを奪わない想定。
fn runEmbed(gpa: std.mem.Allocator, arena: std.mem.Allocator, io: std.Io, spec: Spec, out_dir: []const u8) !void {
    const focus_before = focusNow();
    const root = try tk.Tk.init(gpa);
    defer root.deinit();
    try root.withdraw();

    const x_pos = std.mem.indexOfScalar(u8, spec.geometry, 'x') orelse return error.InvalidGeometry;
    const width = try std.fmt.parseInt(u32, spec.geometry[0..x_pos], 10);
    const height = try std.fmt.parseInt(u32, spec.geometry[x_pos + 1 ..], 10);
    const own_before = capture.foregroundIsOwn();
    var cls_buf: [128]u8 = undefined;
    std.debug.print("debug: foreground before update: {s}\n", .{capture.describeForeground(&cls_buf)});
    try root.update();
    const own_after_withdraw = capture.foregroundIsOwn();
    std.debug.print("debug: foreground after update: {s}\n", .{capture.describeForeground(&cls_buf)});
    const host = try capture.createHost(100, 100, width, height);
    defer capture.destroyHost(host);
    const own_after_host = capture.foregroundIsOwn();

    var t0 = try nowUs(root);
    _ = try root.call(.{ "toplevel", ".host", "-use", try std.fmt.allocPrint(arena, "0x{x}", .{host}), "-width", width, "-height", height });
    _ = try root.call(.{ "pack", "propagate", ".host", 0 });
    _ = try root.call(.{ "grid", "propagate", ".host", 0 });
    base = ".host";
    try build(root, spec);
    try root.update();
    const first_build_us = try nowUs(root) - t0;
    try waitMs(root, 300);
    const focus_after = focusNow();
    std.debug.print("debug: own_foreground before_update={} after_withdraw_update={} after_host={} after_build={}\n", .{ own_before, own_after_withdraw, own_after_host, capture.foregroundIsOwn() });
    const mouse_hits = capture.hitTopLevel(100 + @as(i32, @intCast(width / 2)), 100 + @as(i32, @intCast(height / 2))) == host;

    // 編集→描画→取り込みの時間(待ちなし)
    var edit_total: i64 = 0;
    for (0..10) |i| {
        t0 = try nowUs(root);
        _ = try root.call(.{ ".host.form.b_ok", "configure", "-text", if (i % 2 == 0) "Cancel" else "OK" });
        try root.update();
        gpa.free(try capture.capture(gpa, .{ .print_window = host }, width, height));
        edit_total += try nowUs(root) - t0;
    }
    _ = try root.call(.{ ".host.form.b_ok", "configure", "-text", "OK" });
    try root.update();
    const img = try capture.capture(gpa, .{ .print_window = host }, width, height);
    defer gpa.free(img);

    // 比較の基準: 入れ物を不透明・最前面にして画面から取り込む
    capture.revealHost(host);
    try root.update();
    try waitMs(root, 500);
    const truth = try capture.capture(gpa, .{ .screen = .{ .x = 100, .y = 100 } }, width, height);
    defer gpa.free(truth);

    try writePng(arena, root, out_dir, "embed.png", img, width, height);
    try writePng(arena, root, out_dir, "embed_truth.png", truth, width, height);
    const text = try std.fmt.allocPrint(arena,
        \\{{
        \\  "mode": "embed",
        \\  "time_us": {{ "first_build": {d}, "edit_and_capture_avg": {d} }},
        \\  "focus": {{ "before": {d}, "after": {d}, "host": {d}, "stolen": {} }},
        \\  "mouse_hits_window": {},
        \\  "diff_pixels_embed_vs_truth": {s}
        \\}}
        \\
    , .{ first_build_us, @divTrunc(edit_total, 10), focus_before, focus_after, host, focus_after != focus_before, mouse_hits, try diffText(arena, img, truth) });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = try std.fmt.allocPrint(arena, "{s}/result_embed.json", .{out_dir}), .data = text });
    std.debug.print("{s}", .{text});
}

/// 各Widgetの位置(ウィンドウのクライアント領域からの座標)・大きさ・要求サイズのJSON配列。
fn widgetGeometry(arena: std.mem.Allocator, root: tk.Tk, spec: Spec) ![]const u8 {
    const base_x = try root.w.winfo(.rootx);
    const base_y = try root.w.winfo(.rooty);
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(arena, "[");
    var path_buf: [256]u8 = undefined;
    for (spec.widgets, 0..) |w, i| {
        const path = try widgetPath(&path_buf, w);
        const z: [:0]const u8 = try arena.dupeSentinel(u8, path, 0);
        const widget: tk.Widget = .{ .interp = root.w.interp, .path = z };
        try out.print(arena, "{s}\n    {{ \"path\": \"{s}\", \"x\": {d}, \"y\": {d}, \"width\": {d}, \"height\": {d}, \"reqwidth\": {d}, \"reqheight\": {d} }}", .{
            if (i == 0) "" else ",",
            path,
            try widget.winfo(.rootx) - base_x,
            try widget.winfo(.rooty) - base_y,
            try widget.winfo(.width),
            try widget.winfo(.height),
            try widget.winfo(.reqwidth),
            try widget.winfo(.reqheight),
        });
    }
    try out.appendSlice(arena, "\n  ]");
    return out.items;
}

fn captureOffscreen(gpa: std.mem.Allocator, root: tk.Tk, w: u32, h: u32) ![]u8 {
    return switch (builtin.os.tag) {
        .windows => capture.capture(gpa, .{ .print_window = try frameHandle(root) }, w, h),
        else => capture.capture(gpa, .{ .composite = try windowId(root) }, w, h),
    };
}

/// 画面上でも、画面外と同じ方法(ウィンドウ自身に描かせる)で取り込む。
fn captureOnscreenSelf(gpa: std.mem.Allocator, root: tk.Tk, w: u32, h: u32) ![]u8 {
    return captureOffscreen(gpa, root, w, h);
}

/// 比較の基準: 実際に画面に出ている画素。
fn captureOnscreenTruth(gpa: std.mem.Allocator, root: tk.Tk, w: u32, h: u32) ![]u8 {
    return switch (builtin.os.tag) {
        .windows => capture.capture(gpa, .{ .screen = .{ .x = try root.w.winfo(.rootx), .y = try root.w.winfo(.rooty) } }, w, h),
        else => capture.capture(gpa, .{ .direct = try windowId(root) }, w, h),
    };
}

fn focusNow() usize {
    return if (builtin.os.tag == .windows) capture.foreground() else capture.inputFocus();
}

fn frameHandle(root: tk.Tk) !usize {
    return parseHex(try root.call(.{ "wm", "frame", "." }));
}

fn windowId(root: tk.Tk) !c_ulong {
    return @intCast(try parseHex(try root.call(.{ "winfo", "id", "." })));
}

fn parseHex(s: []const u8) !usize {
    const digits = if (std.mem.startsWith(u8, s, "0x")) s[2..] else s;
    return std.fmt.parseInt(usize, digits, 16);
}

fn diffText(arena: std.mem.Allocator, a: ?[]const u8, b: ?[]const u8) ![]const u8 {
    const x = a orelse return "null";
    const y = b orelse return "null";
    var n: usize = 0;
    var i: usize = 0;
    while (i < x.len) : (i += 3) {
        if (!std.mem.eql(u8, x[i..][0..3], y[i..][0..3])) n += 1;
    }
    return std.fmt.allocPrint(arena, "{d}", .{n});
}

/// RGBをPPMにしてTkのphotoへ読ませ、PNGで書き出す。
fn writePng(arena: std.mem.Allocator, root: tk.Tk, dir: []const u8, name: []const u8, rgb: ?[]const u8, w: u32, h: u32) !void {
    const pixels = rgb orelse return;
    const header = try std.fmt.allocPrint(arena, "P6\n{d} {d}\n255\n", .{ w, h });
    const ppm = try std.mem.concat(arena, u8, &.{ header, pixels });
    const img = try tk.PhotoImage.init(root, .{ .data = .{ .bytes = ppm }, .format = "ppm" });
    defer img.deinit();
    try img.write(try std.fmt.allocPrint(arena, "{s}/{s}", .{ dir, name }), "png");
}

fn nowUs(root: tk.Tk) !i64 {
    return std.fmt.parseInt(i64, try root.call(.{ "clock", "microseconds" }), 10);
}

fn waitMs(root: tk.Tk, ms: u32) !void {
    _ = try root.call(.{ "after", ms, "set ::zt_wait 1" });
    _ = try root.call(.{ "vwait", "::zt_wait" });
}

fn dupe(arena: std.mem.Allocator, s: []const u8) ![]const u8 {
    return arena.dupe(u8, s);
}
