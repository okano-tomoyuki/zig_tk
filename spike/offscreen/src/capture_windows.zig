//! Windows: ウィンドウの画素を取り込む。
//! - printWindow: PrintWindow(PW_RENDERFULLCONTENT)。ウィンドウ自身に描かせるため、画面外・他のウィンドウの裏でも取れるはず。
//! - screen: 画面のDCからのBitBlt。実際に画面に出ている画素(比較の基準)。
const std = @import("std");

const HANDLE = ?*anyopaque;
const BOOL = c_int;

const BITMAPINFOHEADER = extern struct {
    biSize: u32 = @sizeOf(BITMAPINFOHEADER),
    biWidth: i32,
    biHeight: i32,
    biPlanes: u16 = 1,
    biBitCount: u16 = 32,
    biCompression: u32 = 0, // BI_RGB
    biSizeImage: u32 = 0,
    biXPelsPerMeter: i32 = 0,
    biYPelsPerMeter: i32 = 0,
    biClrUsed: u32 = 0,
    biClrImportant: u32 = 0,
};

const BITMAPINFO = extern struct {
    bmiHeader: BITMAPINFOHEADER,
    bmiColors: [1]u32 = .{0},
};

extern "user32" fn GetDC(hwnd: HANDLE) callconv(.c) HANDLE;
extern "user32" fn ReleaseDC(hwnd: HANDLE, hdc: HANDLE) callconv(.c) c_int;
extern "user32" fn PrintWindow(hwnd: HANDLE, hdc: HANDLE, flags: u32) callconv(.c) BOOL;
extern "user32" fn SetProcessDPIAware() callconv(.c) BOOL;
extern "gdi32" fn CreateCompatibleDC(hdc: HANDLE) callconv(.c) HANDLE;
extern "gdi32" fn DeleteDC(hdc: HANDLE) callconv(.c) BOOL;
extern "gdi32" fn CreateDIBSection(hdc: HANDLE, bmi: *const BITMAPINFO, usage: u32, bits: *?*anyopaque, section: HANDLE, offset: u32) callconv(.c) HANDLE;
extern "gdi32" fn SelectObject(hdc: HANDLE, obj: HANDLE) callconv(.c) HANDLE;
extern "gdi32" fn DeleteObject(obj: HANDLE) callconv(.c) BOOL;
extern "gdi32" fn BitBlt(dst: HANDLE, x: c_int, y: c_int, w: c_int, h: c_int, src: HANDLE, sx: c_int, sy: c_int, rop: u32) callconv(.c) BOOL;
extern "gdi32" fn GdiFlush() callconv(.c) BOOL;

const POINT = extern struct { x: i32, y: i32 };

extern "user32" fn GetForegroundWindow() callconv(.c) HANDLE;
extern "user32" fn WindowFromPoint(pt: POINT) callconv(.c) HANDLE;
extern "user32" fn GetAncestor(hwnd: HANDLE, flags: u32) callconv(.c) HANDLE;
extern "user32" fn GetWindowLongPtrW(hwnd: HANDLE, index: c_int) callconv(.c) isize;
extern "user32" fn SetWindowLongPtrW(hwnd: HANDLE, index: c_int, value: isize) callconv(.c) isize;
extern "user32" fn SetWindowPos(hwnd: HANDLE, after: HANDLE, x: c_int, y: c_int, cx: c_int, cy: c_int, flags: u32) callconv(.c) BOOL;

const GA_ROOT: u32 = 2;
const GWL_EXSTYLE: c_int = -20;
const WS_EX_TRANSPARENT: isize = 0x20;
const WS_EX_TOOLWINDOW: isize = 0x80;
const WS_EX_LAYERED: isize = 0x80000;
const WS_EX_NOACTIVATE: isize = 0x08000000;
const SWP_NOSIZE: u32 = 0x1;
const SWP_NOMOVE: u32 = 0x2;
const SWP_NOZORDER: u32 = 0x4;
const SWP_NOACTIVATE: u32 = 0x10;
const SWP_FRAMECHANGED: u32 = 0x20;

/// 前面(キーボード入力を受ける)ウィンドウ。
pub fn foreground() usize {
    return @intFromPtr(GetForegroundWindow());
}

/// 画面上の点(x, y)をクリックした時に入力を受けるトップレベルウィンドウ。
pub fn hitTopLevel(x: i32, y: i32) usize {
    return @intFromPtr(GetAncestor(WindowFromPoint(.{ .x = x, .y = y }), GA_ROOT));
}

/// マウスを素通りさせ、クリックされてもアクティブにならず、タスクバーにも出ないようにする。
pub fn makeInputTransparent(hwnd: usize) void {
    const h: HANDLE = @ptrFromInt(hwnd);
    const ex = GetWindowLongPtrW(h, GWL_EXSTYLE);
    _ = SetWindowLongPtrW(h, GWL_EXSTYLE, ex | WS_EX_TRANSPARENT | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW | WS_EX_LAYERED);
    _ = SetWindowPos(h, null, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
}

// ---- Tkを埋め込むための、アクティブにならない透明なウィンドウ ----

const WNDPROC = *const fn (HANDLE, u32, usize, isize) callconv(.c) isize;
const WNDCLASSEXW = extern struct {
    cbSize: u32 = @sizeOf(WNDCLASSEXW),
    style: u32 = 0,
    lpfnWndProc: WNDPROC,
    cbClsExtra: c_int = 0,
    cbWndExtra: c_int = 0,
    hInstance: HANDLE,
    hIcon: HANDLE = null,
    hCursor: HANDLE = null,
    hbrBackground: HANDLE = null,
    lpszMenuName: ?[*:0]const u16 = null,
    lpszClassName: [*:0]const u16,
    hIconSm: HANDLE = null,
};

extern "user32" fn DefWindowProcW(hwnd: HANDLE, msg: u32, wp: usize, lp: isize) callconv(.c) isize;
extern "user32" fn RegisterClassExW(wc: *const WNDCLASSEXW) callconv(.c) u16;
extern "user32" fn CreateWindowExW(ex: u32, class: [*:0]const u16, title: [*:0]const u16, style: u32, x: c_int, y: c_int, w: c_int, h: c_int, parent: HANDLE, menu: HANDLE, inst: HANDLE, param: ?*anyopaque) callconv(.c) HANDLE;
extern "user32" fn DestroyWindow(hwnd: HANDLE) callconv(.c) BOOL;
extern "user32" fn ShowWindow(hwnd: HANDLE, cmd: c_int) callconv(.c) BOOL;
extern "user32" fn SetLayeredWindowAttributes(hwnd: HANDLE, key: u32, alpha: u8, flags: u32) callconv(.c) BOOL;
extern "kernel32" fn GetModuleHandleW(name: ?[*:0]const u16) callconv(.c) HANDLE;

const WS_POPUP: u32 = 0x80000000;
const SW_SHOWNOACTIVATE: c_int = 4;
const LWA_ALPHA: u32 = 2;
const HWND_TOPMOST: HANDLE = @ptrFromInt(@as(usize, @bitCast(@as(isize, -1))));

// Tkの埋め込みプロトコル(win/tkWin.h)。応答しないとTkは確認のダイアログを出して止まる。
const WM_USER: u32 = 0x400;
const TK_CLAIMFOCUS = WM_USER;
const TK_GEOMETRYREQ = WM_USER + 1;
const TK_ATTACHWINDOW = WM_USER + 2;
const TK_GETFRAMEWID = WM_USER + 9;
const TK_STATE = WM_USER + 12;
const TK_INFO = WM_USER + 13;
const TK_CONTAINER_VERIFY: usize = 1;
const TK_CONTAINER_ISAVAILABLE: usize = 2;

fn hostProc(hwnd: HANDLE, msg: u32, wp: usize, lp: isize) callconv(.c) isize {
    const self: isize = @bitCast(@intFromPtr(hwnd));
    return switch (msg) {
        TK_INFO => switch (wp) {
            TK_CONTAINER_VERIFY => self,
            TK_CONTAINER_ISAVAILABLE => 1,
            else => 0,
        },
        TK_ATTACHWINDOW, TK_GETFRAMEWID => self,
        // 埋め込まれた側のフォーカス要求は無視する(利用者の作業中のウィンドウからフォーカスを奪わない)
        TK_CLAIMFOCUS, TK_GEOMETRYREQ => 0,
        TK_STATE => 2, // NormalState(1) + 1
        else => DefWindowProcW(hwnd, msg, wp, lp),
    };
}

extern "user32" fn GetWindowThreadProcessId(hwnd: HANDLE, pid: *u32) callconv(.c) u32;
extern "kernel32" fn GetCurrentProcessId() callconv(.c) u32;

extern "user32" fn GetClassNameA(hwnd: HANDLE, buf: [*]u8, len: c_int) callconv(.c) c_int;
extern "user32" fn IsWindowVisible(hwnd: HANDLE) callconv(.c) BOOL;

/// 調査用: 前面のウィンドウのクラス名と表示状態。
pub fn describeForeground(buf: []u8) []const u8 {
    const h = GetForegroundWindow();
    const n = GetClassNameA(h, buf.ptr, @intCast(buf.len - 8));
    const vis = if (IsWindowVisible(h) != 0) " visible" else " hidden";
    @memcpy(buf[@intCast(n)..][0..vis.len], vis);
    return buf[0 .. @as(usize, @intCast(n)) + vis.len];
}

extern "user32" fn CreateDesktopW(name: [*:0]const u16, device: ?*anyopaque, devmode: ?*anyopaque, flags: u32, access: u32, sa: ?*anyopaque) callconv(.c) HANDLE;
extern "user32" fn SetThreadDesktop(desk: HANDLE) callconv(.c) BOOL;
extern "user32" fn CloseDesktop(desk: HANDLE) callconv(.c) BOOL;
const GENERIC_ALL: u32 = 0x10000000;

/// このスレッドを、利用者に見えない専用のデスクトップへ移す。ウィンドウを1つも作る前に呼ぶ必要がある。
pub fn useHiddenDesktop() !void {
    const name = std.unicode.utf8ToUtf16LeStringLiteral("ZigTkRender");
    const desk = CreateDesktopW(name, null, null, 0, GENERIC_ALL, null) orelse return error.CreateDesktopFailed;
    if (SetThreadDesktop(desk) == 0) return error.SetThreadDesktopFailed;
}

extern "kernel32" fn Sleep(ms: u32) callconv(.c) void;

/// 利用者のデスクトップの前面ウィンドウの監視結果。
pub const ForegroundWatch = struct {
    samples: u32 = 0,
    /// 監視中に前面のウィンドウが一度でも変わったか。
    changed: bool = false,
    /// このプロセスのウィンドウが前面になったか。
    own: bool = false,
    done: std.atomic.Value(bool) = .init(false),
};

/// 呼び出したスレッドのデスクトップ(=利用者のデスクトップ)で、doneになるまで20msごとに前面を調べる。
/// 専用デスクトップへ移る前に別スレッドとして起動する。
pub fn watchForeground(w: *ForegroundWatch) void {
    const initial = GetForegroundWindow();
    while (!w.done.load(.acquire)) {
        if (GetForegroundWindow() != initial) w.changed = true;
        if (foregroundIsOwn()) w.own = true;
        w.samples += 1;
        Sleep(20);
    }
}

/// 前面のウィンドウがこのプロセスのものか(=フォーカスを奪ったか)。
pub fn foregroundIsOwn() bool {
    var pid: u32 = 0;
    _ = GetWindowThreadProcessId(GetForegroundWindow(), &pid);
    return pid == GetCurrentProcessId();
}

/// Tkの画面を `toplevel -use` で埋め込む入れ物を、アクティブ化せずに表示する(不透明度0・マウス素通り・タスクバー非表示)。
pub fn createHost(x: i32, y: i32, w: u32, h: u32) !usize {
    const class = std.unicode.utf8ToUtf16LeStringLiteral("ZigTkRenderHost");
    const inst = GetModuleHandleW(null);
    _ = RegisterClassExW(&.{ .lpfnWndProc = hostProc, .hInstance = inst, .lpszClassName = class });
    const ex: u32 = @intCast(WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW | WS_EX_LAYERED | WS_EX_TRANSPARENT);
    const hwnd = CreateWindowExW(ex, class, class, WS_POPUP, x, y, @intCast(w), @intCast(h), null, null, inst, null) orelse
        return error.CreateWindowFailed;
    _ = SetLayeredWindowAttributes(hwnd, 0, 0, LWA_ALPHA);
    _ = ShowWindow(hwnd, SW_SHOWNOACTIVATE);
    return @intFromPtr(hwnd);
}

/// 検証用: 入れ物を不透明にして最前面に出す(実際の画面と比べるため)。
pub fn revealHost(hwnd: usize) void {
    const h: HANDLE = @ptrFromInt(hwnd);
    _ = SetLayeredWindowAttributes(h, 0, 255, LWA_ALPHA);
    _ = SetWindowPos(h, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
}

pub fn destroyHost(hwnd: usize) void {
    _ = DestroyWindow(@ptrFromInt(hwnd));
}

const PW_CLIENTONLY: u32 = 1;
const PW_RENDERFULLCONTENT: u32 = 2;
const SRCCOPY: u32 = 0x00CC0020;
const CAPTUREBLT: u32 = 0x40000000;

/// 座標を物理ピクセルで扱うため、Tkを初期化する前に呼ぶ(呼ばないと拡大表示の環境で画面の取り込みが拡大後の画素になる)。
pub fn makeDpiAware() void {
    _ = SetProcessDPIAware();
}

pub const Source = union(enum) {
    /// `wm frame .` のHWND(クライアント領域のみを取り込む)。
    print_window: usize,
    /// 画面上の矩形の左上(`winfo rootx/rooty .`)。
    screen: struct { x: i32, y: i32 },
};

/// width×heightのRGB(1画素3バイト、上から下)をgpaで確保して返す。
pub fn capture(gpa: std.mem.Allocator, source: Source, width: u32, height: u32) ![]u8 {
    const screen_dc = GetDC(null) orelse return error.GetDcFailed;
    defer _ = ReleaseDC(null, screen_dc);
    const mem_dc = CreateCompatibleDC(screen_dc) orelse return error.CreateDcFailed;
    defer _ = DeleteDC(mem_dc);

    const bmi: BITMAPINFO = .{ .bmiHeader = .{ .biWidth = @intCast(width), .biHeight = -@as(i32, @intCast(height)) } };
    var bits: ?*anyopaque = null;
    const dib = CreateDIBSection(mem_dc, &bmi, 0, &bits, null, 0) orelse return error.CreateDibFailed;
    defer _ = DeleteObject(dib);
    const old = SelectObject(mem_dc, dib);
    defer _ = SelectObject(mem_dc, old);

    const ok = switch (source) {
        .print_window => |hwnd| PrintWindow(@ptrFromInt(hwnd), mem_dc, PW_CLIENTONLY | PW_RENDERFULLCONTENT),
        .screen => |p| BitBlt(mem_dc, 0, 0, @intCast(width), @intCast(height), screen_dc, p.x, p.y, SRCCOPY | CAPTUREBLT),
    };
    if (ok == 0) return error.CaptureFailed;
    _ = GdiFlush();

    const bgra: [*]const u8 = @ptrCast(bits.?);
    const n: usize = @as(usize, width) * height;
    const rgb = try gpa.alloc(u8, n * 3);
    for (0..n) |i| {
        rgb[i * 3 + 0] = bgra[i * 4 + 2];
        rgb[i * 3 + 1] = bgra[i * 4 + 1];
        rgb[i * 3 + 2] = bgra[i * 4 + 0];
    }
    return rgb;
}
