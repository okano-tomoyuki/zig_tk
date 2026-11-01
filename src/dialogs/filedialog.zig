//! ファイル選択ダイアログ(Python tkinter.filedialog相当、tk_getOpenFile等のラッパー)。
//! masterはダイアログの親ウィンドウ(Tk/Toplevel等)。キャンセル時はnullを返す。
//! 戻り値の文字列は次のTcl呼び出しまで有効(保持する場合は複製すること)。
const std = @import("std");
const tcl = @import("../tcl.zig");
const value = @import("../value.zig");
const widget = @import("../widget.zig");
const interp_mod = @import("../interp.zig");
const Interp = interp_mod.Interp;
const Cmd = interp_mod.Cmd;
const Error = interp_mod.Error;

/// -filetypes の1項目。例: .{ .name = "Zig source", .patterns = &.{ ".zig", ".zon" } }
/// パターンは拡張子(".txt")または "*"。
pub const FileType = struct {
    name: []const u8,
    patterns: []const []const u8,

    pub fn toTclObj(self: FileType, interp: *Interp) Error!*tcl.Obj {
        return value.toObj(interp, .{ self.name, self.patterns });
    }
};

pub const OpenOptions = struct {
    title: ?[]const u8 = null,
    initialdir: ?[]const u8 = null,
    initialfile: ?[]const u8 = null,
    filetypes: ?[]const FileType = null,
};

pub const SaveOptions = struct {
    title: ?[]const u8 = null,
    initialdir: ?[]const u8 = null,
    initialfile: ?[]const u8 = null,
    filetypes: ?[]const FileType = null,
    /// 拡張子なしで入力された場合に付ける拡張子(例: ".txt")。
    defaultextension: ?[]const u8 = null,
    /// 既存ファイルを選んだ時に上書き確認するか(既定 true)。
    confirmoverwrite: ?bool = null,
};

pub const DirectoryOptions = struct {
    title: ?[]const u8 = null,
    initialdir: ?[]const u8 = null,
    /// 存在するディレクトリだけを選べるようにする。
    mustexist: ?bool = null,
};

fn run(master: anytype, command: []const u8, opts: anytype, extra: anytype) Error![]const u8 {
    const parent = widget.asWidget(master);
    var cmd: Cmd = .init(parent.interp);
    defer cmd.deinit();
    try cmd.add(command);
    try cmd.addOptions(parent.path, opts);
    try cmd.addOptions(parent.path, extra);
    try cmd.addOptions(parent.path, .{ .parent = parent });
    return cmd.eval();
}

fn nonEmpty(s: []const u8) ?[]const u8 {
    return if (s.len == 0) null else s;
}

/// 開くファイルを1つ選ばせる。
pub fn askopenfilename(master: anytype, opts: OpenOptions) Error!?[]const u8 {
    return nonEmpty(try run(master, "tk_getOpenFile", opts, .{}));
}

/// 開くファイルを複数選ばせる。戻り値はgpaで確保され、freeFilenamesで解放する。キャンセル時は空。
pub fn askopenfilenames(gpa: std.mem.Allocator, master: anytype, opts: OpenOptions) Error![][]u8 {
    _ = try run(master, "tk_getOpenFile", opts, .{ .multiple = true });
    return value.dupeStrings(gpa, try widget.asWidget(master).interp.resultList());
}

pub fn freeFilenames(gpa: std.mem.Allocator, files: [][]u8) void {
    value.freeStrings(gpa, files);
}

/// 保存先のファイル名を選ばせる。
pub fn asksaveasfilename(master: anytype, opts: SaveOptions) Error!?[]const u8 {
    return nonEmpty(try run(master, "tk_getSaveFile", opts, .{}));
}

/// ディレクトリを選ばせる。
pub fn askdirectory(master: anytype, opts: DirectoryOptions) Error!?[]const u8 {
    return nonEmpty(try run(master, "tk_chooseDirectory", opts, .{}));
}
