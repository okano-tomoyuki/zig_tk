//! Linux(X11): ウィンドウの画素を取り込む。
//! - composite: XCompositeでウィンドウを裏のpixmapへ描かせて取り込む。画面外でも取れるはず。
//! - direct: ウィンドウからXGetImage。Xの仕様上、画面上に見えている範囲でなければBadMatchになる(比較の基準)。
const std = @import("std");

const Display = opaque {};
const XID = c_ulong;

/// Xlib.h の XImage の先頭部分(使うフィールドまで)。
const XImage = extern struct {
    width: c_int,
    height: c_int,
    xoffset: c_int,
    format: c_int,
    data: [*]u8,
    byte_order: c_int,
    bitmap_unit: c_int,
    bitmap_bit_order: c_int,
    bitmap_pad: c_int,
    depth: c_int,
    bytes_per_line: c_int,
    bits_per_pixel: c_int,
    red_mask: c_ulong,
    green_mask: c_ulong,
    blue_mask: c_ulong,
};

const XErrorEvent = extern struct {
    type: c_int,
    display: *Display,
    resourceid: XID,
    serial: c_ulong,
    error_code: u8,
    request_code: u8,
    minor_code: u8,
};

extern fn XOpenDisplay(name: ?[*:0]const u8) ?*Display;
extern fn XCloseDisplay(dpy: *Display) c_int;
extern fn XGetImage(dpy: *Display, d: XID, x: c_int, y: c_int, w: c_uint, h: c_uint, plane_mask: c_ulong, format: c_int) ?*XImage;
extern fn XSync(dpy: *Display, discard: c_int) c_int;
extern fn XFree(data: ?*anyopaque) c_int;
extern fn XFreePixmap(dpy: *Display, pixmap: XID) c_int;
extern fn XSetErrorHandler(handler: ?*const fn (*Display, *XErrorEvent) callconv(.c) c_int) ?*anyopaque;
extern fn XCompositeRedirectWindow(dpy: *Display, window: XID, update: c_int) void;
extern fn XCompositeUnredirectWindow(dpy: *Display, window: XID, update: c_int) void;
extern fn XCompositeNameWindowPixmap(dpy: *Display, window: XID) XID;

const ZPixmap: c_int = 2;
const CompositeRedirectAutomatic: c_int = 0;

var last_error: u8 = 0;

fn onError(_: *Display, ev: *XErrorEvent) callconv(.c) c_int {
    last_error = ev.error_code;
    return 0;
}

pub fn makeDpiAware() void {}

pub const Source = union(enum) {
    /// `winfo id .` のウィンドウ。
    composite: XID,
    direct: XID,
};

/// width×heightのRGB(1画素3バイト、上から下)をgpaで確保して返す。
pub fn capture(gpa: std.mem.Allocator, source: Source, width: u32, height: u32) ![]u8 {
    const dpy = XOpenDisplay(null) orelse return error.OpenDisplayFailed;
    defer _ = XCloseDisplay(dpy);
    _ = XSetErrorHandler(onError);
    last_error = 0;

    var drawable: XID = undefined;
    var pixmap: XID = 0;
    switch (source) {
        .composite => |win| {
            XCompositeRedirectWindow(dpy, win, CompositeRedirectAutomatic);
            _ = XSync(dpy, 0);
            pixmap = XCompositeNameWindowPixmap(dpy, win);
            drawable = pixmap;
        },
        .direct => |win| drawable = win,
    }
    defer if (pixmap != 0) {
        _ = XFreePixmap(dpy, pixmap);
    };

    const img = XGetImage(dpy, drawable, 0, 0, width, height, ~@as(c_ulong, 0), ZPixmap);
    _ = XSync(dpy, 0);
    if (img == null or last_error != 0) {
        std.debug.print("XGetImage failed (X error code {d})\n", .{last_error});
        return error.CaptureFailed;
    }
    defer {
        _ = XFree(img.?.data);
        _ = XFree(img);
    }
    const im = img.?;
    if (im.bits_per_pixel != 32) return error.UnsupportedPixelFormat;

    const n: usize = @as(usize, width) * height;
    const rgb = try gpa.alloc(u8, n * 3);
    for (0..height) |y| {
        const row = im.data + y * @as(usize, @intCast(im.bytes_per_line));
        for (0..width) |x| {
            const px = std.mem.readInt(u32, row[x * 4 ..][0..4], .little);
            const o = (y * width + x) * 3;
            rgb[o + 0] = @truncate(px >> 16);
            rgb[o + 1] = @truncate(px >> 8);
            rgb[o + 2] = @truncate(px);
        }
    }
    return rgb;
}
