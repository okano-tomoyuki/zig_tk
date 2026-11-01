//! classic Entry/LabelFrame/PanedWindow/Message/Menubutton/OptionMenu と ttk Menubutton のテスト。
const std = @import("std");
const testing = std.testing;
const tk = @import("root.zig");

fn initRoot() !tk.Tk {
    const root = try tk.Tk.init(testing.allocator);
    _ = try root.call(.{ "wm", "withdraw", "." });
    return root;
}

test "classic entry" {
    const root = try initRoot();
    defer root.deinit();

    const text = try tk.StringVar.init(root, .{ .value = "hello" });
    const entry = try tk.Entry.init(root, .{ .textvariable = text, .width = 20, .readonlybackground = "gray90" });
    try testing.expectEqualStrings("hello", try entry.get());
    try entry.insert(.end, " world");
    try testing.expectEqualStrings("hello world", try text.get());
    try entry.config(.{ .state = .readonly });
    try testing.expectEqualStrings("readonly", try entry.cget(.state));

    const sb = try tk.Scrollbar.init(root, .{});
    try sb.attach(entry, .x);
    try testing.expectEqualStrings("horizontal", try sb.cget(.orient));
}

test "classic labelframe, panedwindow and message" {
    const root = try initRoot();
    defer root.deinit();

    const group = try tk.LabelFrame.init(root, .{ .class = "Group", .text = "Options", .labelanchor = .n, .padx = 4 });
    try testing.expectEqualStrings("Group", try group.winfoClass());
    try group.config(.{ .text = "Settings" });
    try testing.expectEqualStrings("Settings", try group.cget(.text));

    const paned = try tk.PanedWindow.init(root, .{ .orient = .horizontal, .showhandle = true, .sashwidth = 6 });
    const left = try tk.Frame.init(paned, .{ .width = 100, .height = 50 });
    const right = try tk.Frame.init(paned, .{ .width = 100, .height = 50 });
    try paned.add(left, .{ .minsize = 40 });
    try paned.add(right, .{ .stretch = .always, .sticky = .nsew });
    try testing.expectEqualStrings("2", try root.call(.{ "llength", try root.call(.{ paned, "panes" }) }));
    try paned.paneconfigure(left, .{ .minsize = 60 });
    try testing.expectEqualStrings("60", try root.call(.{ paned, "panecget", left, "-minsize" }));
    try testing.expectEqualStrings("always", try root.call(.{ paned, "panecget", right, "-stretch" }));
    try paned.forget(left);
    try testing.expectEqualStrings("1", try root.call(.{ "llength", try root.call(.{ paned, "panes" }) }));

    const msg = try tk.Message.init(root, .{ .text = "A long message that wraps", .width = 80, .justify = .center });
    try testing.expectEqualStrings("80", try msg.cget(.width));
}

test "menubuttons open their menu" {
    const root = try initRoot();
    defer root.deinit();

    const mb = try tk.Menubutton.init(root, .{ .text = "File", .direction = .below, .indicatoron = true });
    const menu = try tk.Menu.init(mb, .{ .tearoff = false });
    try menu.addCommand(.{ .label = "Open" });
    try mb.config(.{ .menu = menu });
    try testing.expectEqualStrings(menu.w.path, try mb.cget(.menu));

    const tmb = try tk.ttk.Menubutton.init(root, .{ .text = "Edit", .direction = .right });
    const tmenu = try tk.Menu.init(tmb, .{ .tearoff = false });
    try tmb.config(.{ .menu = tmenu });
    try testing.expectEqualStrings(tmenu.w.path, try tmb.cget(.menu));
    try testing.expectEqualStrings("right", try tmb.cget(.direction));
}

test "option menu with an enum variable" {
    const root = try initRoot();
    defer root.deinit();

    const Size = enum { small, medium, large };
    const size = try tk.Variable(Size).init(root, .{ .value = .medium });
    const om = try tk.OptionMenuOf(Size).init(root, size, &.{ .small, .medium, .large }, .{ .width = 10 });
    try testing.expectEqual(3, try om.menu.count());
    try testing.expectEqualStrings("medium", try root.call(.{ om.w.path, "cget", "-text" }));

    try om.menu.invoke(.label("large"));
    try testing.expectEqual(Size.large, try size.get());
    try testing.expectEqualStrings("large", try root.call(.{ om.w.path, "cget", "-text" }));
    try testing.expectEqualStrings("10", try om.cget(.width));
}

test "option menu with strings, command and setValues" {
    const root = try initRoot();
    defer root.deinit();

    const Counter = struct {
        n: u32 = 0,
        fn inc(self: *@This()) void {
            self.n += 1;
        }
    };
    var counter: Counter = .{};
    const lang = try tk.StringVar.init(root, .{ .value = "Zig" });
    const om = try tk.OptionMenu.init(root, lang, &.{ "Zig", "C", "Tcl" }, .{ .command = tk.callback(&counter, Counter.inc) });
    try om.menu.invoke(.label("Tcl"));
    try testing.expectEqualStrings("Tcl", try lang.get());
    try testing.expectEqual(1, counter.n);

    try om.setValues(&.{ "Rust", "Go" });
    try testing.expectEqual(2, try om.menu.count());
    try om.menu.invoke(.at(1));
    try testing.expectEqualStrings("Go", try lang.get());
    try testing.expectEqual(2, counter.n);

    const ints = try tk.IntVar.init(root, .{ .value = 2 });
    const iom = try tk.OptionMenuOf(i64).init(root, ints, &.{ 1, 2, 3 }, .{});
    try testing.expectEqualStrings("3", try iom.menu.entrycget(.at(2), "label"));

    try om.destroy();
    try iom.destroy();
    try testing.expectEqualStrings("0", try root.call(.{ "llength", try root.call(.{ "info", "commands", "::zt_cb*" }) }));
}
