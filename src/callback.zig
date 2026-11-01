//! Zigの関数をTclコマンドとして登録するためのコールバック型。
//! Zigにはクロージャが無いため「コンテキストポインタ + comptimeに確定した関数」の組を型消去して保持する。
const std = @import("std");
const tcl = @import("tcl.zig");
const interp_mod = @import("interp.zig");
const Interp = interp_mod.Interp;
const Error = interp_mod.Error;

/// 引数なしのコールバック(command=等)。
pub const Callback = struct {
    ctx: ?*anyopaque,
    func: *const fn (ctx: ?*anyopaque) anyerror!void,

    /// オプション以外の場所(Interp.callの引数等)で使われた場合は一意な名前で登録する。
    pub fn toTclObj(self: Callback, interp: *Interp) Error!*tcl.Obj {
        const name = try interp.uniqueName("zt_cb");
        try register(interp, name, self);
        return tcl.Tcl_NewStringObj(name.ptr, @intCast(name.len));
    }
};

/// イベント情報を受け取るコールバック(bind用)。
pub const EventCallback = struct {
    ctx: ?*anyopaque,
    func: *const fn (ctx: ?*anyopaque, event: Event) anyerror!void,
};

/// bindに渡されるイベント情報(Python tkinter.Event相当)。文字列はコールバック実行中のみ有効。
pub const Event = struct {
    x: i32,
    y: i32,
    x_root: i32,
    y_root: i32,
    /// イベントが発生したWidgetのパス名。
    widget: []const u8,
    /// 入力された文字(キーイベント以外では空)。
    char: []const u8,
    keysym: []const u8,
    keycode: i32,
    /// マウスホイールの回転量(MouseWheel以外では0)。
    delta: i32,

    /// bindスクリプトに渡すTkの%置換。並びはfromObjvと一致させる。
    pub const substitutions = .{ "%x", "%y", "%X", "%Y", "%W", "%A", "%K", "%k", "%D" };

    fn fromObjv(objv: []const *tcl.Obj) Event {
        return .{
            .x = int(objv[0]),
            .y = int(objv[1]),
            .x_root = int(objv[2]),
            .y_root = int(objv[3]),
            .widget = tcl.getString(objv[4]),
            .char = notApplicableToEmpty(tcl.getString(objv[5])),
            .keysym = notApplicableToEmpty(tcl.getString(objv[6])),
            .keycode = int(objv[7]),
            .delta = int(objv[8]),
        };
    }

    // 該当しない%置換はTkが"??"を返すため0にする。
    fn int(obj: *tcl.Obj) i32 {
        var v: tcl.WideInt = 0;
        if (tcl.Tcl_GetWideIntFromObj(null, obj, &v) != tcl.OK) return 0;
        return std.math.cast(i32, v) orelse 0;
    }

    fn notApplicableToEmpty(s: []const u8) []const u8 {
        return if (std.mem.eql(u8, s, "??")) "" else s;
    }
};

/// 入力検証(validatecommand)のコールバックに渡される情報。文字列はコールバック実行中のみ有効。
pub const Validation = struct {
    action: Action,
    /// 挿入・削除される位置(該当しない場合は-1)。
    index: i32,
    /// 変更を許可した場合の新しい文字列(%P)。
    new_text: []const u8,
    /// 変更前の文字列(%s)。
    old_text: []const u8,
    /// 挿入・削除される部分(%S)。
    change: []const u8,
    reason: Reason,

    pub const Action = enum { insert, delete, other };
    pub const Reason = enum { key, focusin, focusout, forced };

    /// validatecommandに渡すTkの%置換。並びはfromObjvと一致させる。
    pub const substitutions = .{ "%d", "%i", "%P", "%s", "%S", "%V" };

    fn fromObjv(objv: []const *tcl.Obj) Validation {
        return .{
            .action = switch (Event.int(objv[0])) {
                1 => .insert,
                0 => .delete,
                else => .other,
            },
            .index = Event.int(objv[1]),
            .new_text = tcl.getString(objv[2]),
            .old_text = tcl.getString(objv[3]),
            .change = tcl.getString(objv[4]),
            .reason = std.meta.stringToEnum(Reason, tcl.getString(objv[5])) orelse .forced,
        };
    }
};

/// 入力検証のコールバック。trueを返すと変更を許可し、falseなら拒否する(invalidcommandが呼ばれる)。
pub const ValidateCallback = struct {
    ctx: ?*anyopaque,
    func: *const fn (ctx: ?*anyopaque, v: Validation) anyerror!bool,
};

/// ctx(ポインタ)とfuncからコールバックを作る。
/// - func(ctx) / func(ctx) !void          → Callback
/// - func(ctx, Event) / func(ctx, Event) !void → EventCallback
/// - func(ctx, Validation) bool / !bool        → ValidateCallback(validatecommand用)
/// funcの第1引数がポインタでなく値(例: Tk.quit(self: Tk))の場合は、呼び出し時に*ctxを渡す。
/// 例: tk.callback(&app, App.onClick)
pub fn callback(ctx: anytype, comptime func: anytype) CallbackType(@TypeOf(func)) {
    const P = @TypeOf(ctx);
    if (@typeInfo(P) != .pointer) @compileError("callback: ctx must be a pointer, got " ++ @typeName(P));
    const by_value = @typeInfo(@TypeOf(func)).@"fn".param_types[0] == @typeInfo(P).pointer.child;
    const Wrap = struct {
        fn arg(p: ?*anyopaque) if (by_value) @typeInfo(P).pointer.child else P {
            const ptr: P = @ptrCast(@alignCast(p.?));
            return if (by_value) ptr.* else ptr;
        }
        fn call(p: ?*anyopaque) anyerror!void {
            return func(arg(p));
        }
        fn callEvent(p: ?*anyopaque, event: Event) anyerror!void {
            return func(arg(p), event);
        }
        fn callValidate(p: ?*anyopaque, v: Validation) anyerror!bool {
            return func(arg(p), v);
        }
    };
    const erased: ?*anyopaque = @ptrCast(@constCast(ctx));
    return switch (CallbackType(@TypeOf(func))) {
        Callback => .{ .ctx = erased, .func = Wrap.call },
        EventCallback => .{ .ctx = erased, .func = Wrap.callEvent },
        ValidateCallback => .{ .ctx = erased, .func = Wrap.callValidate },
        else => unreachable,
    };
}

/// コンテキストを持たない関数からコールバックを作る。例: tk.callbackFn(onQuit)
pub fn callbackFn(comptime func: anytype) CallbackType(@TypeOf(func)) {
    const Wrap = struct {
        fn call(_: ?*anyopaque) anyerror!void {
            return func();
        }
        fn callEvent(_: ?*anyopaque, event: Event) anyerror!void {
            return func(event);
        }
        fn callValidate(_: ?*anyopaque, v: Validation) anyerror!bool {
            return func(v);
        }
    };
    return switch (CallbackType(@TypeOf(func))) {
        Callback => .{ .ctx = null, .func = Wrap.call },
        EventCallback => .{ .ctx = null, .func = Wrap.callEvent },
        ValidateCallback => .{ .ctx = null, .func = Wrap.callValidate },
        else => unreachable,
    };
}

fn CallbackType(comptime F: type) type {
    const params = @typeInfo(F).@"fn".param_types;
    if (params.len > 0 and params[params.len - 1] == Event) return EventCallback;
    if (params.len > 0 and params[params.len - 1] == Validation) return ValidateCallback;
    return Callback;
}

/// cbをTclコマンドnameとして登録する。同名コマンドがあれば置き換えられ、古い側の確保領域は解放される。
pub fn register(interp: *Interp, name: [:0]const u8, cb: anytype) Error!void {
    const Cb = @TypeOf(cb);
    const Box = struct {
        gpa: std.mem.Allocator,
        cb: Cb,

        fn proc(client_data: tcl.ClientData, raw: *tcl.Interp, objc: c_int, objv: [*]const *tcl.Obj) callconv(.c) c_int {
            const box: *@This() = @ptrCast(@alignCast(client_data.?));
            const args = objv[1..@intCast(objc)];
            switch (Cb) {
                Callback => box.cb.func(box.cb.ctx) catch |err| return fail(raw, err),
                EventCallback => {
                    if (args.len != Event.substitutions.len) return setError(raw, "zig_tk: unexpected event argument count");
                    box.cb.func(box.cb.ctx, Event.fromObjv(args)) catch |err| return fail(raw, err);
                },
                ValidateCallback => {
                    if (args.len != Validation.substitutions.len) return setError(raw, "zig_tk: unexpected validation argument count");
                    const ok = box.cb.func(box.cb.ctx, Validation.fromObjv(args)) catch |err| return fail(raw, err);
                    // Tkはvalidatecommandの結果をブール値として解釈する
                    tcl.Tcl_SetObjResult(raw, tcl.Tcl_NewWideIntObj(@intFromBool(ok)));
                },
                else => unreachable,
            }
            return tcl.OK;
        }

        // Tcl_ERRORを返すとTk側のbgerror(Python report_callback_exception相当)で報告される。
        fn fail(raw: *tcl.Interp, err: anyerror) c_int {
            var buf: [128]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "zig_tk: callback failed: error.{s}", .{@errorName(err)}) catch "zig_tk: callback failed";
            return setError(raw, msg);
        }

        fn delete(client_data: tcl.ClientData) callconv(.c) void {
            const box: *@This() = @ptrCast(@alignCast(client_data.?));
            box.gpa.destroy(box);
        }
    };

    const box = try interp.gpa.create(Box);
    box.* = .{ .gpa = interp.gpa, .cb = cb };
    interp.createCommand(name, Box.proc, box, Box.delete) catch |err| {
        interp.gpa.destroy(box);
        return err;
    };
}

fn setError(raw: *tcl.Interp, msg: []const u8) c_int {
    tcl.Tcl_SetObjResult(raw, tcl.Tcl_NewStringObj(msg.ptr, @intCast(msg.len)));
    return tcl.ERROR;
}
