//! ttk + StringVarのサンプル: 入力が空の間はOKボタンを無効化し、入力内容をラベルへ反映する。
const std = @import("std");
const tk = @import("zig_tk");
const ttk = tk.ttk;

const Form = struct {
    name: tk.StringVar,
    password: tk.StringVar,
    status: tk.StringVar,
    ok: ttk.Button = undefined,

    fn onInput(self: *Form) !void {
        const name = try self.name.get();
        try self.ok.setState(.{ .disabled = name.len == 0 });

        var buf: [128]u8 = undefined;
        const msg = if (name.len == 0) "Enter your name" else try std.fmt.bufPrint(&buf, "Hello, {s}!", .{name});
        try self.status.set(msg);
    }

    fn onSubmit(self: *Form) !void {
        const len = (try self.password.get()).len;
        var buf: [128]u8 = undefined;
        try self.status.set(try std.fmt.bufPrint(&buf, "Submitted ({d}-char password)", .{len}));
    }
};

pub fn main(init: std.process.Init) !void {
    const root = try tk.Tk.init(init.gpa);
    defer root.deinit();
    try root.title("zig_tk form");

    var form: Form = .{
        .name = try .init(root, .{}),
        .password = try .init(root, .{}),
        .status = try .init(root, .{}),
    };

    const body = try tk.Frame.init(root, .{ .padx = 12, .pady = 12 });
    try body.pack(.{ .fill = .both, .expand = true });

    const name_label = try ttk.Label.init(body, .{ .text = "Name" });
    try name_label.grid(.{ .row = 0, .column = 0, .sticky = .{ .w = true }, .pady = .all(2) });
    const name_entry = try ttk.Entry.init(body, .{ .textvariable = form.name, .width = 24 });
    try name_entry.grid(.{ .row = 0, .column = 1, .sticky = .ew, .pady = .all(2) });

    const pw_label = try ttk.Label.init(body, .{ .text = "Password" });
    try pw_label.grid(.{ .row = 1, .column = 0, .sticky = .{ .w = true }, .pady = .all(2) });
    const pw_entry = try ttk.Entry.init(body, .{ .textvariable = form.password, .show = "*", .width = 24 });
    try pw_entry.grid(.{ .row = 1, .column = 1, .sticky = .ew, .pady = .all(2) });

    form.ok = try ttk.Button.init(body, .{ .text = "OK", .command = tk.callback(&form, Form.onSubmit) });
    try form.ok.grid(.{ .row = 2, .column = 1, .sticky = .{ .e = true }, .pady = .all(6) });

    const status = try ttk.Label.init(body, .{ .textvariable = form.status, .foreground = "gray25" });
    try status.grid(.{ .row = 3, .column = 0, .columnspan = 2, .sticky = .{ .w = true } });

    _ = try form.name.traceAdd(.write, tk.callback(&form, Form.onInput));
    try form.onInput();
    try name_entry.w.focusSet();

    root.mainloop();
}
