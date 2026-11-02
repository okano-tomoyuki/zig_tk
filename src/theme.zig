//! 同梱のttkテーマ。
//!
//!     try root.setTheme(.sun_valley_dark);
//!
//! Sun Valley(https://github.com/rdbende/Sun-Valley-ttk-theme、MIT License)のスクリプトと画像を
//! 実行ファイルに埋め込んで使う。テーマを使うアプリを配布する場合は、`sun_valley_license` の
//! 文面を配布物(ライセンス表示の画面や文書)に含めること。
const std = @import("std");
const sv = @import("sun_valley");
const interp_mod = @import("interp.zig");
const Interp = interp_mod.Interp;
const Error = interp_mod.Error;
const PhotoData = @import("image.zig").PhotoImage.Data;

pub const Theme = enum {
    sun_valley_light,
    sun_valley_dark,

    /// ttk::style theme use に渡す名前。
    pub fn tclName(self: Theme) []const u8 {
        return switch (self) {
            .sun_valley_light => "sun-valley-light",
            .sun_valley_dark => "sun-valley-dark",
        };
    }
};

/// Sun Valley の MIT License の文面。
pub const sun_valley_license: []const u8 = sv.license;

/// themeをttkのテーマにする。初回にテーマを読み込む。classic Widgetの配色(tk_setPalette)も切り替わる。
pub fn use(interp: *Interp, theme: Theme) Error!void {
    const names = try interp.call(.{ "ttk::style", "theme", "names" });
    if (std.mem.indexOf(u8, names, "sun-valley-light") == null) try loadSunValley(interp);
    _ = try interp.call(.{ "ttk::style", "theme", "use", theme.tclName() });
    // sv.tclは <<ThemeChanged>> で配色を切り替えるが、ルートが表示される前(mainloop前に設定する
    // よくある使い方)には届かないため直接呼ぶ(何度呼んでも同じ結果になる)。
    _ = try interp.call(.{"configure_colors"});
}

/// sv.tclと各テーマのスクリプトは、同じディレクトリのファイルを source / image create -file で読む。
/// 埋め込んだ内容から読めるよう、その部分だけを置き換えて評価する。
fn loadSunValley(interp: *Interp) Error!void {
    inline for (.{ .{ "light", sv.sprites_light, sv.light, sv.spritesheet_light }, .{ "dark", sv.sprites_dark, sv.dark, sv.spritesheet_dark } }) |t| {
        try evalPatched(interp, t[1], &.{});
        _ = try interp.call(.{ "set", "::zt_sv_spritesheet", PhotoData{ .bytes = t[3] } });
        try evalPatched(interp, t[2], &.{
            .{ "source [file join [file dirname [info script]] sprites_" ++ t[0] ++ ".tcl]", "" },
            .{ "-file $imgfile", "-data $imgfile" },
            .{ "[file join [file dirname [info script]] spritesheet_" ++ t[0] ++ ".png]", "$::zt_sv_spritesheet" },
        });
    }
    _ = try interp.call(.{ "unset", "::zt_sv_spritesheet" });
    try evalPatched(interp, sv.sv, &.{
        .{ "source [file join [file dirname [info script]] theme light.tcl]", "" },
        .{ "source [file join [file dirname [info script]] theme dark.tcl]", "" },
    });
}

fn evalPatched(interp: *Interp, script: []const u8, replacements: []const [2][]const u8) Error!void {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(interp.gpa);
    try buf.appendSlice(interp.gpa, script);
    for (replacements) |r| {
        const at = std.mem.indexOf(u8, buf.items, r[0]) orelse return interp.failWith("zig_tk: unexpected Sun Valley theme script");
        try buf.replaceRange(interp.gpa, at, r[0].len, r[1]);
    }
    if (std.mem.indexOf(u8, buf.items, "info script") != null) return interp.failWith("zig_tk: unexpected Sun Valley theme script");
    _ = try interp.call(.{ "uplevel", "#0", buf.items });
}
