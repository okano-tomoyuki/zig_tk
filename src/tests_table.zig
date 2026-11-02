const std = @import("std");
const testing = std.testing;
const tk = @import("root.zig");

const Role = enum { dev, ops, sales };
const Person = struct {
    name: []const u8,
    age: u32,
    role: Role,
    active: bool,
    score: ?f64 = null,
};

const people = [_]Person{
    .{ .name = "Carol", .age = 41, .role = .sales, .active = false, .score = 3.5 },
    .{ .name = "alice", .age = 30, .role = .ops, .active = true },
    .{ .name = "Bob", .age = 25, .role = .dev, .active = true, .score = 4.25 },
};

fn initRoot() !tk.Tk {
    const root = try tk.Tk.init(testing.allocator);
    _ = try root.call(.{ "wm", "withdraw", "." });
    return root;
}

/// 表示順のname列を ' ' 区切りで返す。
fn names(root: tk.Tk, table: anytype) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(testing.allocator);
    const items = try table.treeview().children(testing.allocator, .root);
    defer testing.allocator.free(items);
    for (items, 0..) |item, i| {
        if (i > 0) try out.append(testing.allocator, ' ');
        try out.appendSlice(testing.allocator, try root.call(.{ table.treeview(), "set", item, "name" }));
    }
    return out.toOwnedSlice(testing.allocator);
}

test "table shows struct fields as columns and formats each type" {
    const root = try initRoot();
    defer root.deinit();
    const table = try tk.Table(Person).init(testing.allocator, root, .{});
    defer table.deinit();
    try table.pack(.{});

    var rows = people;
    var name_buf = "Carol".*;
    rows[0].name = &name_buf;
    try table.setRows(&rows);
    // 表は文字列を複製して持つ
    name_buf[0] = 'X';
    try testing.expectEqualStrings("Carol", table.get(0).name);

    try testing.expectEqualStrings("name age role active score", try root.call(.{ table.treeview(), "cget", "-columns" }));
    const tv = table.treeview();
    try testing.expectEqualStrings("Carol 41 sales {} 3.5", try root.call(.{ tv, "item", "0", "-values" }));
    try testing.expectEqualStrings("alice 30 ops ✔ {}", try root.call(.{ tv, "item", "1", "-values" }));
    // 数値の列は右寄せ
    try testing.expectEqualStrings("e", try root.call(.{ tv, "column", "age", "-anchor" }));
    try testing.expectEqualStrings("w", try root.call(.{ tv, "column", "name", "-anchor" }));
}

test "table sorts by clicking headings and keeps rows in display order" {
    const root = try initRoot();
    defer root.deinit();
    const table = try tk.Table(Person).init(testing.allocator, root, .{
        .columns = &.{ .{ .field = .name, .heading = "名前" }, .{ .field = .age, .heading = "年齢" }, .{ .field = .score } },
    });
    defer table.deinit();
    try table.setRows(&people);
    try testing.expectEqualStrings("name age score", try root.call(.{ table.treeview(), "cget", "-columns" }));

    // 見出しのクリック(=heading -command の実行)で昇順、もう一度で降順
    _ = try root.call(.{ "eval", try root.call(.{ table.treeview(), "heading", "age", "-command" }) });
    var got = try names(root, table);
    try testing.expectEqualStrings("Bob alice Carol", got);
    testing.allocator.free(got);
    try testing.expectEqualStrings("年齢 ▲", try root.call(.{ table.treeview(), "heading", "age", "-text" }));
    try testing.expectEqualStrings("Bob", table.get(0).name);

    _ = try root.call(.{ "eval", try root.call(.{ table.treeview(), "heading", "age", "-command" }) });
    got = try names(root, table);
    try testing.expectEqualStrings("Carol alice Bob", got);
    testing.allocator.free(got);
    try testing.expectEqualStrings("年齢 ▼", try root.call(.{ table.treeview(), "heading", "age", "-text" }));

    // 文字列は辞書順(大文字が先)、別の列に移ると前の列の印は消える。nullは最小
    try table.sortBy(.score, false);
    got = try names(root, table);
    try testing.expectEqualStrings("alice Carol Bob", got);
    testing.allocator.free(got);
    try testing.expectEqualStrings("年齢", try root.call(.{ table.treeview(), "heading", "age", "-text" }));

    // 追加・置き換え・削除
    _ = try table.append(.{ .name = "Dave", .age = 50, .role = .dev, .active = true });
    try table.set(0, .{ .name = "Alice", .age = 31, .role = .ops, .active = true });
    try table.remove(1);
    got = try names(root, table);
    try testing.expectEqualStrings("Alice Bob Dave", got);
    testing.allocator.free(got);
    try testing.expectEqual(3, table.len());

    try table.select(2);
    const sel = try table.selection(testing.allocator);
    defer testing.allocator.free(sel);
    try testing.expectEqualSlices(usize, &.{2}, sel);
}

const EditLog = struct {
    count: u32 = 0,
    last_row: usize = 0,
    last_field: tk.Table(Person).Field = .name,

    fn edited(self: *EditLog, row: usize, field: tk.Table(Person).Field) !void {
        self.count += 1;
        self.last_row = row;
        self.last_field = field;
    }
};

test "table edits cells through an editor and converts input to the field type" {
    const root = try initRoot();
    defer root.deinit();
    const T = tk.Table(Person);
    const table = try T.init(testing.allocator, root, .{
        .editable = true,
        .columns = &.{ .{ .field = .name }, .{ .field = .age }, .{ .field = .role }, .{ .field = .active }, .{ .field = .score, .editable = false } },
    });
    defer table.deinit();
    try table.setRows(&people);
    var log: EditLog = .{};
    table.onEdit(&log, EditLog.edited);
    // bboxは表示後でないと得られない
    try table.pack(.{});
    _ = try root.call(.{ "wm", "deiconify", "." });
    try root.w.interp.update();

    // 数値: 変換できない入力は確定せず、編集を続ける
    try table.beginEdit(0, .age);
    const editor = table.editing.?.editor;
    // Enter/Escape/フォーカス喪失で確定・取り消しする(キー入力自体はフォーカスの無いテストでは送れない)
    for ([_][]const u8{ "<Return>", "<KP_Enter>", "<Escape>", "<FocusOut>" }) |seq|
        try testing.expect((try root.call(.{ "bind", editor, seq })).len > 0);
    _ = try root.call(.{ editor, "delete", 0, "end" });
    _ = try root.call(.{ editor, "insert", 0, "abc" });
    try table.endEdit(true);
    try testing.expect(table.editing != null);
    try testing.expectEqual(0, log.count);
    _ = try root.call(.{ editor, "delete", 0, "end" });
    _ = try root.call(.{ editor, "insert", 0, " 42 " });
    try table.endEdit(true);
    try testing.expect(table.editing == null);
    try testing.expectEqual(42, table.get(0).age);
    try testing.expectEqualStrings("42", try root.call(.{ table.treeview(), "set", "0", "age" }));
    try testing.expectEqual(1, log.count);
    try testing.expectEqual(T.Field.age, log.last_field);
    try root.w.interp.update();
    try testing.expectEqualStrings("0", try root.call(.{ "winfo", "exists", editor }));

    // 文字列: Escapeで取り消し
    try table.beginEdit(1, .name);
    const name_editor = table.editing.?.editor;
    _ = try root.call(.{ name_editor, "insert", "end", "!!" });
    try table.endEdit(false);
    try testing.expectEqualStrings("alice", table.get(1).name);
    try table.beginEdit(1, .name);
    _ = try root.call(.{ table.editing.?.editor, "delete", 0, "end" });
    _ = try root.call(.{ table.editing.?.editor, "insert", 0, "Alice" });
    try table.endEdit(true);
    try testing.expectEqualStrings("Alice", table.get(1).name);

    // enum: 選択肢から選ぶComboboxになる
    try table.beginEdit(2, .role);
    const combo = table.editing.?.editor;
    try testing.expectEqualStrings("TCombobox", try root.call(.{ "winfo", "class", combo }));
    try testing.expectEqualStrings("dev ops sales", try root.call(.{ combo, "cget", "-values" }));
    _ = try root.call(.{ combo, "set", "ops" });
    _ = try root.call(.{ "event", "generate", combo, "<<ComboboxSelected>>" });
    try testing.expectEqual(Role.ops, table.get(2).role);

    // bool: その場で切り替わる
    try table.beginEdit(0, .active);
    try testing.expect(table.get(0).active);
    try testing.expect(table.editing == null);
    try testing.expectEqual(4, log.count);

    // ダブルクリック: 編集できない列では何も起きない
    const box = try root.call(.{ table.treeview(), "bbox", "0", "score" });
    var it = std.mem.tokenizeScalar(u8, box, ' ');
    const x = try std.fmt.parseInt(i32, it.next().?, 10) + 2;
    const y = try std.fmt.parseInt(i32, it.next().?, 10) + 2;
    try doubleClick(root, table.treeview(), x, y);
    try testing.expect(table.editing == null);
    const name_box = try root.call(.{ table.treeview(), "bbox", "0", "name" });
    it = std.mem.tokenizeScalar(u8, name_box, ' ');
    const nx = try std.fmt.parseInt(i32, it.next().?, 10) + 2;
    const ny = try std.fmt.parseInt(i32, it.next().?, 10) + 2;
    try doubleClick(root, table.treeview(), nx, ny);
    try testing.expectEqual(T.Field.name, table.editing.?.field);
}

/// Tkは <Double-1> を直接発生させられないため、短い間隔で2回クリックする。
fn doubleClick(root: tk.Tk, target: tk.ttk.Treeview, x: i32, y: i32) !void {
    for (0..2) |_| {
        _ = try root.call(.{ "event", "generate", target, "<ButtonPress-1>", "-x", x, "-y", y });
        _ = try root.call(.{ "event", "generate", target, "<ButtonRelease-1>", "-x", x, "-y", y });
    }
}
