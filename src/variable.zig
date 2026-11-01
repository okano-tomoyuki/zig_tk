//! Tcl変数と結び付く値(Python tkinter.StringVar/IntVar/DoubleVar/BooleanVar相当)。
//! ハンドルは「インタプリタ + 変数名」だけを持つ値型で、自由にコピーできる。
//! 変数自体はインタプリタ破棄(またはdeinit)まで残る。
const std = @import("std");
const tcl = @import("tcl.zig");
const value = @import("value.zig");
const callback = @import("callback.zig");
const widget = @import("widget.zig");
const interp_mod = @import("interp.zig");
const Interp = interp_mod.Interp;
const Error = interp_mod.Error;

pub const StringVar = Variable([]const u8);
pub const IntVar = Variable(i64);
pub const DoubleVar = Variable(f64);
pub const BooleanVar = Variable(bool);

/// traceAddに渡す監視対象の操作。
pub const TraceMode = enum { array, read, write, unset };

/// traceAddが返す登録ID(traceRemoveに渡す)。
pub const TraceId = struct { command: [:0]const u8 };

/// Tを値とするTcl変数。Tは []const u8 / i64 / f64 / bool / enum。
/// enumはタグ名の文字列として格納される(例: Variable(Size)に.mediumを入れるとTcl側は "medium")。
pub fn Variable(comptime T: type) type {
    const default: T = switch (T) {
        []const u8 => "",
        i64 => 0,
        f64 => 0.0,
        bool => false,
        else => switch (@typeInfo(T)) {
            // 既定値は最初のタグ(Radiobutton等で全ボタンが未選択表示になるのを避ける)
            .@"enum" => |e| @field(T, e.field_names[0]),
            else => @compileError("zig_tk: unsupported variable type " ++ @typeName(T)),
        },
    };

    return struct {
        const Self = @This();

        interp: *Interp,
        name: [:0]const u8,

        pub const Options = struct {
            value: T = default,
        };

        /// masterは同じインタプリタに属する任意のWidget(Tk等)。
        pub fn init(master: anytype, opts: Options) Error!Self {
            const interp = widget.asWidget(master).interp;
            const self: Self = .{ .interp = interp, .name = try interp.uniqueName("zt_var") };
            try self.set(opts.value);
            return self;
        }

        /// 変数を削除する。traceAddで登録したコールバックも解放される(unsetとしては発火しない)。
        pub fn deinit(self: Self) void {
            _ = self.interp.call(.{ "::zt_var_free", self.name }) catch {};
        }

        /// 現在値。StringVarの戻り値は変数が次に変更されるまで有効。
        pub fn get(self: Self) Error!T {
            const obj = tcl.Tcl_GetVar2Ex(self.interp.raw, self.name.ptr, null, tcl.GLOBAL_ONLY | tcl.LEAVE_ERR_MSG) orelse
                return self.interp.fail();
            const raw = self.interp.raw;
            switch (T) {
                []const u8 => return tcl.getString(obj),
                i64 => {
                    var v: tcl.WideInt = 0;
                    if (tcl.Tcl_GetWideIntFromObj(raw, obj, &v) != tcl.OK) return self.interp.fail();
                    return v;
                },
                f64 => {
                    var v: f64 = 0;
                    if (tcl.Tcl_GetDoubleFromObj(raw, obj, &v) != tcl.OK) return self.interp.fail();
                    return v;
                },
                bool => {
                    var v: c_int = 0;
                    if (tcl.Tcl_GetBooleanFromObj(raw, obj, &v) != tcl.OK) return self.interp.fail();
                    return v != 0;
                },
                else => {
                    const s = tcl.getString(obj);
                    return std.meta.stringToEnum(T, s) orelse
                        self.interp.failWith("invalid value for " ++ @typeName(T) ++ " variable");
                },
            }
        }

        pub fn set(self: Self, v: T) Error!void {
            const obj = try value.toObj(self.interp, v);
            if (tcl.Tcl_SetVar2Ex(self.interp.raw, self.name.ptr, null, obj, tcl.GLOBAL_ONLY | tcl.LEAVE_ERR_MSG) == null)
                return self.interp.fail();
        }

        /// 変数の操作時にcbを呼ぶ(Python Variable.trace_add相当)。
        pub fn traceAdd(self: Self, mode: TraceMode, cb: callback.Callback) Error!TraceId {
            const command = try self.interp.uniqueName("zt_trace");
            try callback.register(self.interp, command, cb);
            _ = try self.interp.call(.{ "trace", "add", "variable", self.name, mode, command });
            return .{ .command = command };
        }

        pub fn traceRemove(self: Self, mode: TraceMode, id: TraceId) Error!void {
            _ = try self.interp.call(.{ "trace", "remove", "variable", self.name, mode, id.command });
            _ = tcl.Tcl_DeleteCommand(self.interp.raw, id.command.ptr);
        }

        pub fn toTclObj(self: Self, _: *Interp) Error!*tcl.Obj {
            return value.string(self.name);
        }
    };
}
