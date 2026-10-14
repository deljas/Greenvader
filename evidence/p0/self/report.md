# P0-01 実装者自己報告

対象: 基準コミット `16b845f` 上の未コミットP0追加。Godot `4.7.2.stable.official.ed1daf0bf`、Windows、Forward+ / Vulkan 1.4.341、NVIDIA GeForce RTX 5070 Ti。最終ソースSHA256は `source-manifest.json`。

変更: `project.godot`, `scenes/main.tscn`, `scripts/{main,pixel_art,player,terrain,weather_view}.gd`, `tests/self/p0_checks.gd` とGodot生成uid、および本証拠ディレクトリ。共有README/docs/Git設定は編集していない。

実装: 640×360固定内部解像度、viewport/keep/integer、最小640×360。WASDで96px/秒、斜め等速。連続移動座標と整数表示座標を分離し、カメラを主人公と同一更新で丸める。マウス照準、Escポーズ、左クリック種・右クリック水の寿命付き仮弾（最大64）。草/荒地/水/花/イノシシ/種/芽/成熟の手作り画素素材。晴れ/雨/夜（1/2/3とボタン）、夜はPointLight2Dと別の加算発光。日本語UI。天気は外観のみ、戦闘/成長/地域/資源/保存はP0未担当。

## 実行検証

- PASS: 最終版headless editor import（`import.log`）、headless main smoke 30フレーム（`smoke.log`）、自己テスト15条件（`checks.log`, failures=0）。
- PASS（API/画像証拠）: 非headless Forward+の1280×720=2倍/余白0、1920×1080=3倍/余白0、1366×768=2倍/余白左右43・上下24。各 `sunny-*.log` のscreen_transform。実画面外枠の画素を検査した結果ではない。
- PASS（内部レンダー画像目視）: `sunny-1280.png`, `rain-1280.png`, `night-1280.png` は各640×360。主人公/イノシシ/種/水の色と形、草/水/植物、日本語UI、夜の別発光を確認。人工的な輪郭は付加していない。美術の最終承認ではない。
- NOT_RUN: native画面でのマウス/キーボード実操作、外枠余白の実画素、日本語の拡大後可読性、移動中のにじみ、画面端カメラ、最小サイズへnativeリサイズ。親/独立検証へ渡す。
- 初回sandbox importはAppData作成権限によるエラー。Godot実行の自動承認後に再実行し最終importはエラーなし。承認拒否は発生していない。

画像はカメラ更新順修正前に取得。静止初期構図の変更はない。最終版でimport/smoke/自己テストを再取得し、修正に関わる動的描画は未確認として残す。親がnative画面を起動するため、実装者からのGodot再実行は停止した。

## 実行方法

```powershell
& C:/godot/Godot_v4.7.2-stable_win64_console.exe --path C:/godot/greenvader --resolution 1280x720
& C:/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path C:/godot/greenvader --script res://tests/self/p0_checks.gd
```

キャプチャには `-- --condition=night --capture=res://evidence/p0/self/name.png --auto-quit` を追加可。画像は内部viewport、ウィンドウ外枠は含まない。

## 文書担当へ渡す変更情報

- 暫定表示基準: 内部640×360、タイル16px、主人公16×16px、最近傍、整数拡大、物理補間なし。UIは同じ内部画素格子で12pxシステムフォント、アンチエイリアスなし。
- レンダラー暫定採用: Forward+。実GPUで2Dライトと独立発光、3サイズを起動できた。性能負荷試験は未実施。
- 素材出典: 本実装者がGDScript内の文字行/整数矩形から自作した仮素材。編集元は `pixel_art.gd` と `terrain.gd`。外部画像/生成サービス/配布フォントなし。PNG比較画像は実際のGodot描画。日本語はWindowsのYu Gothic/Meiryoを実行時参照しフォントファイルを同梱しない。
- 後続: native操作と最終版描画を独立検証し、ユーザーへ初画面を提示。新指示によりP1以降には進まない。

Godotプロセスは自己作業終了時すべて閉じ、実行所有権を親に返却。実装ファイルは凍結。本報告は子の自己検証であり、P0/全体の受入合否は親が判断する。
