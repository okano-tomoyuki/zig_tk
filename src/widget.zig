//! 全Widget共通のハンドルと共通メソッド。
//! Widgetは「インタプリタ + パス名」だけを持つ値型で、自由にコピーできる
//! (cpp_tkのhandle()/as_parent()に相当する仕組みは不要)。
const std = @import("std");
const tcl = @import("tcl.zig");
const value = @import("value.zig");
const types = @import("types.zig");
const callback = @import("callback.zig");
const interp_mod = @import("interp.zig");
const Interp = interp_mod.Interp;
const Cmd = interp_mod.Cmd;
const Error = interp_mod.Error;

pub const PackOptions = struct {
    side: ?types.Side = null,
    fill: ?types.Fill = null,
    expand: ?bool = null,
    anchor: ?types.Anchor = null,
    padx: ?types.Pad = null,
    pady: ?types.Pad = null,
    ipadx: ?i32 = null,
    ipady: ?i32 = null,
    before: ?Widget = null,
    after: ?Widget = null,
};

pub const GridOptions = struct {
    row: ?i32 = null,
    column: ?i32 = null,
    rowspan: ?i32 = null,
    columnspan: ?i32 = null,
    sticky: ?types.Sticky = null,
    padx: ?types.Pad = null,
    pady: ?types.Pad = null,
    ipadx: ?i32 = null,
    ipady: ?i32 = null,
};

pub const PlaceOptions = struct {
    x: ?i32 = null,
    y: ?i32 = null,
    relx: ?f64 = null,
    rely: ?f64 = null,
    width: ?i32 = null,
    height: ?i32 = null,
    relwidth: ?f64 = null,
    relheight: ?f64 = null,
    anchor: ?types.Anchor = null,
};

/// gridRowconfigure/gridColumnconfigureで設定する行・列の性質。
pub const GridConfigOptions = struct {
    /// 余った空間をこの比率で配分する(0なら伸縮しない。既定 0)。
    weight: ?i32 = null,
    /// 最小の大きさ(ピクセル)。
    minsize: ?i32 = null,
    /// 行・列の前後に足す余白(ピクセル)。
    pad: ?i32 = null,
    /// 同じグループ名の行・列は同じ大きさに揃えられる。
    uniform: ?[]const u8 = null,
};

/// winfoで問い合わせる整数値。
pub const Winfo = enum {
    /// 実際の幅・高さ(ピクセル、マップ前は1)。
    width,
    height,
    /// ジオメトリマネージャに要求している幅・高さ。
    reqwidth,
    reqheight,
    /// 親ウィンドウ内での位置。
    x,
    y,
    /// 画面上での位置。
    rootx,
    rooty,
    screenwidth,
    screenheight,
    /// マウスポインタの画面上での位置。
    pointerx,
    pointery,
};

pub const EventGenerateOptions = struct {
    x: ?i32 = null,
    y: ?i32 = null,
    rootx: ?i32 = null,
    rooty: ?i32 = null,
    /// 発生させるタイミング(省略時はただちに処理する)。
    when: ?When = null,
    /// 仮想イベントに添えるデータ。
    data: ?[]const u8 = null,
    keysym: ?[]const u8 = null,
    button: ?i32 = null,
    delta: ?i32 = null,

    pub const When = enum { now, tail, head, mark };
};

pub const Widget = struct {
    interp: *Interp,
    /// Tkのウィンドウパス名(例: ".w1.w3")。インタプリタ破棄まで有効。
    path: [:0]const u8,

    /// parentの子として "<tk_command> <新しいパス> -opt val ..." を実行し、そのハンドルを返す。
    pub fn create(parent: Widget, tk_command: []const u8, opts: anytype) Error!Widget {
        const interp = parent.interp;
        interp.next_id += 1;
        const prefix: []const u8 = if (std.mem.eql(u8, parent.path, ".")) "" else parent.path;
        const path = try std.fmt.allocPrintSentinel(interp.arena.allocator(), "{s}.w{d}", .{ prefix, interp.next_id }, 0);

        var cmd: Cmd = .init(interp);
        defer cmd.deinit();
        try cmd.add(tk_command);
        try cmd.add(path);
        // 生成に失敗した場合、オプション経由で先に登録されたコールバックを解放する
        errdefer _ = interp.call(.{ "::zt_cleanup", path }) catch {};
        try cmd.addOptions(path, opts);
        _ = try cmd.eval();
        try interp.trackWidget(path);
        return .{ .interp = interp, .path = path };
    }

    pub fn toTclObj(self: Widget, _: *Interp) Error!*tcl.Obj {
        return value.string(self.path);
    }

    /// "<path> configure -opt val ..."
    pub fn configure(self: Widget, opts: anytype) Error!void {
        var cmd: Cmd = .init(self.interp);
        defer cmd.deinit();
        try cmd.add(self.path);
        try cmd.add("configure");
        try cmd.addOptions(self.path, opts);
        _ = try cmd.eval();
    }

    /// "<path> cget -<option>"。戻り値は次のTcl呼び出しまで有効。
    pub fn cget(self: Widget, option: []const u8) Error![]const u8 {
        var buf: [64]u8 = undefined;
        const name = std.fmt.bufPrint(&buf, "-{s}", .{option}) catch return error.OutOfMemory;
        return self.interp.call(.{ self.path, "cget", name });
    }

    /// 任意のジオメトリマネージャ/Tclコマンドを "<manager> <path> -opt val ..." の形で呼ぶ。
    fn manage(self: Widget, manager: []const u8, opts: anytype) Error!void {
        var cmd: Cmd = .init(self.interp);
        defer cmd.deinit();
        try cmd.add(manager);
        try cmd.add(self.path);
        try cmd.addOptions(self.path, opts);
        _ = try cmd.eval();
    }

    pub fn pack(self: Widget, opts: PackOptions) Error!void {
        return self.manage("pack", opts);
    }

    pub fn grid(self: Widget, opts: GridOptions) Error!void {
        return self.manage("grid", opts);
    }

    pub fn place(self: Widget, opts: PlaceOptions) Error!void {
        return self.manage("place", opts);
    }

    pub fn packForget(self: Widget) Error!void {
        _ = try self.interp.call(.{ "pack", "forget", self.path });
    }

    pub fn gridForget(self: Widget) Error!void {
        _ = try self.interp.call(.{ "grid", "forget", self.path });
    }

    pub fn placeForget(self: Widget) Error!void {
        _ = try self.interp.call(.{ "place", "forget", self.path });
    }

    /// sequence(例: "<Button-1>")にcbを結び付ける。同じsequenceへの再bindは置き換えになる。
    pub fn bind(self: Widget, sequence: []const u8, cb: callback.EventCallback) Error!void {
        var buf: [256]u8 = undefined;
        const name = try bindCommandName(&buf, self.path, sequence);
        try callback.register(self.interp, name, cb);
        _ = try self.interp.call(.{ "bind", self.path, sequence, .{name} ++ callback.Event.substitutions });
    }

    /// sequenceのbindを解除し、そのコールバックを解放する。
    pub fn unbind(self: Widget, sequence: []const u8) Error!void {
        _ = try self.interp.call(.{ "bind", self.path, sequence, "" });
        var buf: [256]u8 = undefined;
        _ = tcl.Tcl_DeleteCommand(self.interp.raw, (try bindCommandName(&buf, self.path, sequence)).ptr);
    }

    /// "|" はパスに現れないため、破棄時に "zt_bind<path>|*" でこのWidgetの分だけを選べる。
    fn bindCommandName(buf: []u8, path: []const u8, sequence: []const u8) Error![:0]const u8 {
        return std.fmt.bufPrintSentinel(buf, "zt_bind{s}|{s}", .{ path, sequence }, 0) catch error.OutOfMemory;
    }

    pub fn focusSet(self: Widget) Error!void {
        _ = try self.interp.call(.{ "focus", self.path });
    }

    /// 他のアプリケーションがフォーカスを持っていても奪う。
    pub fn focusForce(self: Widget) Error!void {
        _ = try self.interp.call(.{ "focus", "-force", self.path });
    }

    /// このWidgetを親とするgrid配置で、row行目の伸縮等を設定する(Python grid_rowconfigure相当)。
    pub fn gridRowconfigure(self: Widget, row: i32, opts: GridConfigOptions) Error!void {
        return self.gridConfigure("rowconfigure", row, opts);
    }

    /// このWidgetを親とするgrid配置で、column列目の伸縮等を設定する(Python grid_columnconfigure相当)。
    pub fn gridColumnconfigure(self: Widget, column: i32, opts: GridConfigOptions) Error!void {
        return self.gridConfigure("columnconfigure", column, opts);
    }

    fn gridConfigure(self: Widget, sub: []const u8, i: i32, opts: GridConfigOptions) Error!void {
        var cmd: Cmd = .init(self.interp);
        defer cmd.deinit();
        try cmd.add("grid");
        try cmd.add(sub);
        try cmd.add(self.path);
        try cmd.add(i);
        try cmd.addOptions(self.path, opts);
        _ = try cmd.eval();
    }

    /// falseにすると、grid配置した子の大きさに合わせてこのWidgetが伸縮しなくなる。
    pub fn gridPropagate(self: Widget, propagate: bool) Error!void {
        _ = try self.interp.call(.{ "grid", "propagate", self.path, propagate });
    }

    /// falseにすると、pack配置した子の大きさに合わせてこのWidgetが伸縮しなくなる。
    pub fn packPropagate(self: Widget, propagate: bool) Error!void {
        _ = try self.interp.call(.{ "pack", "propagate", self.path, propagate });
    }

    pub fn winfo(self: Widget, query: Winfo) Error!i32 {
        const result = try self.interp.call(.{ "winfo", query, self.path });
        return std.fmt.parseInt(i32, result, 10) catch self.interp.failWith("unexpected winfo result");
    }

    pub fn winfoExists(self: Widget) Error!bool {
        return std.mem.eql(u8, try self.interp.call(.{ "winfo", "exists", self.path }), "1");
    }

    /// 画面に表示されている(マップされている)か。
    pub fn winfoIsmapped(self: Widget) Error!bool {
        return std.mem.eql(u8, try self.interp.call(.{ "winfo", "ismapped", self.path }), "1");
    }

    /// クラス名(例: "Button" "TButton")。次のTcl呼び出しまで有効。
    pub fn winfoClass(self: Widget) Error![]const u8 {
        return self.interp.call(.{ "winfo", "class", self.path });
    }

    /// イベントを発生させる(例: "<<MyEvent>>" "<Button-1>")。
    /// 注意: Tkはマップされていないウィンドウへのイベントを配送しない。
    pub fn eventGenerate(self: Widget, sequence: []const u8, opts: EventGenerateOptions) Error!void {
        var cmd: Cmd = .init(self.interp);
        defer cmd.deinit();
        try cmd.add("event");
        try cmd.add("generate");
        try cmd.add(self.path);
        try cmd.add(sequence);
        try cmd.addOptions(self.path, opts);
        _ = try cmd.eval();
    }

    /// このWidgetが破棄されるまでイベントを処理しながら待つ(モーダルダイアログ等)。
    pub fn waitWindow(self: Widget) Error!void {
        _ = try self.interp.call(.{ "tkwait", "window", self.path });
    }

    pub fn destroy(self: Widget) Error!void {
        _ = try self.interp.call(.{ "destroy", self.path });
    }
};

/// Widget、またはフィールドw: Widgetを持つ型(Button等)とそのポインタからWidgetを取り出す。
pub fn asWidget(x: anytype) Widget {
    const T = @TypeOf(x);
    if (T == Widget) return x;
    switch (@typeInfo(T)) {
        .pointer => |p| if (p.size == .one) return asWidget(x.*),
        .@"struct" => if (@hasField(T, "w") and @FieldType(T, "w") == Widget) return x.w,
        else => {},
    }
    @compileError("zig_tk: expected a widget, got " ++ @typeName(T));
}

/// 具象Widget型(Self、フィールドw: Widgetを持つ)向けの共通メソッド群。
/// Zigには継承もusingnamespaceも無いため、各Widget型で `pub const pack = M.pack;` のように公開する。
/// Optionsはconfig/cgetが受け付けるオプション集合で、cgetの引数もそのフィールド名のenumに限定される。
pub fn Methods(comptime Self: type, comptime Options: type) type {
    return MethodsCreate(Self, Options, Options);
}

/// 生成時にしか指定できないオプション(frameの-class、ttk::panedwindowの-orient等)を持つWidget向けの
/// Methods。CreateOptionsはinitが受け取る全オプション、Optionsは生成後にconfigで変更できるもの。
/// cgetは生成時のみのオプションも読み出せるようCreateOptionsのフィールド名を受け付ける。
/// 両者は手書きで定義するため、CreateOptionsがOptionsの全フィールドを同じ型で含むことをここで検査する。
pub fn MethodsCreate(comptime Self: type, comptime CreateOptions: type, comptime Options: type) type {
    comptime {
        const info = @typeInfo(Options).@"struct";
        for (info.field_names, info.field_types) |name, T| {
            if (!@hasField(CreateOptions, name))
                @compileError(@typeName(CreateOptions) ++ " lacks option '" ++ name ++ "' of " ++ @typeName(Options));
            if (@FieldType(CreateOptions, name) != T)
                @compileError(@typeName(CreateOptions) ++ "." ++ name ++ " must have the same type as in " ++ @typeName(Options));
        }
    }
    return struct {
        pub fn toTclObj(self: Self, interp: *Interp) Error!*tcl.Obj {
            return self.w.toTclObj(interp);
        }
        pub fn config(self: Self, opts: Options) Error!void {
            return self.w.configure(opts);
        }
        pub fn cget(self: Self, comptime option: std.meta.FieldEnum(CreateOptions)) Error![]const u8 {
            return self.w.cget(@tagName(option));
        }
        pub fn pack(self: Self, opts: PackOptions) Error!void {
            return self.w.pack(opts);
        }
        pub fn grid(self: Self, opts: GridOptions) Error!void {
            return self.w.grid(opts);
        }
        pub fn place(self: Self, opts: PlaceOptions) Error!void {
            return self.w.place(opts);
        }
        pub fn bind(self: Self, sequence: []const u8, cb: callback.EventCallback) Error!void {
            return self.w.bind(sequence, cb);
        }
        pub fn unbind(self: Self, sequence: []const u8) Error!void {
            return self.w.unbind(sequence);
        }
        pub fn destroy(self: Self) Error!void {
            return self.w.destroy();
        }
        pub fn packForget(self: Self) Error!void {
            return self.w.packForget();
        }
        pub fn gridForget(self: Self) Error!void {
            return self.w.gridForget();
        }
        pub fn placeForget(self: Self) Error!void {
            return self.w.placeForget();
        }
        pub fn gridRowconfigure(self: Self, row: i32, opts: GridConfigOptions) Error!void {
            return self.w.gridRowconfigure(row, opts);
        }
        pub fn gridColumnconfigure(self: Self, column: i32, opts: GridConfigOptions) Error!void {
            return self.w.gridColumnconfigure(column, opts);
        }
        pub fn gridPropagate(self: Self, propagate: bool) Error!void {
            return self.w.gridPropagate(propagate);
        }
        pub fn packPropagate(self: Self, propagate: bool) Error!void {
            return self.w.packPropagate(propagate);
        }
        pub fn focusSet(self: Self) Error!void {
            return self.w.focusSet();
        }
        pub fn focusForce(self: Self) Error!void {
            return self.w.focusForce();
        }
        pub fn winfo(self: Self, query: Winfo) Error!i32 {
            return self.w.winfo(query);
        }
        pub fn winfoExists(self: Self) Error!bool {
            return self.w.winfoExists();
        }
        pub fn winfoIsmapped(self: Self) Error!bool {
            return self.w.winfoIsmapped();
        }
        pub fn winfoClass(self: Self) Error![]const u8 {
            return self.w.winfoClass();
        }
        pub fn eventGenerate(self: Self, sequence: []const u8, opts: EventGenerateOptions) Error!void {
            return self.w.eventGenerate(sequence, opts);
        }
        pub fn waitWindow(self: Self) Error!void {
            return self.w.waitWindow();
        }
    };
}

/// Methodsで公開するWidget共通のメソッド名(各Widget型の宣言の一覧と揃える)。
pub const common_method_names = [_][]const u8{
    "toTclObj",     "config",              "cget",          "pack",          "grid",
    "place",        "bind",                "unbind",        "destroy",       "packForget",
    "gridForget",   "placeForget",         "gridRowconfigure", "gridColumnconfigure", "gridPropagate",
    "packPropagate", "focusSet",           "focusForce",    "winfo",         "winfoExists",
    "winfoIsmapped", "winfoClass",         "eventGenerate", "waitWindow",
};
