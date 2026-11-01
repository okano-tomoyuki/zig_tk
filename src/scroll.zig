//! スクロールの連携(Scrollbar ⇔ Listbox/Entry/Text/Canvas等)。
//!
//!     try lb.config(.{ .yscrollcommand = sb.setter() });   // Tkinter: yscrollcommand=sb.set
//!     try sb.config(.{ .command = lb.yviewCommand() });    // Tkinter: command=lb.yview
//!     // または両方向をまとめて: try sb.attach(lb, .y);
//!
//! どちらもTclのコマンド文字列で直接つなぐため、Zigのコールバックは介在しない。
const std = @import("std");
const tcl = @import("tcl.zig");
const value = @import("value.zig");
const interp_mod = @import("interp.zig");
const Widget = @import("widget.zig").Widget;
const Interp = interp_mod.Interp;
const Error = interp_mod.Error;

pub const Axis = enum { x, y };

/// xviewScroll/yviewScrollの移動量の単位。
pub const Unit = enum { units, pages };

/// 表示範囲(全体を0〜1とした先頭と末尾の位置)。
pub const Fraction = struct {
    first: f64,
    last: f64,
};

/// Scrollbarの "set" を呼ぶコマンド。xscrollcommand/yscrollcommandに渡す(Scrollbar.setterで得る)。
pub const Setter = struct {
    scrollbar: Widget,

    pub fn toTclObj(self: Setter, interp: *Interp) Error!*tcl.Obj {
        return value.toObj(interp, .{ self.scrollbar.path, "set" });
    }
};

/// Widgetの "xview"/"yview" を呼ぶコマンド。Scrollbarのcommandに渡す(xviewCommand/yviewCommandで得る)。
pub const View = struct {
    target: Widget,
    axis: Axis,

    pub fn toTclObj(self: View, interp: *Interp) Error!*tcl.Obj {
        return value.toObj(interp, .{ self.target.path, if (self.axis == .x) "xview" else "yview" });
    }
};

/// "0.25 0.5" のような2要素の結果をFractionにする。
pub fn parseFraction(interp: *Interp, objs: []const *tcl.Obj) Error!Fraction {
    if (objs.len != 2) return interp.failWith("expected two fractions");
    var f: [2]f64 = undefined;
    for (objs, &f) |obj, *out| {
        if (tcl.Tcl_GetDoubleFromObj(interp.raw, obj, out) != tcl.OK) return interp.fail();
    }
    return .{ .first = f[0], .last = f[1] };
}

/// Scrollbar(classic / ttk)共通のメソッド群。
pub fn ScrollbarMethods(comptime Self: type) type {
    return struct {
        /// つまみの位置(表示範囲)。
        pub fn get(self: Self) Error!Fraction {
            return parseFraction(self.w.interp, try self.w.interp.callList(.{ self.w.path, "get" }));
        }

        /// つまみの位置を設定する(通常は対象Widgetのxscrollcommand/yscrollcommandが呼ぶ)。
        pub fn set(self: Self, first: f64, last: f64) Error!void {
            _ = try self.w.interp.call(.{ self.w.path, "set", first, last });
        }

        /// 対象Widgetのxscrollcommand/yscrollcommandに渡すコマンド。
        pub fn setter(self: Self) Setter {
            return .{ .scrollbar = self.w };
        }

        /// targetのaxis方向のスクロールと双方向に結び付ける。
        /// (targetの[xy]scrollcommandとこのScrollbarのcommand、axisに合わせたorientを設定する)
        pub fn attach(self: Self, target: anytype, axis: Axis) Error!void {
            const t = @import("widget.zig").asWidget(target);
            const interp = self.w.interp;
            const option = if (axis == .x) "-xscrollcommand" else "-yscrollcommand";
            _ = try interp.call(.{ t.path, "configure", option, Setter{ .scrollbar = self.w } });
            _ = try interp.call(.{ self.w.path, "configure", "-command", View{ .target = t, .axis = axis }, "-orient", if (axis == .x) "horizontal" else "vertical" });
        }
    };
}

/// 横方向にスクロールできるWidget(Self、フィールドw: Widgetを持つ)向けのメソッド群。
pub fn XMethods(comptime Self: type) type {
    return AxisMethods(Self, .x);
}

/// 縦方向にスクロールできるWidget向けのメソッド群。
pub fn YMethods(comptime Self: type) type {
    return AxisMethods(Self, .y);
}

fn AxisMethods(comptime Self: type, comptime axis: Axis) type {
    const sub = if (axis == .x) "xview" else "yview";
    return struct {
        /// 現在の表示範囲。
        pub fn view(self: Self) Error!Fraction {
            return parseFraction(self.w.interp, try self.w.interp.callList(.{ self.w.path, sub }));
        }

        /// 全体のfraction(0〜1)の位置が先頭に来るようにスクロールする。
        pub fn moveto(self: Self, fraction: f64) Error!void {
            _ = try self.w.interp.call(.{ self.w.path, sub, "moveto", fraction });
        }

        /// count単位(負なら逆方向)スクロールする。
        pub fn scroll(self: Self, count: i32, unit: Unit) Error!void {
            _ = try self.w.interp.call(.{ self.w.path, sub, "scroll", count, unit });
        }

        /// Scrollbarのcommandに渡すコマンド。
        pub fn command(self: Self) View {
            return .{ .target = self.w, .axis = axis };
        }
    };
}
