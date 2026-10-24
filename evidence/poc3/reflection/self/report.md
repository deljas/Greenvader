# POC3-REFLECTION 自己報告

## 対象版・変更

- Windows / Godot 4.7.2 stable / Vulkan Forward+ / NVIDIA GeForce RTX 5070 Ti。
- 読取・比較の基準HEAD `a97fbcdb996ba90a74c9cf5cf66cdb8206d19786`＋独立確認済みHELPERSのindex差分。共有treeの既存差分は再適用・変更していない。
- ゲーム編集は `scripts/poc2/view/world_view.gd` の水面setupだけ。`source.env_tuning`をdeep copyし、そのコピーの`water.reflection_divisor=1`で共通Waterを構築する。PoC3の反射を本画面と同じ640×360にする。
- 共通water_view、shader、Actor、既存EntitySprite/Catalog、共有environment.jsonは無変更。旧版共通設定のdivisor=2を保持。波・色・影・素材・カード/投影は変更しない。
- 試験: `tests/poc3/reflection/self_compare.gd`、UID、`self_run.ps1`。`actual_diff.patch`と`freeze.json`がゲーム差分・対象hashを記録する。最終world_view SHA256 `AB63C95E19285A30167EF259B662442D66916A8009E495ACE910C47152E84544`。

## 実行結果

1. headless `--check-only --script self_compare.gd`: exit 0（`parse.log`）。描画確認とは区別する。
2. `self_run.ps1 -Mode compare`: exit 0、**19 PASS / 0 FAIL**（`compare.log`、`compare_results.json`）。変更前の同じfixtureでdivisor2→1を比較。本画面640×360、各反射320×180／640×360、nearest・AA無効、主人公＋仮boar＋成熟clover/carrot。静止、歩行4コマ、左右転向の7場面を各設定1回撮影。各場面で本画面と反射textureを保存した。これはcapture/設定の自動条件で、見た目の評価は次節。
3. PoC3限定設定を変更し、`self_run.ps1 -Mode normal -ExpectFullResolution`: exit 0、**6 PASS / 0 FAIL**（`normal.log`、`normal_results.json`）。実Session/Worldで合法な水辺(111,55)を選び撮影。通常本画面・反射とも640×360、元のsession.env_tuning不変と共通JSON divisor2を確認した。全比較の再走はしていない。

自動条件は計25 PASS / 0 FAIL。ゲーム試験の失敗・追試はなし。比較補助sheet生成時にシステムPythonのPillow不在を確認し、インストールせずWindows System.Drawingで既存PNGを合成した。これはゲーム試験の失敗ではない。

## 画像を開いて確認した範囲

- `d2_still.png` / `d1_still.png`: 同一場面で主人公の葉・顔、cloverの輪郭、boarの細部がdivisor1で読みやすくなる。半解像度由来の大きな画素塊が軽減した。
- `comparison_contact.png`: 元の7場面PNGを各2倍nearestで並べた補助sheet。歩行4コマと左右転向で、divisor1の反射に極端な潰れや足からの大きな位置ずれは見られない。通常のコマ変化はある。植物は固定、主人公・boarだけ移動/転向させた。boarは仮1方向画像の左右反転であり、完成4方向素材の検証ではない。
- 足元metadataでは主人公の本画面Xが265→268→270→273→275、Y=200。divisor1反射cameraのXも同じ、Y=160.2022で一定。divisor2では同じ反射足が半画素を含むX=132.5等になり、半解像度格子で量子化する。これは粗さの一因の証拠で、全水面/全現象の唯一の原因と断定しない。
- `normal_world_connection.png`: 通常街区・水面・主人公の接続画像。木による遮蔽があり、この画像単体では細かな反射形状を評価しない。形状・動きの評価は固定fixture側。通常の建物・影の表示を確認したが、全遮蔽条件の回帰試験ではない。
- 追加のshader/カード/投影修正を必要とする形状破綻は、この限定比較では認めなかった。

## 限定負荷

各設定で短い12フレームの1区間だけを測定。**`force_draw(false)`同期呼出のCPU待ち時間であり、GPU専用時間、通常fps、通常全マップ性能の保証ではない**。同じ固定fixtureの補助比較。

| 反射 | CPU待ち中央値 | 最小–最大 | 全体draw call | 全体primitive |
|---|---:|---:|---:|---:|
| 320×180 (divisor2) | 0.358 ms | 0.247–2.427 ms | 15 | 3934 |
| 640×360 (divisor1) | 0.358 ms | 0.284–0.812 ms | 15 | 3934 |

この区間で重大な悪化は観測しなかった。反射画素数は4倍になるため、他のGPU・密集場面・通常全mapで同じ負荷になるとは推定しない。負荷の総当たりや繰り返し計測はしていない。

## 保全・終了状態

- 全GPU起動前にCreateNewで所有overrideを作成し、`no_focus=true`、`mode=1`を指定。隔離APPDATA/LOCALAPPDATAを使用し、開始/終了で最小化・unfocusableを確認。SubViewport.UPDATE_ALWAYSとforce_draw(false)で撮影。
- OS入力、前面化、カーソル移動、ウィンドウ復元、未知プロセス停止は行っていない。
- 実ユーザーの旧save3件（poc_saves/slot、poc2_saves/slot1とbackup）の前後SHA256はすべて一致。
- ゲーム編集/Godot実行停止を親へ通知して実行権を返却済み。`freeze.json`時点でGodot process 0、overrideなし。Git操作は読取のみ、共有資料・作業票・他者CONTENT群は未編集。

## NOT_RUN・残課題

- 物理入力、全照明/雨/全角度/全水面、全敵植物素材、完成アート、通常全マップGPU専用時間・他GPU性能。
- 統合回帰一式やゲーム体験・楽しさの最終評価は今回行わない。親のINTEGRATION/VERIFYで扱う。
- 水の色/波/美術磨き込みは対象外。独立確認と最終受入は親の担当。

文書反映用の事実: PoC3限定deep-copy overrideで反射640×360を採用。共通設定を維持し、限定7場面比較で読みやすさが改善。自動25 PASS、形状/動きの目視範囲とCPU補助値の限界を併記する。
