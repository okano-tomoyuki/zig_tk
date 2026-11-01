//! zig_tk をパッケージ依存として利用するアプリのビルド定義の例。
//!
//!     zig build               # zig-out/ にアプリとTcl/Tkランタイムをインストール
//!     zig build run           # インストール時と同じ配置で起動
//!     zig build -Dlinkage=static   # 実行ファイル1つにまとめる
const std = @import("std");
const zig_tk_build = @import("zig_tk");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const linkage = b.option(std.builtin.LinkMode, "linkage", "Tcl/Tkのリンク方式 (既定: dynamic)") orelse .dynamic;

    const zig_tk = b.dependency("zig_tk", .{
        .target = target,
        .optimize = optimize,
        .linkage = linkage,
    });

    const exe = b.addExecutable(.{
        .name = "consumer",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "zig_tk", .module = zig_tk.module("zig_tk") }},
        }),
    });

    const app = zig_tk_build.installApp(b, zig_tk, exe);
    app.run.addPassthruArgs();
    b.step("run", "アプリを起動する").dependOn(&app.run.step);
}
