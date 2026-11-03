//! 変数と結び付く入力系Widget(Checkbutton/Radiobutton/Scale/Spinbox/Combobox)のテスト。
const std = @import("std");
const testing = std.testing;
const tk = @import("root.zig");

fn initRoot() !tk.Tk {
    const root = try tk.Tk.init(testing.allocator);
    _ = try root.call(.{ "wm", "withdraw", "." });
    return root;
}

const Size = enum { small, medium, large };

test "enum variables store tag names and reject unknown values" {
    const root = try initRoot();
    defer root.deinit();

    const size = try tk.Variable(Size).init(root, .{});
    try testing.expectEqual(Size.small, try size.get());
    try size.set(.large);
    try testing.expectEqualStrings("large", try root.call(.{ "set", size }));

    _ = try root.call(.{ "set", size, "huge" });
    try testing.expectError(error.TclError, size.get());
    try testing.expect(std.mem.indexOf(u8, root.lastError(), "invalid value") != null);
}

test "checkbutton toggles its BooleanVar" {
    const root = try initRoot();
    defer root.deinit();

    const Counter = struct {
        n: u32 = 0,
        fn inc(self: *@This()) void {
            self.n += 1;
        }
    };
    var counter: Counter = .{};
    const flag = try tk.BooleanVar.init(root, .{});
    const check = try tk.Checkbutton.init(root, .{ .text = "Enable", .variable = flag, .command = tk.callback(&counter, Counter.inc) });

    try check.invoke();
    try testing.expect(try flag.get());
    try testing.expectEqual(1, counter.n);
    try check.deselect();
    try testing.expect(!try flag.get());
    try check.toggle();
    try testing.expect(try flag.get());
    // select/deselect/toggleはcommandを呼ばない
    try testing.expectEqual(1, counter.n);

    const ttk_check = try tk.ttk.Checkbutton.init(root, .{ .variable = flag });
    try testing.expect(try ttk_check.instate(.selected));
    try ttk_check.invoke();
    try testing.expect(!try flag.get());
}

test "checkbutton onvalue/offvalue share the variable's type" {
    const root = try initRoot();
    defer root.deinit();

    const mode = try tk.StringVar.init(root, .{ .value = "off" });
    const check = try tk.CheckbuttonOf([]const u8).init(root, .{ .variable = mode, .onvalue = "on", .offvalue = "off" });
    try check.invoke();
    try testing.expectEqualStrings("on", try mode.get());

    const level = try tk.IntVar.init(root, .{});
    const ttk_check = try tk.ttk.CheckbuttonOf(i64).init(root, .{ .variable = level, .onvalue = 5, .offvalue = -1 });
    try ttk_check.invoke();
    try testing.expectEqual(5, try level.get());
    try ttk_check.invoke();
    try testing.expectEqual(-1, try level.get());
}

test "radiobuttons with an enum variable" {
    const root = try initRoot();
    defer root.deinit();

    const size = try tk.Variable(Size).init(root, .{ .value = .medium });
    const small = try tk.RadiobuttonOf(Size).init(root, .{ .text = "Small", .variable = size, .value = .small });
    const large = try tk.ttk.RadiobuttonOf(Size).init(root, .{ .text = "Large", .variable = size, .value = .large });

    try small.invoke();
    try testing.expectEqual(Size.small, try size.get());
    try large.invoke();
    try testing.expectEqual(Size.large, try size.get());
    try testing.expect(try large.instate(.selected));

    // 変数側を変えるとボタンの選択状態が追従する
    try size.set(.small);
    try testing.expect(!try large.instate(.selected));
    try small.deselect();
    try testing.expectEqualStrings("", try root.call(.{ "set", size }));
}

test "scales report values and follow their variable" {
    const root = try initRoot();
    defer root.deinit();

    const level = try tk.DoubleVar.init(root, .{ .value = 2.5 });
    const scale = try tk.Scale.init(root, .{ .from = 0, .to = 10, .resolution = 0.5, .orient = .horizontal, .variable = level });
    try testing.expectEqual(2.5, try scale.get());
    try scale.set(7.3);
    // resolution(0.5刻み)に丸められる
    try testing.expectEqual(7.5, try scale.get());
    try testing.expectEqual(7.5, try level.get());

    const ttk_scale = try tk.ttk.Scale.init(root, .{ .from = -1, .to = 1, .variable = level });
    try ttk_scale.set(0.25);
    try testing.expectEqual(0.25, try level.get());
    try testing.expectEqualStrings("-1.0", try ttk_scale.cget(.from));
}

test "scale commands receive the current value" {
    const root = try initRoot();
    defer root.deinit();

    const Probe = struct {
        value: f64 = 0,
        plain_calls: u32 = 0,
        fn onValue(self: *@This(), value: f64) !void {
            self.value = value;
        }
        fn onPlain(self: *@This()) !void {
            self.plain_calls += 1;
        }
    };
    var probe: Probe = .{};
    // Tkはcommandに現在値を付け足して呼ぶ。func(ctx, f64)はそれを受け取り、func(ctx)は無視する
    const scale = try tk.ttk.Scale.init(root, .{ .from = 0, .to = 10, .command = tk.callback(&probe, Probe.onValue) });
    _ = try root.call(.{ try scale.cget(.command), "3.5" });
    try testing.expectEqual(3.5, probe.value);

    const classic = try tk.Scale.init(root, .{ .from = 0, .to = 10, .command = tk.callback(&probe, Probe.onPlain) });
    _ = try root.call(.{ try classic.cget(.command), "4" });
    try testing.expectEqual(1, probe.plain_calls);
}

test "spinboxes step through values" {
    const root = try initRoot();
    defer root.deinit();

    const spin = try tk.Spinbox.init(root, .{ .values = &.{ "red", "green", "blue" }, .wrap = true });
    try testing.expectEqualStrings("red", try spin.get());
    _ = try root.call(.{ spin, "invoke", "buttonup" });
    try testing.expectEqualStrings("green", try spin.get());
    try spin.set("blue");
    _ = try root.call(.{ spin, "invoke", "buttonup" });
    try testing.expectEqualStrings("red", try spin.get());

    const text = try tk.StringVar.init(root, .{});
    const ttk_spin = try tk.ttk.Spinbox.init(root, .{ .from = 1, .to = 3, .increment = 1, .textvariable = text });
    try ttk_spin.set("2");
    try testing.expectEqualStrings("2", try text.get());
    try ttk_spin.delete(.at(0), .end);
    try ttk_spin.insert(.end, "3");
    try testing.expectEqualStrings("3", try ttk_spin.get());
}

test "combobox selection by index and text" {
    const root = try initRoot();
    defer root.deinit();

    const combo = try tk.ttk.Combobox.init(root, .{ .values = &.{ "Zig", "C", "Tcl" }, .state = .readonly });
    try testing.expectEqual(null, try combo.current());
    try combo.setCurrent(2);
    try testing.expectEqualStrings("Tcl", try combo.get());
    try testing.expectEqual(2, (try combo.current()).?);
    try combo.set("C");
    try testing.expectEqual(1, (try combo.current()).?);
    try combo.set("Rust");
    try testing.expectEqual(null, try combo.current());

    try combo.config(.{ .values = &.{"only"} });
    try testing.expectEqualStrings("only", try combo.cget(.values));
}

test "validatecommand accepts or rejects edits with typed details" {
    const root = try initRoot();
    defer root.deinit();

    const Digits = struct {
        last: ?tk.Validation.Action = null,
        last_reason: ?tk.Validation.Reason = null,
        last_index: i32 = -2,
        new_text: [32]u8 = undefined,
        new_len: usize = 0,
        rejected: u32 = 0,

        fn check(self: *@This(), v: tk.Validation) bool {
            self.last = v.action;
            self.last_reason = v.reason;
            self.last_index = v.index;
            self.new_len = @min(v.new_text.len, self.new_text.len);
            @memcpy(self.new_text[0..self.new_len], v.new_text[0..self.new_len]);
            for (v.change) |c| if (!std.ascii.isDigit(c)) return false;
            return true;
        }
        fn onInvalid(self: *@This()) void {
            self.rejected += 1;
        }
    };
    var digits: Digits = .{};
    const entry = try tk.ttk.Entry.init(root, .{
        .validate = .key,
        .validatecommand = tk.callback(&digits, Digits.check),
        .invalidcommand = tk.callback(&digits, Digits.onInvalid),
    });

    try entry.insert(.end, "12");
    try testing.expectEqualStrings("12", try entry.get());
    try testing.expectEqual(tk.Validation.Action.insert, digits.last.?);
    try testing.expectEqual(tk.Validation.Reason.key, digits.last_reason.?);

    try entry.insert(.end, "3a");
    try testing.expectEqualStrings("12", try entry.get());
    try testing.expectEqualStrings("123a", digits.new_text[0..digits.new_len]);
    try testing.expectEqual(2, digits.last_index);
    try testing.expectEqual(1, digits.rejected);

    try entry.delete(.at(0), null);
    try testing.expectEqualStrings("2", try entry.get());
    try testing.expectEqual(tk.Validation.Action.delete, digits.last.?);

    try testing.expect(try entry.validateNow());
    try testing.expectEqual(tk.Validation.Reason.forced, digits.last_reason.?);

    // 検証コールバックもWidgetの破棄時に解放される
    try entry.destroy();
    try testing.expectEqualStrings("0", try root.call(.{ "llength", try root.call(.{ "info", "commands", "::zt_cb*" }) }));
}
