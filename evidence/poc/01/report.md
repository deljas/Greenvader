# POC-01 検証報告（実装者自己検証）

対象版: HEAD 99013702eaf36db72a64d60d284680fb834f13c5 ＋既存未コミット差分（本作業での既存ファイル変更なし。新規のみ）。
実行: Godot 4.7.2 (Windows, Vulkan Forward+, RTX 5070 Ti)。独立検証・受入は未実施。

## 再現手順
1. `Godot_v4.7.2-stable_win64_console.exe --headless --path C:\godot\greenvader --import`（import.log）
2. logic: `--headless --path C:\godot\greenvader --script res://tests/poc/base/logic.gd`（logic.log）40 PASS / 0 FAIL
3. GPU: `--path C:\godot\greenvader --script res://tests/poc/base/gpu.gd`（gpu.log、ウィンドウ表示、root.unfocusable=true、OS入力なし）14 PASS / 0 FAIL
4. 手動: `launchers/run_poc.bat`

## 結果
- PASS: 座標往復、セル変換、斜め正規化、壁停止(壁ブロック・外周)、pause、早送り刻み非依存(60s一括=0.25s×240: elapsed/growth120/spread60)、実delta上限、InputMap(WASD斜め=長さ1、Esc=pause、左クリックでaim)注入、解像度切替で位置/aim/camera.size不変、中央クリック=注視点付近、余白/UI上クリック拒否、窓不足時640固定＋明示、sprite影同期、1テクセル=1px・足元画素格子、両解像度でのGPU撮影、sprite画素のにじみなし(4回のサブピクセル移動で不一致0)、影板が実際に影を落とす。
- NOT_RUN: 実OS入力経路(物理キーボード/マウス)、非整数窓(1366×768等)の実表示、実時間の連続操作のユーザー確認、独立検証。
- 画像: render_640.png / render_960.png（SubViewport出力）、*_as_1920x1080.png（nearest 3倍/2倍）、screen_*_with_hud*.png（HUD込み）、*_no_shadow.png、*_moved.png。
- 注: headless窓は640×360固定のため、テストは window_size_override で1920×1080を仮定。GPU撮影は1280×720窓で行い、1920×1080像はSubViewport画像のnearest拡大（実1080p窓の表示ではない）。

## 変更ファイルとsha256
- 5be6605dc78a283447a24fa062cff676f332d93227b61a2dbda46a09a1d16b41  scripts/poc/poc_actor.gd
- 602b61d2623c4d60c7d3c2086e8a1a80b590ca07ecc2c59800062e0aefbdd0bb  scripts/poc/poc_config.gd
- bc0e62ac009200221495a04fdca4e615cf12be89aff2fb331b1a445e24540921  scripts/poc/poc_coords.gd
- bf8f88fce03e5353d358c11dad41d0036d39fd78f929d2de64078d6c8652a56d  scripts/poc/poc_input.gd
- 1f7ac949e7e837d8c19a09b2a50fa05af90a50a587816c99055b0b6a966f4402  scripts/poc/poc_main.gd
- 5c1f83cb09b0a4772f25df2d06f70b124c3030d079fd21999873cb79facbc21b  scripts/poc/poc_session.gd
- ef5950dcf2169bf6e75897263b4a7287b7d753c68585aab780d6c1111207493a  scenes/poc.tscn
- 4ea5a6d2f4f18f967df9f4138dcbe756b06088ca813e66d73af5d110ea0ea031  tests/poc/base/gpu.gd
- 9e7c8bf48a34ca35e4367182c4ac8ac385bf79abba700e741c48be2c0f8cfc04  tests/poc/base/logic.gd
- a15d17ebd5f98f5e68e731f723ca5c4987cfb5d67786d109650cb81f329a7848  launchers/run_poc.bat
- 02af487cf4d7a8ef1023d9fd24cd4a04bd2a01e6a7cdc24c0547f455e1f1805a  launchers/README.md
