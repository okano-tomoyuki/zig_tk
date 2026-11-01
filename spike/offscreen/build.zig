//! 技術検証: Tk の画面を画面外に描いて画像と各Widgetの位置を取り出せるか(tk-designer のキャンバス用)。
//!
//!     zig build run -- <画面定義.json> <出力ディレクトリ>
const std = @import("std");
const zig_tk_build = @import("zig_tk");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const linkage = b.option(std.builtin.LinkMode, "linkage", "Tcl/Tkのリンク方式") orelse .dynamic;

    const zig_tk = b.dependency("zig_tk", .{ .target = target, .optimize = optimize, .linkage = linkage });
    const exe = b.addExecutable(.{
        .name = "tkrender",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{.{ .name = "zig_tk", .module = zig_tk.module("zig_tk") }},
        }),
    });
    switch (target.result.os.tag) {
        .windows => {
            exe.root_module.linkSystemLibrary("user32", .{});
            exe.root_module.linkSystemLibrary("gdi32", .{});
        },
        .linux => {
            exe.root_module.linkSystemLibrary("x11", .{});
            exe.root_module.linkSystemLibrary("xcomposite", .{});
        },
        else => {},
    }

    const app = zig_tk_build.installApp(b, zig_tk, exe);
    app.run.addPassthruArgs();
    b.step("run", "tkrender を実行する").dependOn(&app.run.step);
}
