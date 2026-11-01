//! 1行テキストを編集できるWidget(Entry / Spinbox / Combobox)共通のメソッド群。
const std = @import("std");
const types = @import("types.zig");
const Error = @import("interp.zig").Error;
const Index = types.Index;

/// Self(フィールドw: Widgetを持つ)向け。各Widget型で `pub const get = E.get;` のように公開する。
pub fn Methods(comptime Self: type) type {
    return struct {
        /// 入力中の文字列。次のTcl呼び出しまで有効。
        pub fn get(self: Self) Error![]const u8 {
            return self.w.interp.call(.{ self.w.path, "get" });
        }

        pub fn insert(self: Self, pos: Index, text: []const u8) Error!void {
            _ = try self.w.interp.call(.{ self.w.path, "insert", pos, text });
        }

        /// first〜last(lastを含まない)の文字を削除する。lastがnullならfirstの1文字のみ。
        pub fn delete(self: Self, first: Index, last: ?Index) Error!void {
            if (last) |l| {
                _ = try self.w.interp.call(.{ self.w.path, "delete", first, l });
            } else {
                _ = try self.w.interp.call(.{ self.w.path, "delete", first });
            }
        }

        pub fn icursor(self: Self, pos: Index) Error!void {
            _ = try self.w.interp.call(.{ self.w.path, "icursor", pos });
        }

        /// iを数値の文字位置に解決する。
        pub fn index(self: Self, i: Index) Error!i32 {
            const result = try self.w.interp.call(.{ self.w.path, "index", i });
            return std.fmt.parseInt(i32, result, 10) catch error.TclError;
        }

        pub fn selectionRange(self: Self, start: Index, end: Index) Error!void {
            _ = try self.w.interp.call(.{ self.w.path, "selection", "range", start, end });
        }

        pub fn selectionClear(self: Self) Error!void {
            _ = try self.w.interp.call(.{ self.w.path, "selection", "clear" });
        }

        /// 現在の内容でvalidatecommandを呼び(reason = .forced)、その結果を返す。
        pub fn validateNow(self: Self) Error!bool {
            return std.mem.eql(u8, try self.w.interp.call(.{ self.w.path, "validate" }), "1");
        }
    };
}
