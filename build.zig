//! zig_tk のビルド定義。
//!
//! ## ライブラリとして使う場合(利用側の build.zig)
//!
//!     const zig_tk = b.dependency("zig_tk", .{ .target = target, .optimize = optimize });
//!     exe.root_module.addImport("zig_tk", zig_tk.module("zig_tk"));
//!     const app = @import("zig_tk").installApp(b, zig_tk, exe);
//!     b.step("run", "Run the app").dependOn(&app.run.step);
//!
//! installApp は実行ファイルのインストールに加えて、Tcl/Tkのランタイム(共有ライブラリと
//! スクリプトのzip)の配置、Linuxでのrpath設定、静的リンク時のzip同梱を行う。
//! 依存のオプション: .linkage = .dynamic(既定) / .static、.@"tcl-source" = .vendored(既定) / .system
const std = @import("std");
const tcltk = @import("build/tcltk.zig");

const TclSource = enum {
    /// build.zig.zonのTcl/Tk 9.xソースからビルドする。ランタイムスクリプトはzipとして
    /// DLL(-Dlinkage=dynamic、既定)または実行ファイル(-Dlinkage=static)の末尾へ同梱する。
    vendored,
    /// ビルド済みTcl/Tk(MSYS2 MinGW64等)のDLLをリンクする。
    system,
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const tcl_source = b.option(TclSource, "tcl-source", "Tcl/Tkの入手方法 (既定: vendored)") orelse .vendored;

    const mod = b.addModule("zig_tk", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const build_options = b.addOptions();
    mod.addOptions("build_options", build_options);

    const examples = [_][]const u8{ "hello", "form", "dialogs", "listbox", "editor", "sketch", "explorer" };
    const test_step = b.step("test", "Run tests");
    const mod_tests = b.addTest(.{ .root_module = mod });
    const run_mod_tests = b.addRunArtifact(mod_tests);
    test_step.dependOn(&run_mod_tests.step);

    switch (tcl_source) {
        .vendored => {
            const tcl_dep = b.lazyDependency("tcl", .{}) orelse return;
            const tk_dep = b.lazyDependency("tk", .{}) orelse return;
            const linkage = b.option(std.builtin.LinkMode, "linkage", "vendored時のTcl/Tkのリンク方式 (既定: dynamic)") orelse .dynamic;
            const libs = tcltk.build(b, tcl_dep, tk_dep, .{ .target = target, .optimize = optimize, .linkage = linkage });
            build_options.addOption(u32, "tcl_major", 9);
            mod.linkLibrary(libs.tk);
            mod.linkLibrary(libs.tcl);
            if (libs.exe_resource) |rc| mod.addWin32ResourceFile(rc);

            // テスト実行ファイル(とそれが読み込むビルド直後のDLL)にはzipを同梱しないため、
            // ソースツリーのスクリプトを参照させる
            run_mod_tests.setEnvironmentVariable("TCL_LIBRARY", libs.tcl_library_path);
            run_mod_tests.setEnvironmentVariable("TK_LIBRARY", libs.tk_library_path);

            const bundler = b.addExecutable(.{
                .name = "bundle",
                .root_module = b.createModule(.{
                    .root_source_file = b.path("tools/bundle.zig"),
                    .target = b.graph.host,
                    .optimize = .safe,
                }),
            });
            const runtime: Runtime = switch (linkage) {
                .dynamic => .{ .shared = .{
                    .tcl = bundle(b, bundler.getEmittedBin(), libs.tcl.getEmittedBin(), libs.names.tcl_file, &.{tclArchive(libs)}),
                    .tk = bundle(b, bundler.getEmittedBin(), libs.tk.getEmittedBin(), libs.names.tk_file, &.{tkArchive(libs)}),
                } },
                .static => .{ .static = .{
                    .bundler = bundler.getEmittedBin(),
                    .tcl_library = libs.tcl_library,
                    .tk_library = libs.tk_library,
                } },
            };
            runtime.publish(b);
            for (examples) |name| addExample(b, runtime, name, mod, target, optimize);
        },
        .system => {
            build_options.addOption(u32, "tcl_major", 8);
            const install_runtime = linkSystemTclTk(b, mod, target);
            run_mod_tests.step.dependOn(install_runtime);
            for (examples) |name| addExample(b, .system, name, mod, target, optimize);
        },
    }
}

// ---------------------------------------------------------------------------
// 利用側から呼ぶ公開API
// ---------------------------------------------------------------------------

pub const App = struct {
    /// インストール時と同じ相対配置(実行ファイル + Tcl/Tkランタイム)で起動するRunステップ。
    /// 引数は run.addArgs / addPassthruArgs で追加できる。
    run: *std.Build.Step.Run,
};

/// zig_tk を使う実行ファイル exe を、配布に必要なTcl/Tkランタイムと共にインストールする。
/// zig_tk は b.dependency("zig_tk", ...) の戻り値。
pub fn installApp(b: *std.Build, zig_tk: *std.Build.Dependency, exe: *std.Build.Step.Compile) App {
    return installAppWith(b, Runtime.fromDependency(zig_tk), exe);
}

// ---------------------------------------------------------------------------

/// 実行ファイルの配布に必要なTcl/Tkランタイム。依存パッケージ側でビルドし、
/// 名前付きLazyPathとして利用側へ受け渡す(publish / fromDependency)。
const Runtime = union(enum) {
    /// 共有ライブラリ(末尾にスクリプトのzip)を実行ファイルと一緒に配置する。
    shared: struct {
        tcl: std.Build.LazyPath,
        tk: std.Build.LazyPath,
    },
    /// 実行ファイル自体の末尾にスクリプトのzipを付ける。
    static: struct {
        bundler: std.Build.LazyPath,
        tcl_library: std.Build.LazyPath,
        tk_library: std.Build.LazyPath,
    },
    /// ビルド済みTcl/Tk(-Dtcl-source=system)。実行ファイルのみをインストールする(開発用)。
    system,

    const prefix = "zig_tk/";

    fn publish(self: Runtime, b: *std.Build) void {
        switch (self) {
            .shared => |s| {
                b.addNamedLazyPath(prefix ++ "tcl_shared", s.tcl);
                b.addNamedLazyPath(prefix ++ "tk_shared", s.tk);
            },
            .static => |s| {
                b.addNamedLazyPath(prefix ++ "bundler", s.bundler);
                b.addNamedLazyPath(prefix ++ "tcl_library", s.tcl_library);
                b.addNamedLazyPath(prefix ++ "tk_library", s.tk_library);
            },
            .system => {},
        }
    }

    fn fromDependency(dep: *std.Build.Dependency) Runtime {
        const paths = dep.builder.named_lazy_paths;
        if (paths.get(prefix ++ "tcl_shared")) |tcl| {
            return .{ .shared = .{ .tcl = tcl, .tk = paths.get(prefix ++ "tk_shared").? } };
        }
        if (paths.get(prefix ++ "bundler")) |bundler| {
            return .{ .static = .{
                .bundler = bundler,
                .tcl_library = paths.get(prefix ++ "tcl_library").?,
                .tk_library = paths.get(prefix ++ "tk_library").?,
            } };
        }
        return .system;
    }
};

fn installAppWith(b: *std.Build, runtime: Runtime, exe: *std.Build.Step.Compile) App {
    const target = exe.rootModuleTarget();
    const windows = target.os.tag == .windows;
    const exe_name = b.fmt("{s}{s}", .{ exe.name, target.exeFileExt() });
    const exe_path = b.fmt("bin/{s}", .{exe_name});

    switch (runtime) {
        // 配布物(各共有ライブラリの末尾にスクリプトのzip):
        //   Windows: bin/<app>.exe, bin/tcl90.dll, bin/tcl9tk90.dll
        //   Linux:   bin/<app>, lib/libtcl9.0.so, lib/libtcl9tk9.0.so (rpath: $ORIGIN/../lib)
        .shared => |s| {
            if (!windows) exe.root_module.addRPathSpecial("$ORIGIN/../lib");
            b.getInstallStep().dependOn(&b.addInstallArtifact(exe, .{}).step);
            const lib_dir: []const u8 = if (windows) "bin" else "lib";
            const names = tcltk.LibNames.of(.fromOs(target.os.tag));
            const files = [_]Placed{
                .{ .sub_path = exe_path, .file = exe.getEmittedBin() },
                install(b, s.tcl, lib_dir, names.tcl_file),
                install(b, s.tk, lib_dir, names.tk_file),
            };
            return .{ .run = runFromLayout(b, exe.name, &files) };
        },
        // 配布物: bin/<app>(.exe) のみ(実行ファイルの末尾にTcl/Tk両方のスクリプトのzip)
        .static => |s| {
            const bundled = bundle(b, s.bundler, exe.getEmittedBin(), exe_name, &.{
                .{ .prefix = "tcl_library", .dir = s.tcl_library },
                .{ .prefix = "tk_library", .dir = s.tk_library, .exclude = "tk_library/demos" },
            });
            const files = [_]Placed{install(b, bundled, "bin", exe_name)};
            return .{ .run = runFromLayout(b, exe.name, &files) };
        },
        .system => {
            b.getInstallStep().dependOn(&b.addInstallArtifact(exe, .{}).step);
            const run = b.addRunArtifact(exe);
            run.step.dependOn(b.getInstallStep());
            return .{ .run = run };
        },
    }
}

const Archive = struct {
    /// zip内のトップレベルディレクトリ名(tcl_library / tk_library)。
    prefix: []const u8,
    dir: std.Build.LazyPath,
    exclude: ?[]const u8 = null,
};

fn tclArchive(libs: tcltk.TclTk) Archive {
    return .{ .prefix = "tcl_library", .dir = libs.tcl_library };
}

fn tkArchive(libs: tcltk.TclTk) Archive {
    return .{ .prefix = "tk_library", .dir = libs.tk_library, .exclude = "tk_library/demos" };
}

/// inputの末尾にarchivesのzipを連結したファイルを生成する(tools/bundle.zig)。
fn bundle(
    b: *std.Build,
    bundler: std.Build.LazyPath,
    input: std.Build.LazyPath,
    out_name: []const u8,
    archives: []const Archive,
) std.Build.LazyPath {
    const run = b.addRunFile(bundler);
    run.addFileArg(input);
    const out = run.addOutputFileArg(out_name);
    for (archives) |a| {
        run.addPrefixedDirectoryArg(b.fmt("{s}=", .{a.prefix}), a.dir);
        if (a.exclude) |x| run.addArg(b.fmt("--exclude={s}", .{x}));
    }
    return out;
}

/// インストール先(プレフィックスからの相対パス)と、その元になるファイル。
const Placed = struct {
    sub_path: []const u8,
    file: std.Build.LazyPath,
};

fn install(b: *std.Build, file: std.Build.LazyPath, dir: []const u8, name: []const u8) Placed {
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(file, .{ .custom = dir }, name).step);
    return .{ .sub_path = b.fmt("{s}/{s}", .{ dir, name }), .file = file };
}

/// files(先頭が実行ファイル)をインストール時と同じ相対配置でまとめ、実行ファイルを起動する。
fn runFromLayout(b: *std.Build, name: []const u8, files: []const Placed) *std.Build.Step.Run {
    const dir = b.addWriteFiles();
    const exe_copy = dir.addCopyFile(files[0].file, files[0].sub_path);
    for (files[1..]) |f| _ = dir.addCopyFile(f.file, f.sub_path);
    const run = std.Build.Step.Run.create(b, b.fmt("run {s}", .{name}));
    run.addFileArg(exe_copy);
    return run;
}

/// examples/<name>.zig をビルドし、利用側と同じ installAppWith でインストールして run-<name> を定義する。
fn addExample(
    b: *std.Build,
    runtime: Runtime,
    name: []const u8,
    mod: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) void {
    const exe = b.addExecutable(.{
        .name = name,
        .root_module = b.createModule(.{
            .root_source_file = b.path(b.fmt("examples/{s}.zig", .{name})),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "zig_tk", .module = mod }},
        }),
    });
    const app = installAppWith(b, runtime, exe);
    app.run.addPassthruArgs();
    b.step(b.fmt("run-{s}", .{name}), b.fmt("examples/{s}.zig を実行する", .{name})).dependOn(&app.run.step);
}

/// ビルド済みTcl/Tk 8.6(MSYS2 MinGW64等)をリンクし、DLLとランタイムスクリプトを zig-out/ へ配置する。
fn linkSystemTclTk(b: *std.Build, mod: *std.Build.Module, target: std.Build.ResolvedTarget) *std.Build.Step {
    const tcl_prefix = b.option(
        []const u8,
        "tcl-prefix",
        "Tcl/Tkのインストール先 (lib/, bin/, lib/tcl8.6 等を含むディレクトリ)",
    ) orelse "C:/tool/msys64/mingw64";
    const tcl_version = b.option([]const u8, "tcl-version", "Tcl/Tkのバージョン (例: 8.6)") orelse "8.6";
    const tcl_ver_nodot = std.mem.replaceOwned(u8, b.allocator, tcl_version, ".", "") catch @panic("OOM");

    // ZigのlinkSystemLibraryはMinGWのインポートライブラリ(lib*.dll.a)を探索しないため直接渡す。
    for ([_][]const u8{ "tcl", "tk" }) |name| {
        const import_lib = b.fmt("lib{s}{s}.dll.a", .{ name, tcl_ver_nodot });
        mod.addObjectFile(.{ .cwd_relative = b.pathJoin(&.{ tcl_prefix, "lib", import_lib }) });
    }

    // Tclは <exe>/../lib/tcl<ver> を標準で探索するため bin/ と lib/ に分けて置く。
    const install_runtime = b.step("runtime", "Tcl/TkのDLLとランタイムスクリプトを zig-out/ にコピーする");
    if (target.result.os.tag == .windows) {
        const dlls = [_][]const u8{
            b.fmt("tcl{s}.dll", .{tcl_ver_nodot}),
            b.fmt("tk{s}.dll", .{tcl_ver_nodot}),
            "zlib1.dll",
        };
        for (dlls) |dll| {
            const src: std.Build.LazyPath = .{ .cwd_relative = b.pathJoin(&.{ tcl_prefix, "bin", dll }) };
            install_runtime.dependOn(&b.addInstallBinFile(src, dll).step);
        }
    }
    for ([_][]const u8{ "tcl", "tk" }) |name| {
        const dir = b.fmt("{s}{s}", .{ name, tcl_version });
        install_runtime.dependOn(&b.addInstallDirectory(.{
            .source_dir = .{ .cwd_relative = b.pathJoin(&.{ tcl_prefix, "lib", dir }) },
            .install_dir = .lib,
            .install_subdir = dir,
        }).step);
    }
    b.getInstallStep().dependOn(install_runtime);
    return install_runtime;
}
