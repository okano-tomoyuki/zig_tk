//! Tclインタプリタの所有者。Tcl呼び出し・エラーメッセージの保持・Zigコールバックの登録を担う。
const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const tcl = @import("tcl.zig");
const value = @import("value.zig");
const callback = @import("callback.zig");

pub const Error = error{ TclError, OutOfMemory };

/// after/afterIdleが返す予約ID(afterCancelに渡す)。確保領域を持たない値型。
pub const TimerId = struct {
    seq: u32,
    tcl_id: [24]u8 = undefined,
    tcl_id_len: u8 = 0,

    /// Tcl側のafter ID(例: "after#3")。
    pub fn tclId(self: *const TimerId) []const u8 {
        return self.tcl_id[0..self.tcl_id_len];
    }

    fn commandName(buf: []u8, seq: u32) Error![:0]const u8 {
        return std.fmt.bufPrintSentinel(buf, "zt_after{d}", .{seq}, 0) catch error.OutOfMemory;
    }
};

pub const Interp = struct {
    raw: *tcl.Interp,
    gpa: Allocator,
    /// Widgetのパス名など、インタプリタと寿命を共にする小さな文字列の置き場。
    arena: std.heap.ArenaAllocator,
    next_id: u32 = 0,
    /// 直近のTclError発生時のメッセージ(Tclの結果は次の呼び出しで上書きされるため複製して保持する)。
    last_error: std.ArrayList(u8) = .empty,

    var find_executable_done = false;

    /// Tcl_Init/Tk_Initまで済ませたインタプリタを生成する。
    pub fn create(gpa: Allocator) Error!*Interp {
        if (!find_executable_done) {
            findExecutable();
            find_executable_done = true;
        }
        const raw = tcl.Tcl_CreateInterp() orelse return error.TclError;
        errdefer tcl.Tcl_DeleteInterp(raw);

        const self = try gpa.create(Interp);
        errdefer gpa.destroy(self);
        self.* = .{ .raw = raw, .gpa = gpa, .arena = .init(gpa) };
        errdefer self.last_error.deinit(gpa);

        if (tcl.Tcl_Init(raw) != tcl.OK) return self.fail();
        if (tcl.Tk_Init(raw) != tcl.OK) return self.fail();
        if (tcl.Tcl_EvalEx(raw, support_script, support_script.len, tcl.EVAL_GLOBAL) != tcl.OK) return self.fail();
        try self.trackWidget(".");
        return self;
    }

    /// msミリ秒後にcbを1回だけ呼ぶ(Python Misc.after相当)。
    pub fn after(self: *Interp, ms: u32, cb: callback.Callback) Error!TimerId {
        return self.schedule(ms, cb);
    }

    /// イベントループが暇になった時にcbを1回だけ呼ぶ(Python Misc.after_idle相当)。
    pub fn afterIdle(self: *Interp, cb: callback.Callback) Error!TimerId {
        return self.schedule(null, cb);
    }

    /// after/afterIdleで予約したコールバックを取り消して解放する。発火済みなら何もしない。
    pub fn afterCancel(self: *Interp, id: TimerId) void {
        _ = self.call(.{ "after", "cancel", id.tclId() }) catch {};
        var buf: [32]u8 = undefined;
        _ = tcl.Tcl_DeleteCommand(self.raw, (TimerId.commandName(&buf, id.seq) catch return).ptr);
    }

    /// 1回きりのコールバックは "zt_after<seq>" として登録し、::zt_after_fire 経由で呼ぶ。
    /// zt_after_fireは呼び出し後に(例外時も)コマンドを削除するため、実行中に自分自身の確保領域を
    /// 解放してしまうことなく後始末できる。名前はスタック上で組み立てるため、繰り返し予約しても
    /// インタプリタ側のメモリは増えない。
    fn schedule(self: *Interp, ms: ?u32, cb: callback.Callback) Error!TimerId {
        self.next_id += 1;
        const seq = self.next_id;
        var buf: [32]u8 = undefined;
        const name = try TimerId.commandName(&buf, seq);
        try callback.register(self, name, cb);
        const script = .{ "::zt_after_fire", name };
        const result = (if (ms) |delay| self.call(.{ "after", delay, script }) else self.call(.{ "after", "idle", script })) catch |err| {
            _ = tcl.Tcl_DeleteCommand(self.raw, name.ptr);
            return err;
        };
        var id: TimerId = .{ .seq = seq };
        if (result.len > id.tcl_id.len) return error.TclError;
        @memcpy(id.tcl_id[0..result.len], result);
        id.tcl_id_len = @intCast(result.len);
        return id;
    }

    /// 保留中のイベント(再描画・タイマー等)を処理する(Python Misc.update相当)。
    pub fn update(self: *Interp) Error!void {
        _ = try self.call(.{"update"});
    }

    /// 保留中の再描画・ジオメトリ計算だけを処理する(Python Misc.update_idletasks相当)。
    pub fn updateIdletasks(self: *Interp) Error!void {
        _ = try self.call(.{ "update", "idletasks" });
    }

    /// zig_tkが登録するTclコマンドの後始末を行う補助スクリプト。
    ///
    /// Widgetに結び付くコールバックは "zt_cb<path>-<option>" / "zt_bind<path>|<sequence>" という
    /// 名前で登録される。各Widgetのbindtagsの末尾に zt_cleanup タグを足しておき、Widgetの破棄
    /// (親の破棄による連鎖を含む)時にそのWidget用のコマンドをrenameで削除する。削除時にZig側の
    /// delete procが呼ばれ、コールバックの確保領域が解放される。利用者自身の <Destroy> の bind
    /// とは別のタグなので干渉しない。
    const support_script =
        \\proc ::zt_track {w} {
        \\    bindtags $w [linsert [bindtags $w] end zt_cleanup]
        \\}
        \\proc ::zt_cleanup {w} {
        \\    foreach c [info commands ::zt_cb${w}-*] { rename $c {} }
        \\    foreach c [info commands ::zt_bind${w}|*] { rename $c {} }
        \\}
        \\bind zt_cleanup <Destroy> {::zt_cleanup %W}
        \\proc ::zt_after_fire {cmd} {
        \\    try { $cmd } finally { rename $cmd {} }
        \\}
        \\proc ::zt_var_free {name} {
        \\    foreach t [trace info variable ::$name] {
        \\        lassign $t ops cmd
        \\        trace remove variable ::$name $ops $cmd
        \\        if {[string match zt_trace* $cmd]} { rename $cmd {} }
        \\    }
        \\    unset -nocomplain ::$name
        \\}
    ;

    /// pathのWidgetを破棄時のコールバック解放の対象にする(Widget生成時に呼ばれる)。
    pub fn trackWidget(self: *Interp, path: []const u8) Error!void {
        _ = try self.call(.{ "::zt_track", path });
    }

    pub fn destroy(self: *Interp) void {
        // コマンド削除時のdelete procでコールバックの確保領域が解放される。
        tcl.Tcl_DeleteInterp(self.raw);
        self.last_error.deinit(self.gpa);
        self.arena.deinit();
        self.gpa.destroy(self);
    }

    /// 直近にerror.TclErrorを返した呼び出しのエラーメッセージ。
    pub fn lastError(self: *const Interp) []const u8 {
        return self.last_error.items;
    }

    /// 任意のTclコマンドを実行する(Python self.tk.call(...)相当のエスケープハッチ)。
    /// wordsはタプルで、各要素はvalue.toObjで変換できる値。例: call(.{ "wm", "title", root, "x" })
    /// 戻り値はTclの結果文字列で、次のTcl呼び出しまで有効。
    pub fn call(self: *Interp, words: anytype) Error![]const u8 {
        var cmd: Cmd = .init(self);
        defer cmd.deinit();
        inline for (words) |word| try cmd.add(word);
        return cmd.eval();
    }

    /// call と同じだが、結果をTclリストとして要素ごとに返す。
    /// 返すスライスと各要素は次のTcl呼び出しまで有効(保持する場合は複製すること)。
    pub fn callList(self: *Interp, words: anytype) Error![]const *tcl.Obj {
        _ = try self.call(words);
        return self.resultList();
    }

    /// 直前の呼び出しの結果をTclリストとして要素ごとに返す(callList参照)。
    pub fn resultList(self: *Interp) Error![]const *tcl.Obj {
        var objc: tcl.Size = 0;
        var objv: [*]*tcl.Obj = undefined;
        if (tcl.Tcl_ListObjGetElements(self.raw, tcl.Tcl_GetObjResult(self.raw), &objc, &objv) != tcl.OK)
            return self.fail();
        return objv[0..@intCast(objc)];
    }

    /// インタプリタ内で一意な名前を生成する(arenaに確保され、インタプリタ破棄まで有効)。
    pub fn uniqueName(self: *Interp, comptime prefix: []const u8) Error![:0]const u8 {
        self.next_id += 1;
        return std.fmt.allocPrintSentinel(self.arena.allocator(), prefix ++ "{d}", .{self.next_id}, 0);
    }

    /// procをTclコマンドnameとして登録する。同名のコマンドが既にあれば置き換える(古い側のdelete procが呼ばれる)。
    pub fn createCommand(
        self: *Interp,
        name: [:0]const u8,
        proc: tcl.ObjCmdProc,
        client_data: tcl.ClientData,
        delete_proc: ?tcl.CmdDeleteProc,
    ) Error!void {
        if (tcl.Tcl_CreateObjCommand(self.raw, name.ptr, proc, client_data, delete_proc) == null)
            return self.fail();
    }

    /// Tclに実行ファイルの場所を教える。zipfsが実行ファイル/共有ライブラリ末尾のスクリプトを
    /// マウントする際や、TkがDLL/.soを探す際の基準になる。
    /// Windowsでは引数に関わらずGetModuleFileNameWで取得されるが、Unixではargv0がNULLだと
    /// 何も設定されないため実パスを渡す。
    fn findExecutable() void {
        if (builtin.os.tag == .linux) {
            var buf: [4096:0]u8 = undefined;
            const n = std.c.readlink("/proc/self/exe", &buf, buf.len);
            if (n > 0) {
                buf[@intCast(n)] = 0;
                return tcl.Tcl_FindExecutable(&buf);
            }
        }
        tcl.Tcl_FindExecutable(null);
    }

    /// Zig側で検出したエラーをmessageとしてlast_errorへ記録し、error.TclErrorを返す。
    pub fn failWith(self: *Interp, message: []const u8) Error {
        self.last_error.clearRetainingCapacity();
        try self.last_error.appendSlice(self.gpa, message);
        return error.TclError;
    }

    /// Tclの結果をlast_errorへ複製してerror.TclErrorを返す。
    pub fn fail(self: *Interp) Error {
        self.last_error.clearRetainingCapacity();
        try self.last_error.appendSlice(self.gpa, tcl.getStringResult(self.raw));
        return error.TclError;
    }
};

/// Tclコマンドの引数列を組み立ててTcl_EvalObjvで実行するビルダ。
/// 追加したTcl_Objは参照カウントを保持し、deinitで解放する。
pub const Cmd = struct {
    interp: *Interp,
    objs: std.ArrayList(*tcl.Obj) = .empty,

    pub fn init(interp: *Interp) Cmd {
        return .{ .interp = interp };
    }

    pub fn deinit(self: *Cmd) void {
        for (self.objs.items) |obj| tcl.decrRefCount(obj);
        self.objs.deinit(self.interp.gpa);
    }

    pub fn addObj(self: *Cmd, obj: *tcl.Obj) Error!void {
        tcl.incrRefCount(obj);
        self.objs.append(self.interp.gpa, obj) catch |err| {
            tcl.decrRefCount(obj);
            return err;
        };
    }

    pub fn add(self: *Cmd, v: anytype) Error!void {
        try self.addObj(try value.toObj(self.interp, v));
    }

    /// optsの非nullフィールドを "-<フィールド名> <値>" として追加する。
    /// owner_pathはコールバック型のオプションを登録するTclコマンド名の生成に使う。
    pub fn addOptions(self: *Cmd, owner_path: []const u8, opts: anytype) Error!void {
        try value.appendOptions(self, owner_path, opts);
    }

    pub fn eval(self: *Cmd) Error![]const u8 {
        const code = tcl.Tcl_EvalObjv(self.interp.raw, @intCast(self.objs.items.len), self.objs.items.ptr, tcl.EVAL_GLOBAL);
        if (code != tcl.OK) return self.interp.fail();
        return tcl.getString(tcl.Tcl_GetObjResult(self.interp.raw));
    }
};
