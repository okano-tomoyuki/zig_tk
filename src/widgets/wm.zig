//! トップレベルウィンドウ(Tk / Toplevel)共通のウィンドウマネージャ操作(Python tkinter.Wm相当)。
const std = @import("std");
const PhotoImage = @import("../image.zig").PhotoImage;
const callback = @import("../callback.zig");
const Error = @import("../interp.zig").Error;

/// protocolで扱うウィンドウマネージャのプロトコル。
pub const Protocol = enum {
    /// ウィンドウの閉じるボタン。ハンドラを設定するとTkは自動で閉じなくなる。
    delete_window,
    take_focus,
    save_yourself,

    fn tclName(self: Protocol) []const u8 {
        return switch (self) {
            .delete_window => "WM_DELETE_WINDOW",
            .take_focus => "WM_TAKE_FOCUS",
            .save_yourself => "WM_SAVE_YOURSELF",
        };
    }
};

pub fn Methods(comptime Self: type) type {
    return struct {
        pub fn title(self: Self, text: []const u8) Error!void {
            _ = try self.w.interp.call(.{ "wm", "title", self.w.path, text });
        }

        /// 例: geometry("320x200+100+100")
        pub fn geometry(self: Self, spec: []const u8) Error!void {
            _ = try self.w.interp.call(.{ "wm", "geometry", self.w.path, spec });
        }

        pub fn withdraw(self: Self) Error!void {
            _ = try self.w.interp.call(.{ "wm", "withdraw", self.w.path });
        }

        pub fn deiconify(self: Self) Error!void {
            _ = try self.w.interp.call(.{ "wm", "deiconify", self.w.path });
        }

        pub fn iconify(self: Self) Error!void {
            _ = try self.w.interp.call(.{ "wm", "iconify", self.w.path });
        }

        pub fn resizable(self: Self, width: bool, height: bool) Error!void {
            _ = try self.w.interp.call(.{ "wm", "resizable", self.w.path, width, height });
        }

        pub fn minsize(self: Self, width: i32, height: i32) Error!void {
            _ = try self.w.interp.call(.{ "wm", "minsize", self.w.path, width, height });
        }

        pub fn maxsize(self: Self, width: i32, height: i32) Error!void {
            _ = try self.w.interp.call(.{ "wm", "maxsize", self.w.path, width, height });
        }

        /// タイトルバー等に表示するアイコン。as_defaultがtrueなら以後作るToplevelにも使う。
        pub fn iconphoto(self: Self, image: PhotoImage, as_default: bool) Error!void {
            if (as_default) {
                _ = try self.w.interp.call(.{ "wm", "iconphoto", self.w.path, "-default", image });
            } else {
                _ = try self.w.interp.call(.{ "wm", "iconphoto", self.w.path, image });
            }
        }

        /// ウィンドウを最前面に出す。
        pub fn lift(self: Self) Error!void {
            _ = try self.w.interp.call(.{ "raise", self.w.path });
        }

        /// ウィンドウマネージャのプロトコル(閉じるボタン等)にハンドラを設定する。
        /// コールバックはウィンドウの破棄時に解放される。
        pub fn protocol(self: Self, which: Protocol, cb: callback.Callback) Error!void {
            var buf: [256]u8 = undefined;
            const name = std.fmt.bufPrintSentinel(&buf, "zt_cb{s}-protocol-{s}", .{ self.w.path, which.tclName() }, 0) catch
                return error.OutOfMemory;
            try callback.register(self.w.interp, name, cb);
            _ = try self.w.interp.call(.{ "wm", "protocol", self.w.path, which.tclName(), name });
        }
    };
}
