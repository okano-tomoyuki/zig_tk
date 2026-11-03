//! Text + Scrollbar + Menuのサンプル: Undo/Redo、折り返しの切り替え、検索語のハイライト、
//! 右クリックのポップアップメニュー。
const std = @import("std");
const tk = @import("zig_tk");
const ttk = tk.ttk;
const I = tk.Text.Index;

const App = struct {
    text: tk.Text = undefined,
    query: ttk.Entry = undefined,
    popup_menu: tk.Menu = undefined,
    status: tk.StringVar,
    wrap: tk.BooleanVar,

    fn toggleWrap(self: *App) !void {
        try self.text.config(.{ .wrap = if (try self.wrap.get()) .word else .none });
    }

    fn showPopup(self: *App, e: tk.Event) !void {
        try self.popup_menu.popup(e.x_root, e.y_root);
    }

    fn undo(self: *App) !void {
        self.text.editUndo() catch try self.status.set("これ以上元に戻せません");
    }

    fn redo(self: *App) !void {
        self.text.editRedo() catch try self.status.set("これ以上やり直せません");
    }

    /// 検索語の出現箇所すべてに "hit" タグを付ける。
    fn highlight(self: *App) !void {
        try self.text.tagRemove("hit", .at(1, 0), .end);
        const query = try self.query.get();
        if (query.len == 0) return;
        // queryはTcl呼び出しで上書きされるため複製しておく
        var buf: [256]u8 = undefined;
        const pattern = buf[0..@min(query.len, buf.len)];
        @memcpy(pattern, query[0..pattern.len]);

        var count: usize = 0;
        var from: I = .at(1, 0);
        while (try self.text.search(pattern, from, .{ .nocase = true, .stop = .end })) |pos| {
            const start = I.fromPos(pos);
            const stop = start.plusChars(@intCast(pattern.len));
            try self.text.tagAdd("hit", start, stop);
            from = stop;
            count += 1;
        }
        var msg: [64]u8 = undefined;
        try self.status.set(try std.fmt.bufPrint(&msg, "{d} 件", .{count}));
    }

    fn highlightKey(self: *App, _: tk.Event) !void {
        try self.highlight();
    }
};

pub fn main(init: std.process.Init) !void {
    const root = try tk.Tk.init(init.gpa);
    defer root.deinit();
    try root.title("zig_tk editor");

    var app: App = .{ .status = try .init(root, .{}), .wrap = try .init(root, .{ .value = true }) };

    // メニューバー
    const menubar = try tk.Menu.init(root, .{});
    const edit = try tk.Menu.init(menubar, .{ .tearoff = false });
    try edit.addCommand(.{ .label = "元に戻す", .accelerator = "Ctrl+Z", .command = tk.callback(&app, App.undo) });
    try edit.addCommand(.{ .label = "やり直し", .accelerator = "Ctrl+Y", .command = tk.callback(&app, App.redo) });
    try menubar.addCascade(.{ .label = "編集", .menu = edit });
    const view = try tk.Menu.init(menubar, .{ .tearoff = false });
    try view.addCheckbutton(bool, .{ .label = "折り返し", .variable = app.wrap, .command = tk.callback(&app, App.toggleWrap) });
    try menubar.addCascade(.{ .label = "表示", .menu = view });
    const quit = tk.callback(&root, tk.Tk.quit);
    try menubar.addCommand(.{ .label = "終了", .command = quit });
    try root.config(.{ .menu = menubar });

    // 右クリックのポップアップメニュー
    app.popup_menu = try tk.Menu.init(root, .{ .tearoff = false });
    try app.popup_menu.addCommand(.{ .label = "元に戻す", .command = tk.callback(&app, App.undo) });
    try app.popup_menu.addCommand(.{ .label = "やり直し", .command = tk.callback(&app, App.redo) });

    const toolbar = try tk.Frame.init(root, .{ .padx = 4, .pady = 4 });
    try toolbar.pack(.{ .fill = .x });
    const undo = try ttk.Button.init(toolbar, .{ .text = "元に戻す", .command = tk.callback(&app, App.undo) });
    try undo.pack(.{ .side = .left });
    const redo = try ttk.Button.init(toolbar, .{ .text = "やり直し", .command = tk.callback(&app, App.redo) });
    try redo.pack(.{ .side = .left, .padx = .all(4) });
    app.query = try ttk.Entry.init(toolbar, .{ .width = 20 });
    try app.query.pack(.{ .side = .left, .padx = .all(4) });
    try app.query.bind("<Return>", tk.callback(&app, App.highlightKey));
    const find = try ttk.Button.init(toolbar, .{ .text = "検索", .command = tk.callback(&app, App.highlight) });
    try find.pack(.{ .side = .left });
    const status = try ttk.Label.init(toolbar, .{ .textvariable = app.status });
    try status.pack(.{ .side = .right });

    const body = try tk.Frame.init(root, .{});
    try body.pack(.{ .fill = .both, .expand = true });
    app.text = try tk.Text.init(body, .{ .wrap = .word, .undo = true, .width = 60, .height = 20, .padx = 6, .pady = 6 });
    const sb = try ttk.Scrollbar.init(body, .{});
    try sb.attach(app.text, .y);
    try sb.pack(.{ .side = .right, .fill = .y });
    try app.text.pack(.{ .side = .left, .fill = .both, .expand = true });
    try app.text.bind("<Button-3>", tk.callback(&app, App.showPopup));

    try app.text.tagConfigure("hit", .{ .background = "yellow" });
    try app.text.tagConfigure("title", .{ .font = "TkHeadingFont 14 bold", .spacing3 = 6 });
    try app.text.insertTagged(.end, "zig_tk editor\n", &.{"title"});
    try app.text.insert(.end, "Tcl/Tk の Text ウィジェットを Zig から操作するサンプルです。\n" ++
        "検索欄に語を入れて Enter を押すと、出現箇所がハイライトされます。\n");
    try app.text.editReset();
    try app.text.markSet("insert", .end);
    try app.text.w.focusSet();

    root.mainloop();
}
