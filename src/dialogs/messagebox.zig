//! メッセージボックス(Python tkinter.messagebox相当、tk_messageBoxのラッパー)。
//! masterはダイアログの親ウィンドウ(Tk/Toplevel等)。
const std = @import("std");
const widget = @import("../widget.zig");
const interp_mod = @import("../interp.zig");
const Cmd = interp_mod.Cmd;
const Error = interp_mod.Error;

pub const Icon = enum { info, warning, @"error", question };

/// ダイアログのボタン(=戻り値の種類)。
pub const Reply = enum { ok, cancel, yes, no, retry, abort, ignore };

pub const Options = struct {
    /// messageの下に小さく表示する補足説明。
    detail: ?[]const u8 = null,
    /// 既定のアイコンを置き換える。
    icon: ?Icon = null,
    /// Enterで選ばれるボタン。
    default: ?Reply = null,
};

const Kind = enum { ok, okcancel, yesno, yesnocancel, retrycancel, abortretryignore };

fn show(master: anytype, kind: Kind, icon: Icon, title: []const u8, message: []const u8, opts: Options) Error!Reply {
    const parent = widget.asWidget(master);
    var cmd: Cmd = .init(parent.interp);
    defer cmd.deinit();
    try cmd.add("tk_messageBox");
    try cmd.addOptions(parent.path, .{
        .@"type" = kind,
        .icon = opts.icon orelse icon,
        .title = title,
        .message = message,
        .detail = opts.detail,
        .default = opts.default,
        .parent = parent,
    });
    const result = try cmd.eval();
    return std.meta.stringToEnum(Reply, result) orelse error.TclError;
}

pub fn showinfo(master: anytype, title: []const u8, message: []const u8, opts: Options) Error!void {
    _ = try show(master, .ok, .info, title, message, opts);
}

pub fn showwarning(master: anytype, title: []const u8, message: []const u8, opts: Options) Error!void {
    _ = try show(master, .ok, .warning, title, message, opts);
}

pub fn showerror(master: anytype, title: []const u8, message: []const u8, opts: Options) Error!void {
    _ = try show(master, .ok, .@"error", title, message, opts);
}

/// 「はい/いいえ」を尋ね、押されたボタンを返す(Python askquestionは"yes"/"no"の文字列を返す)。
pub fn askquestion(master: anytype, title: []const u8, message: []const u8, opts: Options) Error!Reply {
    return show(master, .yesno, .question, title, message, opts);
}

/// OKならtrue。
pub fn askokcancel(master: anytype, title: []const u8, message: []const u8, opts: Options) Error!bool {
    return try show(master, .okcancel, .question, title, message, opts) == .ok;
}

/// はいならtrue。
pub fn askyesno(master: anytype, title: []const u8, message: []const u8, opts: Options) Error!bool {
    return try show(master, .yesno, .question, title, message, opts) == .yes;
}

/// はいならtrue、いいえならfalse、キャンセルならnull。
pub fn askyesnocancel(master: anytype, title: []const u8, message: []const u8, opts: Options) Error!?bool {
    return switch (try show(master, .yesnocancel, .question, title, message, opts)) {
        .yes => true,
        .no => false,
        else => null,
    };
}

/// 再試行ならtrue。
pub fn askretrycancel(master: anytype, title: []const u8, message: []const u8, opts: Options) Error!bool {
    return try show(master, .retrycancel, .warning, title, message, opts) == .retry;
}
