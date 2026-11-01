//! ttkウィジェット共通の状態フラグ操作(ttk::widget state / instate)。
const std = @import("std");
const tcl = @import("../tcl.zig");
const interp_mod = @import("../interp.zig");
const Interp = interp_mod.Interp;
const Error = interp_mod.Error;

pub const StateFlag = enum { active, disabled, focus, pressed, selected, background, readonly, alternate, invalid, hover };

/// 状態の指定。trueで「その状態である」、falseで「その状態でない」("!disabled")、nullは指定しない。
/// 例: try button.setState(.{ .disabled = true })
///     style.map("TButton", "foreground", &.{ .{ .state = .{ .pressed = true }, .value = "red" } })
pub const StateSpec = struct {
    active: ?bool = null,
    disabled: ?bool = null,
    focus: ?bool = null,
    pressed: ?bool = null,
    selected: ?bool = null,
    background: ?bool = null,
    readonly: ?bool = null,
    alternate: ?bool = null,
    invalid: ?bool = null,
    hover: ?bool = null,

    /// Tclの状態リスト(例: {pressed !disabled})にする。
    pub fn toTclObj(self: StateSpec, _: *Interp) Error!*tcl.Obj {
        const list = tcl.Tcl_NewListObj(0, null);
        inline for (@typeInfo(StateSpec).@"struct".field_names) |name| {
            if (@field(self, name)) |on| {
                const flag = if (on) name else "!" ++ name;
                _ = tcl.Tcl_ListObjAppendElement(null, list, tcl.Tcl_NewStringObj(flag.ptr, @intCast(flag.len)));
            }
        }
        return list;
    }
};

/// ttk具象Widget型(Self、フィールドw: Widgetを持つ)向けの追加メソッド群。
pub fn Methods(comptime Self: type) type {
    return struct {
        pub fn setState(self: Self, spec: StateSpec) Error!void {
            _ = try self.w.interp.call(.{ self.w.path, "state", spec });
        }

        pub fn instate(self: Self, flag: StateFlag) Error!bool {
            return std.mem.eql(u8, try self.w.interp.call(.{ self.w.path, "instate", flag }), "1");
        }
    };
}
