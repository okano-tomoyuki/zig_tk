//! Zigの値 → Tcl_Objの変換。型による分岐は全てcomptimeに解決される。
//!
//! | Zigの型                         | Tcl値                         |
//! |---------------------------------|-------------------------------|
//! | 整数 / comptime_int / bool      | 整数                          |
//! | 浮動小数点 / comptime_float     | 実数                          |
//! | 文字列([]const u8, リテラル等)  | 文字列                        |
//! | enum / enum literal             | @tagName(.raised → "raised")  |
//! | タプル / 配列 / スライス        | リスト(入れ子可)              |
//! | toTclObjを持つ型(Widget等)      | 型ごとの変換(パス名等)        |
//! | ?T                              | nullなら空文字列              |
const std = @import("std");
const tcl = @import("tcl.zig");
const interp_mod = @import("interp.zig");
const callback = @import("callback.zig");
const Interp = interp_mod.Interp;
const Cmd = interp_mod.Cmd;
const Error = interp_mod.Error;

pub fn toObj(interp: *Interp, v: anytype) Error!*tcl.Obj {
    const T = @TypeOf(v);
    if (T == *tcl.Obj) return v;
    switch (@typeInfo(T)) {
        .@"struct", .@"union", .@"enum" => if (@hasDecl(T, "toTclObj")) return v.toTclObj(interp),
        else => {},
    }
    switch (@typeInfo(T)) {
        .int, .comptime_int => return tcl.Tcl_NewWideIntObj(@intCast(v)),
        .float, .comptime_float => return tcl.Tcl_NewDoubleObj(@floatCast(v)),
        .bool => return tcl.Tcl_NewWideIntObj(@intFromBool(v)),
        .@"enum", .enum_literal => return string(@tagName(v)),
        .optional => return if (v) |x| toObj(interp, x) else string(""),
        .array => |a| return if (a.child == u8) string(&v) else list(interp, &v),
        .pointer => |p| switch (p.size) {
            .slice => return if (p.child == u8) string(v) else list(interp, v),
            .one => switch (@typeInfo(p.child)) {
                .array => |a| return if (a.child == u8) string(v) else list(interp, v),
                else => return toObj(interp, v.*),
            },
            .many, .c => {
                if (p.child != u8 or p.sentinel() != 0) @compileError("zig_tk: unsupported pointer type " ++ @typeName(T));
                return string(std.mem.span(v));
            },
        },
        .@"struct" => |s| {
            if (s.is_tuple) return list(interp, v);
            @compileError("zig_tk: struct " ++ @typeName(T) ++ " cannot be converted to a Tcl value (add a toTclObj method)");
        },
        else => @compileError("zig_tk: unsupported type " ++ @typeName(T)),
    }
}

/// Tcl_Objの文字列表現をgpaで複製する(freeStringsで解放)。
pub fn dupeStrings(gpa: std.mem.Allocator, objs: []const *tcl.Obj) Error![][]u8 {
    const out = try gpa.alloc([]u8, objs.len);
    var filled: usize = 0;
    errdefer {
        for (out[0..filled]) |s| gpa.free(s);
        gpa.free(out);
    }
    for (objs, out) |obj, *s| {
        s.* = try gpa.dupe(u8, tcl.getString(obj));
        filled += 1;
    }
    return out;
}

pub fn freeStrings(gpa: std.mem.Allocator, strings: [][]u8) void {
    for (strings) |s| gpa.free(s);
    gpa.free(strings);
}

pub fn string(s: []const u8) *tcl.Obj {
    return tcl.Tcl_NewStringObj(s.ptr, @intCast(s.len));
}

/// タプル・配列・スライスをTclリストに変換する(要素はtoObjで再帰的に変換されるため入れ子も可)。
fn list(interp: *Interp, items: anytype) Error!*tcl.Obj {
    const obj = tcl.Tcl_NewListObj(0, null);
    // 参照カウント0のオブジェクトを途中失敗時に解放するためのincr/decr。
    errdefer {
        tcl.incrRefCount(obj);
        tcl.decrRefCount(obj);
    }
    const Items = @TypeOf(items);
    if (@typeInfo(Items) == .@"struct") {
        inline for (items) |item| _ = tcl.Tcl_ListObjAppendElement(null, obj, try toObj(interp, item));
    } else {
        for (items) |item| _ = tcl.Tcl_ListObjAppendElement(null, obj, try toObj(interp, item));
    }
    return obj;
}

/// optsの非nullフィールドを "-<フィールド名> <値>" としてcmdへ追加する。
/// Callback型のフィールドは "zt_cb<owner_path>-<フィールド名>" という名前のTclコマンドとして登録する
/// (同じWidget・同じオプションへ再設定すると同名コマンドが置き換わり、古いコールバックは解放される)。
pub fn appendOptions(cmd: *Cmd, owner_path: []const u8, opts: anytype) Error!void {
    const info = @typeInfo(@TypeOf(opts)).@"struct";
    inline for (info.field_names) |name| {
        const field = @field(opts, name);
        if (@typeInfo(@TypeOf(field)) == .optional) {
            if (field) |v| try appendOption(cmd, owner_path, name, v);
        } else {
            try appendOption(cmd, owner_path, name, field);
        }
    }
}

fn appendOption(cmd: *Cmd, owner_path: []const u8, comptime name: []const u8, v: anytype) Error!void {
    try cmd.add("-" ++ name);
    const V = @TypeOf(v);
    if (V == callback.Callback or V == callback.ValidateCallback) {
        var buf: [256]u8 = undefined;
        const cmd_name = std.fmt.bufPrintSentinel(&buf, "zt_cb{s}-" ++ name, .{owner_path}, 0) catch return error.OutOfMemory;
        try callback.register(cmd.interp, cmd_name, v);
        if (V == callback.ValidateCallback) {
            // validatecommandは%置換を含むスクリプトとして渡す
            try cmd.add(.{cmd_name} ++ callback.Validation.substitutions);
        } else {
            try cmd.add(cmd_name);
        }
    } else {
        try cmd.add(v);
    }
}
