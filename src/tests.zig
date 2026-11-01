const std = @import("std");
const testing = std.testing;
const tk = @import("root.zig");

fn initRoot() !tk.Tk {
    const root = try tk.Tk.init(testing.allocator);
    _ = try root.call(.{ "wm", "withdraw", "." });
    return root;
}

test "call converts Zig values to Tcl words" {
    const root = try initRoot();
    defer root.deinit();

    try testing.expectEqualStrings("42", try root.call(.{ "expr", "6 * 7" }));
    try testing.expectEqualStrings("3", try root.call(.{ "llength", .{ 1, "two words", .{ 2.5, true } } }));
    try testing.expectEqualStrings("raised", try root.call(.{ "set", "x", tk.Relief.raised }));
    try testing.expectEqualStrings("nsew", try root.call(.{ "set", "x", tk.Sticky.nsew }));
}

test "options are applied at creation and readable through typed cget" {
    const root = try initRoot();
    defer root.deinit();

    const label = try tk.Label.init(root, .{ .text = "hello", .relief = .sunken, .padx = 7 });
    try testing.expectEqualStrings("hello", try label.cget(.text));
    try testing.expectEqualStrings("sunken", try label.cget(.relief));
    try testing.expectEqualStrings("7", try label.cget(.padx));

    try label.config(.{ .text = "changed" });
    try testing.expectEqualStrings("changed", try label.cget(.text));
    // configに渡さなかったオプションは変更されない
    try testing.expectEqualStrings("sunken", try label.cget(.relief));
}

test "widget paths nest under their parent" {
    const root = try initRoot();
    defer root.deinit();

    const frame = try tk.Frame.init(root, .{});
    const button = try tk.Button.init(frame, .{ .text = "x" });
    try testing.expect(std.mem.startsWith(u8, button.w.path, frame.w.path));
    try testing.expectEqualStrings("Button", try root.call(.{ "winfo", "class", button }));
    try button.pack(.{ .side = .left, .fill = .both, .expand = true });
    try testing.expectEqualStrings(frame.w.path, try root.call(.{ "winfo", "parent", button }));
}

test "command callback runs with its context and can be replaced" {
    const root = try initRoot();
    defer root.deinit();

    const Counter = struct {
        n: u32 = 0,
        fn inc(self: *@This()) void {
            self.n += 1;
        }
        fn add10(self: *@This()) void {
            self.n += 10;
        }
    };
    var counter: Counter = .{};
    const button = try tk.Button.init(root, .{ .command = tk.callback(&counter, Counter.inc) });
    _ = try button.invoke();
    _ = try button.invoke();
    try testing.expectEqual(2, counter.n);

    // 再設定すると古いコールバックは置き換えられ(解放され)る
    try button.config(.{ .command = tk.callback(&counter, Counter.add10) });
    _ = try button.invoke();
    try testing.expectEqual(12, counter.n);
}

test "callback errors become Tcl errors" {
    const root = try initRoot();
    defer root.deinit();

    const S = struct {
        fn fail() !void {
            return error.Boom;
        }
    };
    const button = try tk.Button.init(root, .{ .command = tk.callbackFn(S.fail) });
    try testing.expectError(error.TclError, button.invoke());
    try testing.expect(std.mem.indexOf(u8, root.lastError(), "error.Boom") != null);
}

test "bind delivers event fields" {
    const root = try initRoot();
    defer root.deinit();

    const Recorder = struct {
        x: i32 = -1,
        y: i32 = -1,
        fn onEvent(self: *@This(), event: tk.Event) void {
            self.x = event.x;
            self.y = event.y;
        }
    };
    var rec: Recorder = .{};
    const frame = try tk.Frame.init(root, .{ .width = 50, .height = 50 });
    try frame.pack(.{});
    try frame.bind("<<Ping>>", tk.callback(&rec, Recorder.onEvent));
    // Tkはマップされていないウィンドウへの生成イベントを配送しないため、画面外に表示する
    _ = try root.call(.{ "wm", "geometry", ".", "+-3000+-3000" });
    _ = try root.call(.{ "wm", "deiconify", "." });
    _ = try root.call(.{"update"});
    _ = try root.call(.{ "event", "generate", frame, "<<Ping>>", "-x", 3, "-y", 4, "-when", "now" });
    try testing.expectEqual(3, rec.x);
    try testing.expectEqual(4, rec.y);
}

test "variables round-trip typed values" {
    const root = try initRoot();
    defer root.deinit();

    const s = try tk.StringVar.init(root, .{ .value = "hi" });
    try testing.expectEqualStrings("hi", try s.get());
    try s.set("with space");
    try testing.expectEqualStrings("with space", try s.get());

    const i = try tk.IntVar.init(root, .{});
    try testing.expectEqual(0, try i.get());
    try i.set(-42);
    try testing.expectEqual(-42, try i.get());

    const d = try tk.DoubleVar.init(root, .{ .value = 1.5 });
    try testing.expectEqual(1.5, try d.get());

    const b = try tk.BooleanVar.init(root, .{ .value = true });
    try testing.expect(try b.get());

    // 型に合わない値がTcl側で書き込まれた場合はTclErrorになる
    _ = try root.call(.{ "set", i, "abc" });
    try testing.expectError(error.TclError, i.get());
}

test "variable traces fire on write and can be removed" {
    const root = try initRoot();
    defer root.deinit();

    const Counter = struct {
        n: u32 = 0,
        fn inc(self: *@This()) void {
            self.n += 1;
        }
    };
    var counter: Counter = .{};
    const v = try tk.StringVar.init(root, .{});
    const id = try v.traceAdd(.write, tk.callback(&counter, Counter.inc));
    try v.set("a");
    try v.set("b");
    try testing.expectEqual(2, counter.n);

    try v.traceRemove(.write, id);
    try v.set("c");
    try testing.expectEqual(2, counter.n);
}

test "textvariable links widget text and variable" {
    const root = try initRoot();
    defer root.deinit();

    const v = try tk.StringVar.init(root, .{ .value = "initial" });
    const entry = try tk.ttk.Entry.init(root, .{ .textvariable = v });
    try testing.expectEqualStrings("initial", try entry.get());

    try entry.delete(.at(0), .end);
    try entry.insert(.end, "typed");
    try testing.expectEqualStrings("typed", try v.get());

    try v.set("from var");
    try testing.expectEqualStrings("from var", try entry.get());
    try testing.expectEqual(8, try entry.index(.end));

    const label = try tk.ttk.Label.init(root, .{ .textvariable = v, .padding = .xy(4, 2) });
    try testing.expectEqualStrings("from var", try label.cget(.text));
    try testing.expectEqualStrings("4 2 4 2", try label.cget(.padding));
}

test "ttk state flags" {
    const root = try initRoot();
    defer root.deinit();

    const button = try tk.ttk.Button.init(root, .{ .text = "ok" });
    try testing.expect(!try button.instate(.disabled));
    try button.setState(.{ .disabled = true });
    try testing.expect(try button.instate(.disabled));
    try button.setState(.{ .disabled = false });
    try testing.expect(!try button.instate(.disabled));
}

test "callbacks are released when their widget is destroyed" {
    const root = try initRoot();
    defer root.deinit();

    const S = struct {
        fn noop() void {}
        fn noopEvent(_: tk.Event) void {}
    };
    const frame = try tk.Frame.init(root, .{});
    const button = try tk.Button.init(frame, .{ .command = tk.callbackFn(S.noop) });
    try button.bind("<Enter>", tk.callbackFn(S.noopEvent));
    try frame.bind("<Leave>", tk.callbackFn(S.noopEvent));
    const sibling = try tk.Button.init(root, .{ .command = tk.callbackFn(S.noop) });

    const all = "llength [concat [info commands ::zt_cb*] [info commands ::zt_bind*]]";
    try testing.expectEqualStrings("4", try root.call(.{ "eval", all }));

    // 親の破棄で子のコールバックも解放され、無関係なWidgetの分は残る
    try frame.destroy();
    try testing.expectEqualStrings("1", try root.call(.{ "eval", all }));
    _ = try sibling.invoke();

    try sibling.destroy();
    try testing.expectEqualStrings("0", try root.call(.{ "eval", all }));
}

test "unbind releases the callback" {
    const root = try initRoot();
    defer root.deinit();

    const S = struct {
        fn noopEvent(_: tk.Event) void {}
    };
    const frame = try tk.Frame.init(root, .{});
    try frame.bind("<Enter>", tk.callbackFn(S.noopEvent));
    try frame.unbind("<Enter>");
    try testing.expectEqualStrings("0", try root.call(.{ "eval", "llength [info commands ::zt_bind*]" }));
}

test "variable deinit releases trace callbacks" {
    const root = try initRoot();
    defer root.deinit();

    const S = struct {
        fn noop() void {}
    };
    const v = try tk.StringVar.init(root, .{});
    _ = try v.traceAdd(.write, tk.callbackFn(S.noop));
    try testing.expectEqualStrings("1", try root.call(.{ "eval", "llength [info commands ::zt_trace*]" }));
    v.deinit();
    try testing.expectEqualStrings("0", try root.call(.{ "eval", "llength [info commands ::zt_trace*]" }));
    try testing.expectEqualStrings("0", try root.call(.{ "info", "exists", v }));
}

test "failed widget creation releases option callbacks" {
    const root = try initRoot();
    defer root.deinit();

    const S = struct {
        fn noop() void {}
    };
    // 存在しない親を指定して生成を失敗させる
    const bogus: tk.Widget = .{ .interp = root.w.interp, .path = ".nonexistent" };
    try testing.expectError(error.TclError, tk.Button.init(bogus, .{ .command = tk.callbackFn(S.noop) }));
    try testing.expectEqualStrings("0", try root.call(.{ "eval", "llength [info commands ::zt_cb*]" }));
}

test "create-only options are accepted by init and readable by cget" {
    const root = try initRoot();
    defer root.deinit();

    const frame = try tk.Frame.init(root, .{ .class = "Fancy", .width = 40 });
    try testing.expectEqualStrings("Fancy", try root.call(.{ "winfo", "class", frame }));
    try testing.expectEqualStrings("Fancy", try frame.cget(.class));
    try frame.config(.{ .width = 50 });
    try testing.expectEqualStrings("50", try frame.cget(.width));

    const top = try tk.Toplevel.init(root, .{ .class = "Dialog", .padx = 4 });
    try top.withdraw();
    try top.title("sub window");
    try testing.expectEqualStrings("Dialog", try root.call(.{ "winfo", "class", top }));
    try testing.expectEqualStrings("sub window", try root.call(.{ "wm", "title", top }));

    const paned = try tk.ttk.Panedwindow.init(root, .{ .orient = .horizontal });
    try testing.expectEqualStrings("horizontal", try paned.cget(.orient));
    const left = try tk.Frame.init(paned, .{ .width = 100, .height = 50 });
    const right = try tk.Frame.init(paned, .{ .width = 100, .height = 50 });
    try paned.add(left, .{ .weight = 1 });
    try paned.add(right, .{ .weight = 2 });
    // Tclの結果は次の呼び出しの引数としてコピーされるため、そのまま渡せる
    try testing.expectEqualStrings("2", try root.call(.{ "llength", try root.call(.{ paned, "panes" }) }));
    try testing.expectEqualStrings("2", try root.call(.{ paned, "pane", right, "-weight" }));
}

test "wm protocol handler is invoked and released with its window" {
    const root = try initRoot();
    defer root.deinit();

    const Flag = struct {
        closed: bool = false,
        fn onClose(self: *@This()) void {
            self.closed = true;
        }
    };
    var flag: Flag = .{};
    const top = try tk.Toplevel.init(root, .{});
    try top.protocol(.delete_window, tk.callback(&flag, Flag.onClose));
    // ウィンドウマネージャからの閉じる要求を模擬する(登録されたハンドラを直接呼ぶ)
    _ = try root.call(.{try root.call(.{ "wm", "protocol", top, "WM_DELETE_WINDOW" })});
    try testing.expect(flag.closed);

    try top.destroy();
    try testing.expectEqualStrings("0", try root.call(.{ "eval", "llength [info commands ::zt_cb*]" }));
}

/// msミリ秒イベントループを回す(タイマーの発火待ち)。
fn waitMs(root: tk.Tk, ms: u32) !void {
    _ = try root.call(.{ "after", ms, "set ::zt_wait_done 1" });
    _ = try root.call(.{ "vwait", "::zt_wait_done" });
}

const TimerCounter = struct {
    n: u32 = 0,
    fn inc(self: *TimerCounter) void {
        self.n += 1;
    }
    fn fail(_: *TimerCounter) !void {
        return error.Boom;
    }
};

test "after fires once and releases its callback" {
    const root = try initRoot();
    defer root.deinit();

    var counter: TimerCounter = .{};
    const id = try root.after(1, tk.callback(&counter, TimerCounter.inc));
    try testing.expect(std.mem.startsWith(u8, id.tclId(), "after#"));
    try waitMs(root, 30);
    try testing.expectEqual(1, counter.n);
    try testing.expectEqualStrings("0", try root.call(.{ "eval", "llength [info commands {::zt_after[0-9]*}]" }));

    // 発火済みのIDを取り消しても何も起きない
    root.afterCancel(id);
}

test "afterIdle runs on update" {
    const root = try initRoot();
    defer root.deinit();

    var counter: TimerCounter = .{};
    _ = try root.afterIdle(tk.callback(&counter, TimerCounter.inc));
    try testing.expectEqual(0, counter.n);
    try root.update();
    try testing.expectEqual(1, counter.n);
}

test "afterCancel prevents firing and releases the callback" {
    const root = try initRoot();
    defer root.deinit();

    var counter: TimerCounter = .{};
    const id = try root.after(1, tk.callback(&counter, TimerCounter.inc));
    root.afterCancel(id);
    try waitMs(root, 30);
    try testing.expectEqual(0, counter.n);
    try testing.expectEqualStrings("0", try root.call(.{ "eval", "llength [info commands {::zt_after[0-9]*}]" }));
}

test "after callback errors go to bgerror and still release the callback" {
    const root = try initRoot();
    defer root.deinit();

    _ = try root.call(.{ "proc", "bgerror", "msg", "set ::zt_bgerr $msg" });
    var counter: TimerCounter = .{};
    _ = try root.after(1, tk.callback(&counter, TimerCounter.fail));
    try waitMs(root, 30);
    try testing.expect(std.mem.indexOf(u8, try root.call(.{ "set", "::zt_bgerr" }), "error.Boom") != null);
    try testing.expectEqualStrings("0", try root.call(.{ "eval", "llength [info commands {::zt_after[0-9]*}]" }));
}

/// dialogコマンドを、引数を ::zt_args に記録して reply を返すprocに差し替える。
fn fakeDialog(root: tk.Tk, command: []const u8, reply: []const u8) !void {
    _ = try root.call(.{ "set", "::zt_reply", reply });
    _ = try root.call(.{ "proc", command, "args", "set ::zt_args $args; return $::zt_reply" });
}

fn dialogArg(root: tk.Tk, option: []const u8) ![]const u8 {
    return root.call(.{ "dict", "get", try root.call(.{ "set", "::zt_args" }), option });
}

test "messagebox passes options and maps replies" {
    const root = try initRoot();
    defer root.deinit();

    try fakeDialog(root, "tk_messageBox", "yes");
    try testing.expect(try tk.messagebox.askyesno(root, "Confirm", "Proceed?", .{ .detail = "details" }));
    try testing.expectEqualStrings("yesno", try dialogArg(root, "-type"));
    try testing.expectEqualStrings("question", try dialogArg(root, "-icon"));
    try testing.expectEqualStrings("Confirm", try dialogArg(root, "-title"));
    try testing.expectEqualStrings("Proceed?", try dialogArg(root, "-message"));
    try testing.expectEqualStrings("details", try dialogArg(root, "-detail"));
    try testing.expectEqualStrings(".", try dialogArg(root, "-parent"));

    try fakeDialog(root, "tk_messageBox", "cancel");
    try testing.expectEqual(null, try tk.messagebox.askyesnocancel(root, "t", "m", .{}));

    try fakeDialog(root, "tk_messageBox", "ok");
    try tk.messagebox.showerror(root, "t", "m", .{ .default = .ok });
    try testing.expectEqualStrings("error", try dialogArg(root, "-icon"));
    try testing.expectEqualStrings("ok", try dialogArg(root, "-default"));
}

test "filedialog builds filetypes and handles cancel and multiple selection" {
    const root = try initRoot();
    defer root.deinit();

    try fakeDialog(root, "tk_getOpenFile", "C:/work/a.zig");
    const types = [_]tk.filedialog.FileType{
        .{ .name = "Zig source", .patterns = &.{ ".zig", ".zon" } },
        .{ .name = "All files", .patterns = &.{"*"} },
    };
    const path = try tk.filedialog.askopenfilename(root, .{ .title = "Open", .filetypes = &types });
    try testing.expectEqualStrings("C:/work/a.zig", path.?);
    try testing.expectEqualStrings("{{Zig source} {.zig .zon}} {{All files} *}", try dialogArg(root, "-filetypes"));

    try fakeDialog(root, "tk_getOpenFile", "");
    try testing.expectEqual(null, try tk.filedialog.askopenfilename(root, .{}));

    try fakeDialog(root, "tk_getOpenFile", "{C:/my files/a.txt} C:/b.txt");
    const files = try tk.filedialog.askopenfilenames(testing.allocator, root, .{});
    defer tk.filedialog.freeFilenames(testing.allocator, files);
    try testing.expectEqual(2, files.len);
    try testing.expectEqualStrings("C:/my files/a.txt", files[0]);
    try testing.expectEqualStrings("1", try dialogArg(root, "-multiple"));

    try fakeDialog(root, "tk_getSaveFile", "C:/out.txt");
    try testing.expectEqualStrings("C:/out.txt", (try tk.filedialog.asksaveasfilename(root, .{ .defaultextension = ".txt" })).?);
    try testing.expectEqualStrings(".txt", try dialogArg(root, "-defaultextension"));
}

test "colorchooser converts colors both ways" {
    const root = try initRoot();
    defer root.deinit();

    try fakeDialog(root, "tk_chooseColor", "#ff8000");
    const color = (try tk.colorchooser.askcolor(root, .{ .initialcolor = .{ .r = 0x10, .g = 0x20, .b = 0x30 } })).?;
    try testing.expectEqual(tk.Color{ .r = 0xff, .g = 0x80, .b = 0x00 }, color);
    try testing.expectEqualStrings("#102030", try dialogArg(root, "-initialcolor"));

    try fakeDialog(root, "tk_chooseColor", "");
    try testing.expectEqual(null, try tk.colorchooser.askcolor(root, .{}));
}

test "Tcl errors are reported with their message" {
    const root = try initRoot();
    defer root.deinit();

    try testing.expectError(error.TclError, root.call(.{"no_such_command"}));
    try testing.expect(std.mem.indexOf(u8, root.lastError(), "no_such_command") != null);
}
