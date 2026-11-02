//! Tcl/Tk C APIとの境界層。
//! 必要な関数だけを手書きのextern宣言で持つ(tcl.hのスタブマクロに依存しないため)。
//! Tcl 8.6と9.xのABI差(Tcl_Sizeの幅)はここで吸収する。使用している関数は両バージョンとも
//! 実関数としてエクスポートされている(9.xでマクロ化された関数は使わない)。
const build_options = @import("build_options");

pub const Interp = opaque {};
pub const Obj = opaque {};
pub const Command = opaque {};

pub const major_version = build_options.tcl_major;

/// Tcl 8.6 では int、Tcl 9.x では ptrdiff_t。
pub const Size = if (major_version >= 9) isize else c_int;
pub const WideInt = c_longlong;
pub const ClientData = ?*anyopaque;

pub const OK: c_int = 0;
pub const ERROR: c_int = 1;

pub const EVAL_GLOBAL: c_int = 0x020000;
pub const GLOBAL_ONLY: c_int = 1;
pub const LEAVE_ERR_MSG: c_int = 0x200;

pub const ObjCmdProc = *const fn (ClientData, *Interp, c_int, [*]const *Obj) callconv(.c) c_int;
pub const CmdDeleteProc = *const fn (ClientData) callconv(.c) void;

pub extern fn Tcl_FindExecutable(argv0: ?[*:0]const u8) void;
pub extern fn Tcl_CreateInterp() ?*Interp;
pub extern fn Tcl_DeleteInterp(interp: *Interp) void;
pub extern fn Tcl_Init(interp: *Interp) c_int;
pub extern fn Tcl_EvalEx(interp: *Interp, script: [*]const u8, num_bytes: Size, flags: c_int) c_int;
pub extern fn Tcl_EvalObjv(interp: *Interp, objc: Size, objv: [*]const *Obj, flags: c_int) c_int;
pub extern fn Tcl_GetObjResult(interp: *Interp) *Obj;
pub extern fn Tcl_SetObjResult(interp: *Interp, obj: *Obj) void;

pub extern fn Tcl_NewStringObj(bytes: [*]const u8, length: Size) *Obj;
pub extern fn Tcl_NewWideIntObj(value: WideInt) *Obj;
pub extern fn Tcl_NewDoubleObj(value: f64) *Obj;
pub extern fn Tcl_NewByteArrayObj(bytes: [*]const u8, length: Size) *Obj;
pub extern fn Tcl_NewListObj(objc: Size, objv: ?[*]const *Obj) *Obj;
pub extern fn Tcl_ListObjAppendElement(interp: ?*Interp, list: *Obj, elem: *Obj) c_int;
/// 9.xではマクロ経由で呼ぶ版もあるが、実関数はTcl_Size*を取る(8.6はint*でSizeと一致)。
pub extern fn Tcl_ListObjGetElements(interp: ?*Interp, list: *Obj, objc: *Size, objv: *[*]*Obj) c_int;
pub extern fn Tcl_GetStringFromObj(obj: *Obj, length: ?*Size) [*]const u8;
pub extern fn Tcl_GetWideIntFromObj(interp: ?*Interp, obj: *Obj, out: *WideInt) c_int;
pub extern fn Tcl_GetDoubleFromObj(interp: ?*Interp, obj: *Obj, out: *f64) c_int;
pub extern fn Tcl_GetBooleanFromObj(interp: ?*Interp, obj: *Obj, out: *c_int) c_int;

// Tcl_IncrRefCount/Tcl_DecrRefCountはtcl.h上のマクロ(Tcl_Objの内部レイアウトに依存)のため、
// 非デバッグビルドでも同じ処理をするエクスポート関数版を使う。
extern fn Tcl_DbIncrRefCount(obj: *Obj, file: [*:0]const u8, line: c_int) void;
extern fn Tcl_DbDecrRefCount(obj: *Obj, file: [*:0]const u8, line: c_int) void;

pub fn incrRefCount(obj: *Obj) void {
    Tcl_DbIncrRefCount(obj, "zig_tk", 0);
}

pub fn decrRefCount(obj: *Obj) void {
    Tcl_DbDecrRefCount(obj, "zig_tk", 0);
}

/// インタプリタの結果文字列(Tcl 9ではTcl_GetStringResultがマクロのため、Tcl_GetObjResult経由で取得する)。
pub fn getStringResult(interp: *Interp) []const u8 {
    return getString(Tcl_GetObjResult(interp));
}

pub fn getString(obj: *Obj) []const u8 {
    var len: Size = 0;
    const ptr = Tcl_GetStringFromObj(obj, &len);
    return ptr[0..@intCast(len)];
}

pub extern fn Tcl_GetVar2Ex(interp: *Interp, name1: [*:0]const u8, name2: ?[*:0]const u8, flags: c_int) ?*Obj;
pub extern fn Tcl_SetVar2Ex(interp: *Interp, name1: [*:0]const u8, name2: ?[*:0]const u8, value: *Obj, flags: c_int) ?*Obj;
pub extern fn Tcl_UnsetVar2(interp: *Interp, name1: [*:0]const u8, name2: ?[*:0]const u8, flags: c_int) c_int;

pub extern fn Tcl_CreateObjCommand(
    interp: *Interp,
    name: [*:0]const u8,
    proc: ObjCmdProc,
    client_data: ClientData,
    delete_proc: ?CmdDeleteProc,
) ?*Command;
pub extern fn Tcl_DeleteCommand(interp: *Interp, name: [*:0]const u8) c_int;

// スレッド間でのイベントの受け渡し。Tcl_ThreadQueueEvent/Tcl_ThreadAlertはどのスレッドから呼んでもよい。
pub const ThreadId = ?*opaque {};
pub const EventProc = *const fn (ev: *Event, flags: c_int) callconv(.c) c_int;
pub const EventDeleteProc = *const fn (ev: *Event, client_data: ClientData) callconv(.c) c_int;
/// Tcl_Event。キューに入れる側はこれを先頭に置いた領域をTcl_Allocで確保する(処理後にTclが解放する)。
pub const Event = extern struct {
    proc: EventProc,
    next: ?*Event,
};
pub const QUEUE_TAIL: c_int = 0;
/// Tcl 8.6 では unsigned int、Tcl 9.x では size_t。
pub const AllocSize = if (major_version >= 9) usize else c_uint;

pub extern fn Tcl_GetCurrentThread() ThreadId;
pub extern fn Tcl_ThreadQueueEvent(thread: ThreadId, ev: *Event, position: c_int) void;
pub extern fn Tcl_ThreadAlert(thread: ThreadId) void;
pub extern fn Tcl_DeleteEvents(proc: EventDeleteProc, client_data: ClientData) void;
pub extern fn Tcl_AttemptAlloc(size: AllocSize) ?*anyopaque;
pub extern fn Tcl_BackgroundException(interp: *Interp, code: c_int) void;

pub extern fn Tk_Init(interp: *Interp) c_int;
pub extern fn Tk_MainLoop() void;
