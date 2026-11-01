# 技術検証: Tk の画面を利用者に見せずに描いて、画像と各 Widget の位置を取り出す

tk-designer のキャンバスで、tokotachi のデザイナー（ADR 0039）と同じように「実物の描画結果」を表示できるかを確かめた。
ライブラリには引き継がない検証用のコード。

```sh
zig build run -- <画面定義.json> <出力ディレクトリ>     # 例: zig build run -- sample.json out
```

`tkrender` は画面定義（[sample.json](sample.json)）から Tk の画面を組み、次を出力する。

- `result.json`: 各 Widget の位置・大きさ・要求サイズ（`winfo`）、所要時間、画像どうしの差分の画素数
- `offscreen.png` / `transparent.png` / `onscreen_self.png` / `onscreen_truth.png`: 取り込んだ画像

## 結果（2026-11-02）

環境: Windows 11（日本語版、表示倍率 133%）、WSL2 Ubuntu 24.04（WSLg）。Tcl/Tk 9.0.4（zig_tk でソースからビルド）。
画面は ttk の Label・Entry・Combobox・Checkbutton・Radiobutton・Scale・Progressbar・Button と classic の Text（日本語を含む）、420×330。

| 項目 | Windows | Linux（WSLg） |
|---|---|---|
| 位置（`winfo`）が画面外と画面上で一致 | 一致 | 一致 |
| **画面外**に置いたウィンドウの取り込み | **失敗**（PrintWindow は真っ白） | **成功**（XComposite。実際の画面と差分 0 画素） |
| **画面内・不透明度 0**（利用者には見えない）の取り込み | **成功**（PrintWindow。実際の画面と差分 10 画素※） | 成功（差分 0 画素） |
| 編集 1 回（オプション変更→描画→取り込み）の平均 | 約 32 ms | 約 6 ms |
| 画面全体の組み直し（Widget 11 個を作り直して配置）の平均 | 約 22 ms | 約 32 ms |
| 最初の組み立て（Tk の初期化後） | 約 83 ms | 約 102 ms |

※ 差分は画像の下端 3 行の両端だけで、Windows 11 のウィンドウの角丸に背後が写り込んだもの。Tk が描いた内容は一致している。

「実際の画面」は、ウィンドウを画面上に最前面で表示し、Windows は画面の DC からの BitBlt、Linux はウィンドウからの XGetImage で取り込んだもの。

## 分かったこと

- **Windows では、画面外のウィンドウは描かれない。** OS が見えない領域に描画要求（WM_PAINT）を送らず、Tk も描かないため、
  PrintWindow（PW_RENDERFULLCONTENT）で取り込める内容が無い。
  **画面内に置いたまま不透明度を 0 にする**（`wm attributes . -alpha 0`）と、OS からは表示中のウィンドウとして扱われて描かれ、
  合成前の内容を PrintWindow で取り込める。描画の直後に待たずに取り込んでも正しい画像になった。
- **Linux（X11）では画面外のままでよい。** XComposite でウィンドウを裏の pixmap に描かせると、画面外でも実際の表示と同じ画素が取れる。
  （素の XGetImage は、Xの仕様上、画面に見えていない範囲を取れない）
- 位置（`winfo`）は画面外でも正しく、画面上と一致する。**位置だけで良ければ、どちらの OS でも画面外で済む。**
- 時間は、編集のたびに描き直して画像を渡しても実用的な範囲（tokotachi の WebAssembly 版は約 8 ms）。
- Tk 9.0.4 の Windows 版では、`wm geometry . +100+100`（位置だけの指定）で画面外から戻らなかった（8.6 では戻る）。
  大きさを含めた `420x330+100+100` なら戻る。

## 残っている確認事項

- 不透明度 0 のウィンドウが、利用者のマウス操作を横取りしないか、フォーカスを奪わないか（Windows。必要なら Win32 で
  WS_EX_TRANSPARENT・WS_EX_NOACTIVATE を付ける）。
- 表示倍率（DPI）の扱い。この検証はプロセスを DPI 対応にして物理画素で取り込んだ。Tk のスケーリング（`tk scaling` 1.33）は
  利用者のアプリの実行時と同じになるか。
- 画面のない Linux（CI 等）では Xvfb が要る（WSLg・デスクトップでは不要）。
- 拡張との通信（標準入出力で画面定義を受け取り、画像と位置を返す常駐プロセス）、実行ファイルの同梱と署名、
  Tk 8.6（cpp_tk・Python の実行環境）との描画の差。
