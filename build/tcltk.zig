//! Tcl/Tk 9.x をソースから共有ライブラリ(既定)または静的ライブラリとしてビルドする。
//! 対応ターゲット: Windows(MinGW)、Linux(X11)。
//! ファイル一覧とマクロ定義は各ソースの win/Makefile.in・unix/Makefile.in と、
//! MSYS2版tclConfig.sh / unix/configure(Ubuntu 24.04)が生成するDEFSに準拠している。
const std = @import("std");

pub const Options = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    linkage: std.builtin.LinkMode,
};

pub const Platform = enum {
    windows,
    linux,

    pub fn of(target: std.Build.ResolvedTarget) Platform {
        return fromOs(target.result.os.tag);
    }

    pub fn fromOs(os: std.Target.Os.Tag) Platform {
        return switch (os) {
            .windows => .windows,
            .linux => .linux,
            else => |tag| std.debug.panic("zig_tk: Tcl/Tk source build does not support {t} yet", .{tag}),
        };
    }
};

/// 共有ライブラリ名(Tcl/Tk公式の命名に合わせる)。addLibraryのnameと実ファイル名。
pub const LibNames = struct {
    tcl: []const u8,
    tk: []const u8,
    tcl_file: []const u8,
    tk_file: []const u8,

    pub fn of(platform: Platform) LibNames {
        return switch (platform) {
            .windows => .{ .tcl = "tcl90", .tk = "tcl9tk90", .tcl_file = "tcl90.dll", .tk_file = "tcl9tk90.dll" },
            .linux => .{ .tcl = "tcl9.0", .tk = "tcl9tk9.0", .tcl_file = "libtcl9.0.so", .tk_file = "libtcl9tk9.0.so" },
        };
    }
};

// ---------------------------------------------------------------------------
// マクロ定義
// ---------------------------------------------------------------------------

const win_common_defs = [_][]const u8{
    "-DTCL_THREADS=1",
    "-DUSE_THREAD_ALLOC=1",
    "-DMODULE_SCOPE=extern",
    "-DTCL_CFG_DO64BIT=1",
    "-DHAVE_NO_SEH=1",
    "-DHAVE_CAST_TO_UNION=1",
    "-DHAVE_INTPTR_T=1",
    "-DHAVE_UINTPTR_T=1",
    "-DHAVE_STDINT_H=1",
    "-DHAVE_INTTYPES_H=1",
    "-D__USE_MINGW_ANSI_STDIO=0",
};

/// unix/configure(Tcl 9.0.4, Ubuntu 24.04 x86_64)のAC_FLAGSのうちTcl/Tk共通の部分。
const linux_common_defs = [_][]const u8{
    "-DHAVE_STDIO_H=1",           "-DHAVE_STDLIB_H=1",          "-DHAVE_STRING_H=1",
    "-DHAVE_INTTYPES_H=1",        "-DHAVE_STDINT_H=1",          "-DHAVE_STRINGS_H=1",
    "-DHAVE_SYS_STAT_H=1",        "-DHAVE_SYS_TYPES_H=1",       "-DHAVE_UNISTD_H=1",
    "-DHAVE_SYS_TIME_H=1",        "-DSTDC_HEADERS=1",           "-DTCL_CFGVAL_ENCODING=\"utf-8\"",
    "-DMODULE_SCOPE=extern __attribute__((__visibility__(\"hidden\")))",
    "-DHAVE_HIDDEN=1",            "-DTCL_CFG_DO64BIT=1",        "-DHAVE_CAST_TO_UNION=1",
    "-DHAVE_VFORK=1",             "-DHAVE_POSIX_SPAWNP=1",      "-DHAVE_POSIX_SPAWN_FILE_ACTIONS_ADDDUP2=1",
    "-DHAVE_POSIX_SPAWNATTR_SETFLAGS=1",
    "-DTCL_SHLIB_EXT=\".so\"",    "-D_LARGEFILE64_SOURCE=1",    "-DTCL_WIDE_INT_IS_LONG=1",
    "-DHAVE_INTPTR_T=1",          "-DHAVE_UINTPTR_T=1",         "-D_REENTRANT=1",
    "-D_THREAD_SAFE=1",
};

const linux_tcl_defs = [_][]const u8{
    "-DHAVE_SYS_PARAM_H=1",           "-DHAVE_PTHREAD_ATTR_SETSTACKSIZE=1", "-DHAVE_PTHREAD_ATFORK=1",
    "-DHAVE_GETCWD=1",                "-DHAVE_MKSTEMP=1",                   "-DHAVE_WAITPID=1",
    "-DHAVE_GETNAMEINFO=1",           "-DHAVE_GETADDRINFO=1",               "-DHAVE_FREEADDRINFO=1",
    "-DHAVE_GAI_STRERROR=1",          "-DHAVE_STRUCT_ADDRINFO=1",           "-DHAVE_STRUCT_IN6_ADDR=1",
    "-DHAVE_STRUCT_SOCKADDR_IN6=1",   "-DHAVE_STRUCT_SOCKADDR_STORAGE=1",   "-DHAVE_GETPWUID_R_5=1",
    "-DHAVE_GETPWUID_R=1",            "-DHAVE_GETPWNAM_R_5=1",              "-DHAVE_GETPWNAM_R=1",
    "-DHAVE_GETGRGID_R_5=1",          "-DHAVE_GETGRGID_R=1",                "-DHAVE_GETGRNAM_R_5=1",
    "-DHAVE_GETGRNAM_R=1",            "-DHAVE_DECL_GETHOSTBYNAME_R=1",      "-DHAVE_GETHOSTBYNAME_R_6=1",
    "-DHAVE_GETHOSTBYNAME_R=1",       "-DHAVE_DECL_GETHOSTBYADDR_R=1",      "-DHAVE_GETHOSTBYADDR_R_8=1",
    "-DHAVE_GETHOSTBYADDR_R=1",       "-DHAVE_TERMIOS_H=1",                 "-DHAVE_SYS_IOCTL_H=1",
    "-DHAVE_PSELECT=1",               "-DHAVE_SYS_EPOLL_H=1",               "-DNOTIFIER_EPOLL=1",
    "-DHAVE_SYS_EVENTFD_H=1",         "-DHAVE_EVENTFD=1",                   "-DHAVE_GMTIME_R=1",
    "-DHAVE_LOCALTIME_R=1",           "-DHAVE_TM_GMTOFF=1",                 "-DHAVE_TIMEZONE_VAR=1",
    "-DHAVE_STRUCT_STAT_ST_BLOCKS=1", "-DHAVE_STRUCT_STAT_ST_BLKSIZE=1",    "-DHAVE_STRUCT_STAT_ST_RDEV=1",
    "-DHAVE_BLKCNT_T=1",              "-DNO_UNION_WAIT=1",                  "-DHAVE_SIGNED_CHAR=1",
    "-DHAVE_LANGINFO=1",              "-DHAVE_CFMAKERAW=1",                 "-DHAVE_MKSTEMPS=1",
    "-DHAVE_FTS=1",                   "-DTCL_UNLOAD_DLLS=1",                "-DHAVE_CPUID=1",
    "-DHAVE_ZLIB=1",
};

fn tclDefs(platform: Platform) []const []const u8 {
    const shared = [_][]const u8{ "-DZIPFS_BUILD=1", "-DMP_PREC=4", "-DMP_FIXED_CUTOFFS", "-w" };
    return switch (platform) {
        .windows => &(win_common_defs ++ shared ++ [_][]const u8{
            "-DHAVE_ZLIB=1",
            "-DTCL_WITH_INTERNAL_ZLIB=1",
            "-DHAVE_INTRIN_H=1",
            "-DHAVE_CPUID_H=1",
            "-DHAVE_WSPIAPI_H=1",
            "-DTCL_CFGVAL_ENCODING=\"utf-8\"",
        }),
        .linux => &(linux_common_defs ++ shared ++ linux_tcl_defs),
    };
}

fn tkDefs(platform: Platform) []const []const u8 {
    const shared = [_][]const u8{ "-DBUILD_tk", "-DBUILD_ttk", "-DZIPFS_BUILD=1", "-w" };
    return switch (platform) {
        .windows => &(win_common_defs ++ shared ++ [_][]const u8{
            "-DTCL_UTF_MAX=4",
            "-DHAVE_UXTHEME_H=1",
            "-DHAVE_VSSYM32_H=1",
        }),
        .linux => &(linux_common_defs ++ shared ++ [_][]const u8{
            "-DHAVE_PW_GECOS=1",
            "-DHAVE_LIBXFT=1",
            "-DHAVE_XFT=1",
            "-DHAVE_XSS=1",
        }),
    };
}

/// tclPkgConfig.c/tkPkgConfig.c等が埋め込むインストール先情報。ランタイムスクリプトはzipfs経由で
/// 見つけるためパスは固定値でよいが、dllfile,runtime はTkが自身の共有ライブラリに付いたzip
/// (tk_library)を探す際に使う(auto.tclのtcl_findLibrary)ため、実際のファイル名にする必要がある。
fn pkgConfigDefs(b: *std.Build, lib_file: []const u8) []const []const u8 {
    return b.allocator.dupe([]const u8, &.{
        "-DCFG_INSTALL_LIBDIR=\"//zipfs:/lib\"",
        "-DCFG_INSTALL_BINDIR=\"//zipfs:/lib\"",
        "-DCFG_INSTALL_SCRDIR=\"//zipfs:/lib\"",
        "-DCFG_INSTALL_INCDIR=\"//zipfs:/lib\"",
        "-DCFG_INSTALL_DOCDIR=\"//zipfs:/lib\"",
        "-DCFG_RUNTIME_LIBDIR=\"//zipfs:/lib\"",
        "-DCFG_RUNTIME_BINDIR=\"//zipfs:/lib\"",
        "-DCFG_RUNTIME_SCRDIR=\"//zipfs:/lib\"",
        "-DCFG_RUNTIME_INCDIR=\"//zipfs:/lib\"",
        "-DCFG_RUNTIME_DOCDIR=\"//zipfs:/lib\"",
        b.fmt("-DCFG_RUNTIME_DLLFILE=\"{s}\"", .{lib_file}),
    }) catch @panic("OOM");
}

// ---------------------------------------------------------------------------
// ソースファイル一覧
// ---------------------------------------------------------------------------

const tcl_generic = [_][]const u8{
    "regcomp.c",             "regexec.c",        "regfree.c",          "regerror.c",
    "tclAlloc.c",            "tclArithSeries.c", "tclAssembly.c",      "tclAsync.c",
    "tclBasic.c",            "tclBinary.c",      "tclCkalloc.c",       "tclClock.c",
    "tclClockFmt.c",         "tclCmdAH.c",       "tclCmdIL.c",         "tclCmdMZ.c",
    "tclCompCmds.c",         "tclCompCmdsGR.c",  "tclCompCmdsSZ.c",    "tclCompExpr.c",
    "tclCompile.c",          "tclConfig.c",      "tclDate.c",          "tclDictObj.c",
    "tclDisassemble.c",      "tclEncoding.c",    "tclEnsemble.c",      "tclEnv.c",
    "tclEvent.c",            "tclExecute.c",     "tclFCmd.c",          "tclFileName.c",
    "tclGet.c",              "tclHash.c",        "tclHistory.c",       "tclIcu.c",
    "tclIndexObj.c",         "tclInterp.c",      "tclIO.c",            "tclIOCmd.c",
    "tclIOGT.c",             "tclIORChan.c",     "tclIORTrans.c",      "tclIOSock.c",
    "tclIOUtil.c",           "tclLink.c",        "tclLiteral.c",       "tclListObj.c",
    "tclLoad.c",             "tclMain.c",        "tclNamesp.c",        "tclNotify.c",
    "tclOO.c",               "tclOOBasic.c",     "tclOOCall.c",        "tclOODefineCmds.c",
    "tclOOInfo.c",           "tclOOMethod.c",    "tclOOProp.c",        "tclOOStubInit.c",
    "tclObj.c",              "tclOptimize.c",    "tclPanic.c",         "tclParse.c",
    "tclPathObj.c",          "tclPipe.c",        "tclPkg.c",           "tclPosixStr.c",
    "tclPreserve.c",         "tclProc.c",        "tclProcess.c",       "tclRegexp.c",
    "tclResolve.c",          "tclResult.c",      "tclScan.c",          "tclStringObj.c",
    "tclStrIdxTree.c",       "tclStrToD.c",      "tclStubInit.c",      "tclThread.c",
    "tclThreadAlloc.c",      "tclThreadJoin.c",  "tclThreadStorage.c", "tclTimer.c",
    "tclTomMathInterface.c", "tclTrace.c",       "tclUtf.c",           "tclUtil.c",
    "tclVar.c",              "tclZlib.c",
};

const tcl_win = [_][]const u8{
    "tclWin32Dll.c", "tclWinChan.c",   "tclWinConsole.c", "tclWinSerial.c",
    "tclWinError.c", "tclWinFCmd.c",   "tclWinFile.c",    "tclWinInit.c",
    "tclWinLoad.c",  "tclWinNotify.c", "tclWinPipe.c",    "tclWinSock.c",
    "tclWinThrd.c",  "tclWinTime.c",   "tclWinPanic.c",
};

/// tclUnixFile.c / tclUnixInit.c は個別のマクロが必要なため別途追加する。
/// 通知機構の3ファイルはNOTIFIER_*マクロで有効なもの(Linuxではepoll)だけが中身を持つ。
const tcl_unix = [_][]const u8{
    "tclUnixChan.c",   "tclUnixEvent.c",    "tclUnixFCmd.c",     "tclUnixPipe.c",
    "tclUnixSock.c",   "tclUnixTime.c",     "tclUnixThrd.c",     "tclUnixCompat.c",
    "tclEpollNotfy.c", "tclKqueueNotfy.c",  "tclSelectNotfy.c",  "tclLoadDl.c",
};

const tommath = [_][]const u8{
    "bn_mp_add.c",             "bn_mp_add_d.c",       "bn_mp_and.c",             "bn_mp_clamp.c",
    "bn_mp_clear.c",           "bn_mp_clear_multi.c", "bn_mp_cmp.c",             "bn_mp_cmp_d.c",
    "bn_mp_cmp_mag.c",         "bn_mp_cnt_lsb.c",     "bn_mp_copy.c",            "bn_mp_count_bits.c",
    "bn_mp_div.c",             "bn_mp_div_d.c",       "bn_mp_div_2.c",           "bn_mp_div_2d.c",
    "bn_s_mp_div_3.c",         "bn_mp_exch.c",        "bn_mp_expt_n.c",          "bn_mp_get_mag_u64.c",
    "bn_mp_grow.c",            "bn_mp_init.c",        "bn_mp_init_copy.c",       "bn_mp_init_i64.c",
    "bn_mp_init_multi.c",      "bn_mp_init_set.c",    "bn_mp_init_size.c",       "bn_mp_init_u64.c",
    "bn_mp_lshd.c",            "bn_mp_mod.c",         "bn_mp_mod_2d.c",          "bn_mp_mul.c",
    "bn_mp_mul_2.c",           "bn_mp_mul_2d.c",      "bn_mp_mul_d.c",           "bn_mp_neg.c",
    "bn_mp_or.c",              "bn_mp_pack.c",        "bn_mp_pack_count.c",      "bn_mp_radix_size.c",
    "bn_mp_radix_smap.c",      "bn_mp_read_radix.c",  "bn_mp_rshd.c",            "bn_mp_set_i64.c",
    "bn_mp_set_u64.c",         "bn_mp_shrink.c",      "bn_mp_sqr.c",             "bn_mp_sqrt.c",
    "bn_mp_sub.c",             "bn_mp_sub_d.c",       "bn_mp_signed_rsh.c",      "bn_mp_to_ubin.c",
    "bn_mp_to_radix.c",        "bn_mp_ubin_size.c",   "bn_mp_unpack.c",          "bn_mp_xor.c",
    "bn_mp_zero.c",            "bn_s_mp_add.c",       "bn_s_mp_balance_mul.c",   "bn_s_mp_karatsuba_mul.c",
    "bn_s_mp_karatsuba_sqr.c", "bn_s_mp_mul_digs.c",  "bn_s_mp_mul_digs_fast.c", "bn_s_mp_reverse.c",
    "bn_s_mp_sqr_fast.c",      "bn_s_mp_sqr.c",       "bn_s_mp_sub.c",           "bn_s_mp_toom_mul.c",
    "bn_s_mp_toom_sqr.c",
};

/// Windowsでは同梱のzlibを使う(Linuxではconfigure同様にシステムのlibzを使う)。
const zlib = [_][]const u8{
    "adler32.c", "compress.c", "crc32.c", "deflate.c", "infback.c", "inffast.c",
    "inflate.c", "inftrees.c", "trees.c", "uncompr.c", "zutil.c",
};

const tk_generic = [_][]const u8{
    "tk3d.c",          "tkArgv.c",       "tkAtom.c",       "tkBind.c",          "tkBitmap.c",
    "tkBusy.c",        "tkButton.c",     "tkCanvArc.c",    "tkCanvBmap.c",      "tkCanvImg.c",
    "tkCanvLine.c",    "tkCanvPoly.c",   "tkCanvPs.c",     "tkCanvText.c",      "tkCanvUtil.c",
    "tkCanvWind.c",    "tkCanvas.c",     "tkClipboard.c",  "tkCmds.c",          "tkColor.c",
    "tkConfig.c",      "tkConsole.c",    "tkCursor.c",     "tkEntry.c",         "tkError.c",
    "tkEvent.c",       "tkFocus.c",      "tkFont.c",       "tkFrame.c",         "tkGC.c",
    "tkGeometry.c",    "tkGet.c",        "tkGrab.c",       "tkGrid.c",          "tkIcu.c",
    "tkImage.c",       "tkImgBmap.c",    "tkImgListFormat.c", "tkImgGIF.c",     "tkImgPNG.c",
    "tkImgPPM.c",      "tkImgSVGnano.c", "tkImgPhoto.c",   "tkImgPhInstance.c", "tkListbox.c",
    "tkMain.c",        "tkMenu.c",       "tkMenubutton.c", "tkMenuDraw.c",      "tkMessage.c",
    "tkPanedWindow.c", "tkObj.c",        "tkOldConfig.c",  "tkOption.c",        "tkPack.c",
    "tkPlace.c",       "tkRectOval.c",   "tkScale.c",      "tkScrollbar.c",     "tkSelect.c",
    "tkStyle.c",       "tkText.c",       "tkTextBTree.c",  "tkTextDisp.c",      "tkTextImage.c",
    "tkTextIndex.c",   "tkTextMark.c",   "tkTextTag.c",    "tkTextWind.c",      "tkTrig.c",
    "tkUndo.c",        "tkUtil.c",       "tkVisual.c",     "tkStubInit.c",      "tkWindow.c",
};

/// generic/配下だがWindows(とmacOS)でのみ使われるもの。
const tk_generic_win = [_][]const u8{ "tkFileFilter.c", "tkImgUtil.c", "tkMacWinMenu.c", "tkPointer.c" };

const ttk_generic = [_][]const u8{
    "ttkBlink.c",        "ttkButton.c",   "ttkCache.c",    "ttkClamTheme.c", "ttkClassicTheme.c",
    "ttkDefaultTheme.c", "ttkElements.c", "ttkEntry.c",    "ttkFrame.c",     "ttkImage.c",
    "ttkInit.c",         "ttkLabel.c",    "ttkLayout.c",   "ttkManager.c",   "ttkNotebook.c",
    "ttkPanedwindow.c",  "ttkProgress.c", "ttkScale.c",    "ttkScrollbar.c", "ttkScroll.c",
    "ttkSeparator.c",    "ttkSquare.c",   "ttkState.c",    "ttkTagSet.c",    "ttkTheme.c",
    "ttkTrace.c",        "ttkTrack.c",    "ttkTreeview.c", "ttkWidget.c",    "ttkStubInit.c",
};

const tk_win = [_][]const u8{
    "tkWin3d.c",       "tkWin32Dll.c",  "tkWinButton.c",  "tkWinClipboard.c", "tkWinColor.c",
    "tkWinConfig.c",   "tkWinCursor.c", "tkWinDialog.c",  "tkWinDraw.c",      "tkWinEmbed.c",
    "tkWinFont.c",     "tkWinGDI.c",    "tkWinIco.c",     "tkWinImage.c",     "tkWinInit.c",
    "tkWinKey.c",      "tkWinMenu.c",   "tkWinPixmap.c",  "tkWinPointer.c",   "tkWinRegion.c",
    "tkWinScrlbr.c",   "tkWinSend.c",   "tkWinSendCom.c", "tkWinSysTray.c",   "tkWinWindow.c",
    "tkWinWm.c",       "tkWinX.c",      "stubs.c",        "ttkWinMonitor.c",  "ttkWinTheme.c",
    "ttkWinXPTheme.c",
};

/// WindowsでX11 APIをエミュレートする層。
const tk_xlib = [_][]const u8{ "xcolors.c", "xdraw.c", "xgc.c", "ximage.c", "xutil.c" };

/// unix/配下のうちWindowsでも使われるもの。
const tk_unix_shared = [_][]const u8{ "tkUnixMenubu.c", "tkUnixScale.c" };

/// Linux(X11)のunix/配下。フォントはXft版(tkUnixRFont.c)を使う。
const tk_unix_x11 = [_][]const u8{
    "tkUnix.c",         "tkUnix3d.c",       "tkUnixButton.c",  "tkUnixColor.c",   "tkUnixConfig.c",
    "tkUnixCursor.c",   "tkUnixDraw.c",     "tkUnixEmbed.c",   "tkUnixEvent.c",   "tkUnixFocus.c",
    "tkUnixInit.c",     "tkUnixKey.c",      "tkUnixMenu.c",    "tkUnixScrlbr.c",  "tkUnixSelect.c",
    "tkUnixSend.c",     "tkUnixSysNotify.c", "tkUnixSysTray.c", "tkUnixWm.c",      "tkUnixXId.c",
    "tkUnixPrint.c",    "tkUnixRFont.c",
};

const win_system_libs = [_][]const u8{
    "advapi32", "comctl32", "comdlg32", "gdi32",  "imm32",   "kernel32", "netapi32",
    "ole32",    "oleaut32", "shell32",  "user32", "userenv", "uuid",     "winspool",
    "ws2_32",
};

const linux_tcl_libs = [_][]const u8{ "dl", "pthread", "m", "z" };
/// pkg-configの名前(xft経由でfreetype2のインクルードパスも得る)。
const linux_tk_libs = [_][]const u8{ "x11", "xft", "fontconfig", "freetype2", "xscrnsaver", "xext" };

// ---------------------------------------------------------------------------

pub const TclTk = struct {
    tcl: *std.Build.Step.Compile,
    tk: *std.Build.Step.Compile,
    names: LibNames,
    /// 静的リンク時にexeへ含める必要があるTkのリソース(Windowsのカーソル・ダイアログ等)。
    exe_resource: ?std.Build.Module.RcSourceFile,
    tcl_library: std.Build.LazyPath,
    tk_library: std.Build.LazyPath,
    /// 環境変数(TCL_LIBRARY等)に渡すための実パス。
    tcl_library_path: []const u8,
    tk_library_path: []const u8,
};

pub fn build(b: *std.Build, tcl_dep: *std.Build.Dependency, tk_dep: *std.Build.Dependency, opts: Options) TclTk {
    const platform = Platform.of(opts.target);
    const names = LibNames.of(platform);
    const release = opts.optimize != .debug;
    const static = opts.linkage == .static;
    const plat_dir = if (platform == .windows) "win" else "unix";

    const opt_defs: []const []const u8 = concat(b, &.{
        if (release) &.{ "-DNDEBUG=1", "-DTCL_CFG_OPTIMIZED=1" } else &.{},
        // STATIC_BUILDが無い場合、BUILD_tcl/BUILD_tkを定義したソースは公開APIをエクスポートする
        if (static) &.{"-DSTATIC_BUILD=1"} else &.{},
    });
    const tcl_name = if (static) "tcl9" else names.tcl;
    const tk_name = if (static) "tk9" else names.tk;

    // tclUuid.h / tkUuid.h はmanifest.uuidから生成するヘッダ(ビルド識別に使われる)
    const uuid = b.addWriteFiles();
    _ = uuid.add("tclUuid.h", uuidHeader(b, "TCL", tcl_dep));
    _ = uuid.add("tkUuid.h", uuidHeader(b, "TK", tk_dep));

    // ---- Tcl ----
    const tcl_mod = cModule(b, opts);
    for ([_][]const u8{ "generic", plat_dir, "libtommath", "compat/zlib/contrib/minizip" }) |dir|
        tcl_mod.addIncludePath(tcl_dep.path(dir));
    if (platform == .windows) tcl_mod.addIncludePath(tcl_dep.path("compat/zlib"));
    tcl_mod.addIncludePath(uuid.getDirectory());

    const tcl_base = concat(b, &.{ tclDefs(platform), opt_defs, &.{"-DBUILD_tcl"} });
    const tcl_pkg = pkgConfigDefs(b, names.tcl_file);
    tcl_mod.addCSourceFiles(.{ .root = tcl_dep.path("generic"), .files = &tcl_generic, .flags = tcl_base });
    tcl_mod.addCSourceFiles(.{ .root = tcl_dep.path("libtommath"), .files = &tommath, .flags = tcl_base });
    tcl_mod.addCSourceFile(.{ .file = tcl_dep.path("generic/tclPkgConfig.c"), .flags = concat(b, &.{ tcl_base, tcl_pkg }) });
    switch (platform) {
        .windows => {
            tcl_mod.addCSourceFiles(.{ .root = tcl_dep.path("win"), .files = &tcl_win, .flags = tcl_base });
            tcl_mod.addCSourceFile(.{ .file = tcl_dep.path("generic/tclZipfs.c"), .flags = tcl_base });
            tcl_mod.addCSourceFiles(.{ .root = tcl_dep.path("compat/zlib"), .files = &zlib, .flags = tcl_base });
            // tclMain.cはANSI版とUNICODE版(Tcl_MainExW)の2回コンパイルする
            tcl_mod.addCSourceFile(.{ .file = tcl_dep.path("generic/tclMain.c"), .flags = concat(b, &.{ tcl_base, &.{ "-DUNICODE", "-D_UNICODE" } }) });
            for (win_system_libs) |lib| tcl_mod.linkSystemLibrary(lib, .{});
        },
        .linux => {
            tcl_mod.addCSourceFiles(.{ .root = tcl_dep.path("unix"), .files = &tcl_unix, .flags = tcl_base });
            // 共有ライブラリ自身のパス(zipfsのマウント元)をdladdrで得るためのマクロ
            tcl_mod.addCSourceFile(.{ .file = tcl_dep.path("unix/tclUnixFile.c"), .flags = concat(b, &.{ tcl_base, tcl_pkg, &.{"-D_GNU_SOURCE"} }) });
            // tclZipfs.cはzlibの内部ヘッダ(zutil.h)を使うため、このファイルだけ同梱zlibを参照させる
            // (それ以外はシステムのzlib.hを使う。unix/Makefile.inと同じ扱い)
            const zlib_dir = tcl_dep.builder.root.joinString(b.allocator, "compat/zlib") catch @panic("OOM");
            tcl_mod.addCSourceFile(.{ .file = tcl_dep.path("generic/tclZipfs.c"), .flags = concat(b, &.{ tcl_base, tcl_pkg, &.{ "-D_GNU_SOURCE", b.fmt("-I{s}", .{zlib_dir}) } }) });
            tcl_mod.addCSourceFile(.{ .file = tcl_dep.path("unix/tclUnixInit.c"), .flags = concat(b, &.{ tcl_base, &.{
                "-DTCL_LIBRARY=\"//zipfs:/lib/tcl/tcl_library\"",
                "-DTCL_PACKAGE_PATH=\"\"",
            } }) });
            for (linux_tcl_libs) |lib| tcl_mod.linkSystemLibrary(lib, .{});
        },
    }
    const tcl = b.addLibrary(.{ .name = tcl_name, .linkage = opts.linkage, .root_module = tcl_mod });
    // ELFの共有ライブラリは既定で未定義シンボルを許容し実行時まで問題が見えないため、リンク時に検出する
    tcl.linker_allow_shlib_undefined = false;

    // TkはTclのstubテーブル(tclStubsPtr)を直接参照する箇所があるため、共有ライブラリとしては
    // 公式同様にUSE_TCL_STUBSでビルドしてTclのstubライブラリにリンクする(Tclを直接リンクしない)。
    // 静的リンクでは同一バイナリ内なのでTclへ直接リンクする。
    const tk_tcl_link = if (static) tcl else buildTclStub(b, tcl_dep, uuid, opts, opt_defs, platform, names);

    // ---- Tk ----
    const tk_mod = cModule(b, opts);
    for ([_][]const u8{ "generic", "generic/ttk", plat_dir, "bitmaps" }) |dir|
        tk_mod.addIncludePath(tk_dep.path(dir));
    if (platform == .windows) tk_mod.addIncludePath(tk_dep.path("xlib"));
    tk_mod.addIncludePath(tcl_dep.path("generic"));
    tk_mod.addIncludePath(tcl_dep.path(plat_dir));
    tk_mod.addIncludePath(uuid.getDirectory());

    const tk_base = concat(b, &.{ tkDefs(platform), opt_defs, if (static) &.{} else &.{"-DUSE_TCL_STUBS"} });
    tk_mod.addCSourceFiles(.{ .root = tk_dep.path("generic"), .files = &tk_generic, .flags = tk_base });
    tk_mod.addCSourceFiles(.{ .root = tk_dep.path("generic/ttk"), .files = &ttk_generic, .flags = tk_base });
    tk_mod.addCSourceFiles(.{ .root = tk_dep.path("unix"), .files = &tk_unix_shared, .flags = tk_base });
    tk_mod.addCSourceFile(.{ .file = tk_dep.path("generic/tkPkgConfig.c"), .flags = concat(b, &.{ tk_base, pkgConfigDefs(b, names.tk_file) }) });
    tk_mod.linkLibrary(tk_tcl_link);

    var exe_resource: ?std.Build.Module.RcSourceFile = null;
    switch (platform) {
        .windows => {
            tk_mod.addCSourceFiles(.{ .root = tk_dep.path("generic"), .files = &tk_generic_win, .flags = tk_base });
            tk_mod.addCSourceFiles(.{ .root = tk_dep.path("win"), .files = &tk_win, .flags = tk_base });
            tk_mod.addCSourceFiles(.{ .root = tk_dep.path("xlib"), .files = &tk_xlib, .flags = tk_base });
            tk_mod.addCSourceFile(.{ .file = tk_dep.path("generic/tkMain.c"), .flags = concat(b, &.{ tk_base, &.{ "-DUNICODE", "-D_UNICODE" } }) });
            for (win_system_libs) |lib| tk_mod.linkSystemLibrary(lib, .{});

            // TkはTk_GetHINSTANCE()のモジュールからリソースを読む。DLLではDllMainが自身のHINSTANCEを
            // 設定するためDLLに、静的リンクではGetModuleHandle(NULL)=exeになるためexeに含める。
            const tk_resource: std.Build.Module.RcSourceFile = .{
                .file = tk_dep.path("win/rc/tk_base.rc"),
                .include_paths = b.allocator.dupe(std.Build.LazyPath, &.{tk_dep.path("win/rc")}) catch @panic("OOM"),
            };
            if (static) exe_resource = tk_resource else tk_mod.addWin32ResourceFile(tk_resource);
        },
        .linux => {
            tk_mod.addCSourceFiles(.{ .root = tk_dep.path("unix"), .files = &tk_unix_x11, .flags = tk_base });
            for (linux_tk_libs) |lib| tk_mod.linkSystemLibrary(lib, .{});
            for ([_][]const u8{ "dl", "pthread", "m" }) |lib| tk_mod.linkSystemLibrary(lib, .{});
        },
    }
    const tk = b.addLibrary(.{ .name = tk_name, .linkage = opts.linkage, .root_module = tk_mod });
    tk.linker_allow_shlib_undefined = false;

    return .{
        .tcl = tcl,
        .tk = tk,
        .names = names,
        .exe_resource = exe_resource,
        .tcl_library = tcl_dep.path("library"),
        .tk_library = tk_dep.path("library"),
        .tcl_library_path = tcl_dep.builder.root.joinString(b.allocator, "library") catch @panic("OOM"),
        .tk_library_path = tk_dep.builder.root.joinString(b.allocator, "library") catch @panic("OOM"),
    };
}

fn cModule(b: *std.Build, opts: Options) *std.Build.Module {
    return b.createModule(.{
        .target = opts.target,
        .optimize = opts.optimize,
        .link_libc = true,
        // Tcl/Tkのソースは未定義動作検出(UBSan)を想定していないため無効化する
        .sanitize_c = .off,
        // 静的ライブラリも共有ライブラリ(Tk)へリンクされうるため位置独立コードにする
        .pic = true,
    });
}

/// Tclのstubライブラリ(tclstub)。拡張(Tk等)がTcl_InitStubs経由でTclのAPIを呼ぶために使う。
/// 各Makefile.inのSTUB_OBJSと同じくSTATIC_BUILDでコンパイルする。
fn buildTclStub(
    b: *std.Build,
    tcl_dep: *std.Build.Dependency,
    uuid: *std.Build.Step.WriteFile,
    opts: Options,
    opt_defs: []const []const u8,
    platform: Platform,
    names: LibNames,
) *std.Build.Step.Compile {
    const mod = cModule(b, opts);
    for ([_][]const u8{ "generic", if (platform == .windows) "win" else "unix", "libtommath" }) |dir|
        mod.addIncludePath(tcl_dep.path(dir));
    mod.addIncludePath(uuid.getDirectory());
    const flags = concat(b, &.{ tclDefs(platform), opt_defs, &.{
        "-DSTATIC_BUILD=1",
        b.fmt("-DCFG_RUNTIME_DLLFILE=\"{s}\"", .{names.tcl_file}),
        "-DCFG_RUNTIME_BINDIR=\"//zipfs:/lib\"",
        "-DCFG_RUNTIME_LIBDIR=\"//zipfs:/lib\"",
    } });
    mod.addCSourceFiles(.{
        .root = tcl_dep.path("generic"),
        .files = &.{ "tclStubLib.c", "tclStubCall.c", "tclStubLibTbl.c", "tclTomMathStubLib.c", "tclOOStubLib.c" },
        .flags = flags,
    });
    return b.addLibrary(.{ .name = "tclstub", .linkage = .static, .root_module = mod });
}

fn uuidHeader(b: *std.Build, comptime prefix: []const u8, dep: *std.Build.Dependency) []const u8 {
    const path = dep.builder.root.joinString(b.allocator, "manifest.uuid") catch @panic("OOM");
    const content = std.Io.Dir.cwd().readFileAlloc(b.graph.io, path, b.allocator, .limited(256)) catch "unknown";
    return b.fmt("#define " ++ prefix ++ "_VERSION_UUID \\\n{s}\n", .{std.mem.trim(u8, content, " \r\n")});
}

fn concat(b: *std.Build, parts: []const []const []const u8) []const []const u8 {
    var list: std.ArrayList([]const u8) = .empty;
    for (parts) |p| list.appendSlice(b.allocator, p) catch @panic("OOM");
    return list.items;
}
