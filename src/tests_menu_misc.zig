//! Menu、ttk Frame/Labelframe/Separator/Progressbar、font のテスト。
const std = @import("std");
const testing = std.testing;
const tk = @import("root.zig");

fn initRoot() !tk.Tk {
    const root = try tk.Tk.init(testing.allocator);
    _ = try root.call(.{ "wm", "withdraw", "." });
    return root;
}

fn countCommands(root: tk.Tk, pattern: []const u8) ![]const u8 {
    return root.call(.{ "llength", try root.call(.{ "info", "commands", pattern }) });
}

const Counter = struct {
    n: u32 = 0,
    fn inc(self: *Counter) void {
        self.n += 1;
    }
};

test "menubar with cascades and command items" {
    const root = try initRoot();
    defer root.deinit();

    var counter: Counter = .{};
    const menubar = try tk.Menu.init(root, .{});
    const file = try tk.Menu.init(menubar, .{ .tearoff = false });
    try file.addCommand(.{ .label = "Open", .accelerator = "Ctrl+O", .command = tk.callback(&counter, Counter.inc) });
    try file.addSeparator();
    try file.addCommand(.{ .label = "Quit", .underline = 0 });
    try menubar.addCascade(.{ .label = "File", .menu = file });
    try root.config(.{ .menu = menubar });
    try testing.expectEqualStrings(menubar.w.path, try root.cget(.menu));

    try testing.expectEqual(3, try file.count());
    try testing.expectEqual(0, (try file.index(.label("Open"))).?);
    try testing.expectEqual(2, (try file.index(.label("Q*"))).?);
    try testing.expectEqual(null, try file.index(.label("Missing")));
    try testing.expectEqualStrings("Ctrl+O", try file.entrycget(.at(0), "accelerator"));

    try file.invoke(.label("Open"));
    try testing.expectEqual(1, counter.n);

    try file.entryconfigure(.at(0), tk.Menu.CommandItemOptions{ .label = "Open...", .state = .disabled });
    try testing.expectEqualStrings("Open...", try file.entrycget(.at(0), "label"));
    try testing.expectEqualStrings("disabled", try file.entrycget(.at(0), "state"));

    try file.delete(.at(1), .end);
    try testing.expectEqual(1, try file.count());
}

test "menu tearoff shifts item indices" {
    const root = try initRoot();
    defer root.deinit();

    const menu = try tk.Menu.init(root, .{ .tearoff = true });
    try menu.addCommand(.{ .label = "First" });
    try testing.expectEqual(1, (try menu.index(.label("First"))).?);
    try testing.expectEqual(2, try menu.count());
}

test "menu check and radio items share typed variables" {
    const root = try initRoot();
    defer root.deinit();

    const Theme = enum { light, dark };
    const wrap = try tk.BooleanVar.init(root, .{});
    const theme = try tk.Variable(Theme).init(root, .{});
    const view = try tk.Menu.init(root, .{ .tearoff = false });
    try view.addCheckbutton(bool, .{ .label = "Wrap", .variable = wrap });
    try view.addRadiobutton(Theme, .{ .label = "Light", .variable = theme, .value = .light });
    try view.addRadiobutton(Theme, .{ .label = "Dark", .variable = theme, .value = .dark });

    try view.invoke(.label("Wrap"));
    try testing.expect(try wrap.get());
    try view.invoke(.label("Dark"));
    try testing.expectEqual(Theme.dark, try theme.get());
    try view.invoke(.label("Light"));
    try testing.expectEqual(Theme.light, try theme.get());
}

test "menu item callbacks are released with the menu" {
    const root = try initRoot();
    defer root.deinit();

    var counter: Counter = .{};
    const menu = try tk.Menu.init(root, .{ .tearoff = false, .postcommand = tk.callback(&counter, Counter.inc) });
    try menu.addCommand(.{ .label = "a", .command = tk.callback(&counter, Counter.inc) });
    try menu.addCommand(.{ .label = "b", .command = tk.callback(&counter, Counter.inc) });
    try menu.entryconfigure(.at(0), tk.Menu.CommandItemOptions{ .command = tk.callback(&counter, Counter.inc) });
    try testing.expect(!std.mem.eql(u8, "0", try countCommands(root, "::zt_cb*")));
    try menu.destroy();
    try testing.expectEqualStrings("0", try countCommands(root, "::zt_cb*"));
}

test "ttk frame, labelframe and separator" {
    const root = try initRoot();
    defer root.deinit();

    const frame = try tk.ttk.Frame.init(root, .{ .class = "Toolbar", .padding = .all(4) });
    try testing.expectEqualStrings("Toolbar", try root.call(.{ "winfo", "class", frame }));
    try testing.expectEqualStrings("Toolbar", try frame.cget(.class));
    try frame.config(.{ .relief = .groove });

    const group = try tk.ttk.Labelframe.init(frame, .{ .text = "Options", .labelanchor = .nw });
    try testing.expectEqualStrings("Options", try group.cget(.text));
    try group.config(.{ .labelanchor = .ne });
    try testing.expectEqualStrings("ne", try group.cget(.labelanchor));

    const sep = try tk.ttk.Separator.init(frame, .{ .orient = .vertical });
    try testing.expectEqualStrings("vertical", try sep.cget(.orient));
}

test "progressbar value, step and variable" {
    const root = try initRoot();
    defer root.deinit();

    const level = try tk.DoubleVar.init(root, .{});
    const bar = try tk.ttk.Progressbar.init(root, .{ .maximum = 10, .variable = level, .length = 200 });
    try bar.setValue(4);
    try testing.expectEqual(4, try bar.value());
    try testing.expectEqual(4, try level.get());
    try bar.step(2.5);
    try testing.expectEqual(6.5, try bar.value());
    try level.set(9);
    try testing.expectEqual(9, try bar.value());

    const busy = try tk.ttk.Progressbar.init(root, .{ .mode = .indeterminate });
    try busy.start(20);
    try busy.stop();
}

test "named fonts" {
    const root = try initRoot();
    defer root.deinit();

    const heading = try tk.font.Font.init(root, .{ .family = "Courier", .size = 14, .weight = .bold });
    const label = try tk.Label.init(root, .{ .text = "Title", .font = heading.name() });
    try testing.expectEqualStrings(heading.name(), try label.cget(.font));
    try testing.expectEqualStrings("bold", try root.call(.{ "font", "configure", heading, "-weight" }));

    const narrow = try heading.measure("i");
    const wide = try heading.measure("iiiiiiiiii");
    try testing.expect(narrow > 0 and wide > narrow);
    try testing.expect(try heading.metrics(.linespace) > 0);
    try testing.expect(try heading.metrics(.ascent) > 0);

    try heading.config(.{ .size = 20, .slant = .italic });
    try testing.expectEqualStrings("20", try root.call(.{ "font", "configure", heading, "-size" }));

    const fixed = tk.font.Font.named(root, tk.font.standard.fixed);
    try testing.expect(try fixed.isFixed());
    fixed.deinit(); // namedは削除しない
    try testing.expect(try fixed.measure("abc") > 0);

    heading.deinit();
    const all = try tk.font.names(testing.allocator, root);
    defer tk.freeStrings(testing.allocator, all);
    for (all) |n| try testing.expect(!std.mem.eql(u8, n, heading.name()));

    const fams = try tk.font.families(testing.allocator, root);
    defer tk.freeStrings(testing.allocator, fams);
    try testing.expect(fams.len > 0);
}

test "ttk style themes, configure, map and lookup" {
    const root = try initRoot();
    defer root.deinit();

    const style = tk.ttk.Style.init(root);
    const themes = try style.themeNames(testing.allocator);
    defer tk.freeStrings(testing.allocator, themes);
    var has_clam = false;
    for (themes) |t| has_clam = has_clam or std.mem.eql(u8, t, "clam");
    try testing.expect(has_clam);

    try style.themeUse("clam");
    try testing.expectEqualStrings("clam", try style.currentTheme());

    try style.configure("Accent.TButton", .{ .foreground = "white", .background = "#3366cc", .padding = .xy(12, 4) });
    try testing.expectEqualStrings("white", try style.lookup("Accent.TButton", "foreground", null));
    try testing.expectEqualStrings("12 4 12 4", try style.lookup("Accent.TButton", "padding", null));

    try style.map("Accent.TButton", "background", &.{
        .{ .state = .{ .pressed = true }, .value = "#224488" },
        .{ .state = .{ .active = true, .disabled = false }, .value = "#4477dd" },
    });
    try testing.expectEqualStrings("#224488", try style.lookup("Accent.TButton", "background", .{ .pressed = true }));
    try testing.expectEqualStrings("#4477dd", try style.lookup("Accent.TButton", "background", .{ .active = true }));
    try testing.expectEqualStrings("#3366cc", try style.lookup("Accent.TButton", "background", null));
    try testing.expectEqualStrings("pressed #224488 {active !disabled} #4477dd", try root.call(.{ "ttk::style", "map", "Accent.TButton", "-background" }));

    try style.configureRaw("Accent.TButton", .{ "-focuscolor", "orange" });
    try testing.expectEqualStrings("orange", try style.lookup("Accent.TButton", "focuscolor", null));

    const button = try tk.ttk.Button.init(root, .{ .text = "OK", .style = "Accent.TButton" });
    try testing.expectEqualStrings("Accent.TButton", try button.cget(.style));
    try button.setState(.{ .disabled = true, .pressed = false });
    try testing.expect(try button.instate(.disabled));
}
