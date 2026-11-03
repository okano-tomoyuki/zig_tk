//! Tkオプション値の型。enumのタグ名がそのままTclの値になる(例: Relief.raised → "raised")。
const std = @import("std");
const tcl = @import("tcl.zig");
const value = @import("value.zig");
const Interp = @import("interp.zig").Interp;
const Error = @import("interp.zig").Error;

pub const Side = enum { left, right, top, bottom };
pub const Fill = enum { none, x, y, both };
pub const Anchor = enum { n, ne, e, se, s, sw, w, nw, center };
pub const Relief = enum { flat, raised, sunken, groove, ridge, solid };
pub const State = enum { normal, active, disabled, readonly };
pub const Justify = enum { left, center, right };
pub const Orient = enum { horizontal, vertical };
pub const Compound = enum { none, text, image, center, top, bottom, left, right };

/// Entry等の-validate(いつvalidatecommandを呼ぶか)。
pub const Validate = enum {
    none,
    /// フォーカスの出入り時。
    focus,
    focusin,
    focusout,
    /// キー入力などで内容が変わる時。
    key,
    /// 上記すべて。
    all,
};

/// ttkの-padding。例: .padding = .all(8) / .padding = .xy(8, 4) / .padding = .ltrb(1, 2, 3, 4)
pub const Padding = struct {
    left: i32,
    top: i32,
    right: i32,
    bottom: i32,

    pub fn all(n: i32) Padding {
        return .{ .left = n, .top = n, .right = n, .bottom = n };
    }
    pub fn xy(x: i32, y: i32) Padding {
        return .{ .left = x, .top = y, .right = x, .bottom = y };
    }
    pub fn ltrb(left: i32, top: i32, right: i32, bottom: i32) Padding {
        return .{ .left = left, .top = top, .right = right, .bottom = bottom };
    }

    pub fn toTclObj(self: Padding, interp: *Interp) Error!*tcl.Obj {
        return value.toObj(interp, .{ self.left, self.top, self.right, self.bottom });
    }
};

/// pack/gridの-padx/-pady(外側の余白)。例: .padx = .all(8) / .padx = .pair(8, 4)
/// pairは左右(padx)・上下(pady)で異なる余白(Tkの -padx {8 4})。
pub const Pad = struct {
    before: i32,
    after: i32,

    pub fn all(n: i32) Pad {
        return .{ .before = n, .after = n };
    }
    pub fn pair(before: i32, after: i32) Pad {
        return .{ .before = before, .after = after };
    }

    pub fn toTclObj(self: Pad, interp: *Interp) Error!*tcl.Obj {
        if (self.before == self.after) return value.toObj(interp, self.before);
        return value.toObj(interp, .{ self.before, self.after });
    }
};

/// Entry等の文字位置。例: .at(0) / .end / .insert / .sel_first
pub const Index = union(enum) {
    pos: i32,
    end,
    insert,
    anchor,
    sel_first,
    sel_last,

    pub fn at(i: i32) Index {
        return .{ .pos = i };
    }

    pub fn toTclObj(self: Index, interp: *Interp) Error!*tcl.Obj {
        return switch (self) {
            .pos => |i| value.toObj(interp, i),
            .sel_first => value.string("sel.first"),
            .sel_last => value.string("sel.last"),
            else => value.string(@tagName(self)),
        };
    }
};

/// Listbox等の行の位置。例: .at(0) / .end / .active / .anchor
pub const ListIndex = union(enum) {
    pos: usize,
    end,
    /// キーボード操作の対象行(下線表示される行)。
    active,
    /// 範囲選択の起点。
    anchor,

    pub fn at(i: usize) ListIndex {
        return .{ .pos = i };
    }

    pub fn toTclObj(self: ListIndex, interp: *Interp) Error!*tcl.Obj {
        return switch (self) {
            .pos => |i| value.toObj(interp, i),
            else => value.string(@tagName(self)),
        };
    }
};

/// gridの-sticky。例: .sticky = .nsew / .sticky = .{ .w = true, .e = true }
pub const Sticky = struct {
    n: bool = false,
    e: bool = false,
    s: bool = false,
    w: bool = false,

    pub const nsew: Sticky = .{ .n = true, .e = true, .s = true, .w = true };
    pub const ew: Sticky = .{ .e = true, .w = true };
    pub const ns: Sticky = .{ .n = true, .s = true };

    pub fn toTclObj(self: Sticky, _: *Interp) Error!*tcl.Obj {
        var buf: [4]u8 = undefined;
        var len: usize = 0;
        inline for (.{ "n", "s", "e", "w" }) |dir| {
            if (@field(self, dir)) {
                buf[len] = dir[0];
                len += 1;
            }
        }
        return value.string(buf[0..len]);
    }
};
