//! レイアウト(grid設定)・winfo・eventGenerate と、Widget共通メソッドの公開漏れの検査。
const std = @import("std");
const testing = std.testing;
const tk = @import("root.zig");
const widget = @import("widget.zig");

fn initRoot() !tk.Tk {
    const root = try tk.Tk.init(testing.allocator);
    _ = try root.call(.{ "wm", "withdraw", "." });
    return root;
}

/// 画面外に表示する(マップが必要なwinfo/イベントの検証用)。
fn showOffscreen(root: tk.Tk) !void {
    try root.geometry("+-3000+-3000");
    try root.deiconify();
    try root.update();
}

test "every widget type exposes the common methods" {
    @setEvalBranchQuota(20_000);
    const all_types = .{
        tk.Button,          tk.Label,              tk.Frame,           tk.Toplevel,      tk.Checkbutton,
        tk.Radiobutton,     tk.Scale,              tk.Spinbox,         tk.Scrollbar,     tk.Listbox,
        tk.Text,            tk.Canvas,             tk.Menu,            tk.Tk,            tk.ttk.Button,
        tk.ttk.Label,       tk.ttk.Entry,          tk.ttk.Panedwindow, tk.ttk.Checkbutton, tk.ttk.Radiobutton,
        tk.ttk.Scale,       tk.ttk.Spinbox,        tk.ttk.Combobox,    tk.ttk.Scrollbar, tk.ttk.Notebook,
        tk.ttk.Treeview,    tk.ttk.Frame,          tk.ttk.Labelframe,  tk.ttk.Separator, tk.ttk.Progressbar,
        tk.Entry,           tk.LabelFrame,         tk.PanedWindow,     tk.Message,       tk.Menubutton,
        tk.OptionMenu,      tk.ttk.Menubutton,
    };
    // トップレベル/メニューはジオメトリマネージャで配置しないためpack/grid/placeを持たない
    const unplaced = [_][]const u8{ "pack", "grid", "place" };
    inline for (all_types) |T| {
        const top_or_menu = T == tk.Tk or T == tk.Toplevel or T == tk.Menu;
        inline for (widget.common_method_names) |name| {
            const skip = top_or_menu and comptime for (unplaced) |u| {
                if (std.mem.eql(u8, u, name)) break true;
            } else false;
            if (!skip and !@hasDecl(T, name)) @compileError(@typeName(T) ++ " does not expose " ++ name);
        }
    }
}

test "grid row and column weights distribute extra space" {
    const root = try initRoot();
    defer root.deinit();

    const frame = try tk.ttk.Frame.init(root, .{ .width = 300, .height = 100 });
    try frame.pack(.{ .fill = .both, .expand = true });
    try frame.gridPropagate(false);
    // 同じuniformグループの列はweightに比例した幅になる(グループ外だと要求幅を確保した残りを配分する)
    try frame.gridColumnconfigure(0, .{ .weight = 1, .uniform = "cols" });
    try frame.gridColumnconfigure(1, .{ .weight = 2, .uniform = "cols" });
    try frame.gridRowconfigure(0, .{ .weight = 1, .minsize = 10, .pad = 0 });
    try testing.expectEqualStrings("2", try root.call(.{ "grid", "columnconfigure", frame, 1, "-weight" }));
    try testing.expectEqualStrings("cols", try root.call(.{ "grid", "columnconfigure", frame, 0, "-uniform" }));
    try testing.expectEqualStrings("10", try root.call(.{ "grid", "rowconfigure", frame, 0, "-minsize" }));

    const left = try tk.Frame.init(frame, .{ .background = "red" });
    const right = try tk.Frame.init(frame, .{ .background = "blue" });
    try left.grid(.{ .row = 0, .column = 0, .sticky = .nsew });
    try right.grid(.{ .row = 0, .column = 1, .sticky = .nsew });
    try showOffscreen(root);

    try testing.expectEqual(300, try frame.winfo(.width));
    const lw = try left.winfo(.width);
    const rw = try right.winfo(.width);
    try testing.expectEqual(300, lw + rw);
    try testing.expectEqual(100, lw);
    try testing.expectEqual(0, try left.winfo(.x));
    try testing.expectEqual(lw, try right.winfo(.x));
    try testing.expect(try right.winfoIsmapped());

    try right.gridForget();
    try root.update();
    try testing.expect(!try right.winfoIsmapped());
    try testing.expect(try right.winfoExists());
    try right.destroy();
    try testing.expect(!try right.winfoExists());
}

test "winfo class and screen size" {
    const root = try initRoot();
    defer root.deinit();

    const button = try tk.ttk.Button.init(root, .{});
    try testing.expectEqualStrings("TButton", try button.winfoClass());
    try testing.expect(try root.winfo(.screenwidth) > 0);
    try testing.expect(try button.winfo(.reqwidth) > 0);
}

test "eventGenerate delivers virtual events with data" {
    const root = try initRoot();
    defer root.deinit();

    const Recorder = struct {
        x: i32 = -1,
        fn onEvent(self: *@This(), e: tk.Event) void {
            self.x = e.x;
        }
    };
    var rec: Recorder = .{};
    const frame = try tk.Frame.init(root, .{ .width = 20, .height = 20 });
    try frame.pack(.{});
    try showOffscreen(root);
    try frame.bind("<<Ping>>", tk.callback(&rec, Recorder.onEvent));
    try frame.eventGenerate("<<Ping>>", .{ .x = 7, .when = .now, .data = "payload" });
    try testing.expectEqual(7, rec.x);
}
