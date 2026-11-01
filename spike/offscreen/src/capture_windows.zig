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
