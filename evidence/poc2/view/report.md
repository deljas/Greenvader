# POC2-03 表示担当の自己報告

対象は基準 `151a53f20255489ef08481e2a353258cd8ac559c` と共有ツリーの未コミット PoC2 差分。編集対象と SHA-256 は `source_manifest.json`。親から source 編集停止指示を受け、以降は本報告と manifest のみ更新。第一弾のコード・素材・保存を変更していない。

## 実装

- 新規 `scenes/poc2.tscn` と `launchers/run_poc2.bat`。既存採用主人公 24×36 / 4方向 fire と、Placement/GroundCover/Water/Wall の3D景観を再利用。内部640×360、nearest・整数倍、カメラ画像軸スナップ。地面 dirty 消費者は WorldView 一つ。
- WASD/矢印、通常種射撃と給水、Q/R のたいあたり/種バズーカ。植物8種の小アイコンと化石ロック、コスト tooltip、設置 footprint preview。配置ガトリンガーの弾薬投入量 popup。
- 左上の円形ミニマップ、M の時間停止全体マップ、探索地形の記憶と未知敵/化石の非表示。全体マップのホイール整数1/2/4倍拡大を操作性補助として追加。個体の不足HP/種/水ゲージ、選択時だけ撤去/補給、投入量と返還量の popup。移動は backend へ注文し、閉じるまで進行停止。
- `user://poc2_saves/slot1.json` 専用保存、一時ファイル→前回backup→確定。候補 Session の完全復元に成功した後だけ main が交換。不正保存は現ゲームを保持。JSON float の full_precision 出力、意図した不正JSONの読込はエラーログを出さず失敗を返す。
- 遮蔽時の半透明＋高さ1.6m超の上部カット。元の全高影はshadow専用コピーで保持。太陽はゲーム内0.1時間の段階更新（標準600秒日では2.5秒）で毎frameの影方向更新を削減。水面反射の磨き込みはしていない。
- 削除済み/消費済みentityの描画nodeを破棄し、単に視界外になった生存enemyはhiddenで保持。追加美術磨き込みは行わず、植物/クモ/親玉は機能を読める簡易形状。

## 実行と採用結果

Godot 4.7.2 / Vulkan Forward+ / RTX 5070 Ti。全GPU試験は `_init` で `root.unfocusable=true`、入力は Input.parse_input_event と直接の管理API、撮影は viewport texture のみ。OS入力・カーソル移動・前面化は不使用。実行プロセスはすべて終了し、Godot/import 専有権を親へ返却。

最初の sandbox 実行は user://書込不可で保存に失敗し、試験側のnull file処理で停止。Ctrl+C終了後、require_escalated が許可された実行で保存とGPUを確認した。生の経緯は `attempt1/gpu_smoke.log` に保持。

`checks.json` / `gpu_smoke.log` は広いGPU自己試験の生結果。640解像度、engine内キー移動、5個体配置、スイカ3×4 preview、map時間停止、補給の非貫通/個数、移動注文の待機、backup、壊れたsave時の現ゲーム保持、太陽の非毎frame更新が通る。描画画像01〜04を目視し、街区素材・主人公・日本語・map/popup・cutawayを確認。

以下のFAILは消さず、原因と後続証拠を対応させる。

| 生結果の失敗 | 原因/変更 | 最終証拠 |
|---|---|---|
| 初回 map_move_order_queued | 試験のクリック先が別植物の選択半径内。空き地クリックへ修正 | 正規権限GPU `checks.json` の同条件 PASS |
| save_load_full_state | JSON往復の income_fraction だけに約1e-18級数値差。`save_probe.json` に診断を保持。形・キー・配列長・非数値を厳密照合し、数値のみ絶対1e-9以下を許容する比較へ変更 | `followup_checks.json`: save_roundtrip_structure_and_values PASS。backup/破損保持もPASS |
| followup engine_wheel_zoom | 試験がcontent座標をwindow座標へ変換していなかった | `wheel_checks.json` / `wheel_gpu.log`: root.get_final_transform適用の engine入力 PASS、07画像 |

`followup_checks.json` の残る8項目はPASS。save完全往復・破損JSON静かな拒否・income hover設定と射撃遮断・消費shot node解放・視界外生存enemyの保持・cutaway稼働を確認。毎回回帰全体を繰り返さず、失敗/変更した範囲だけ追試。

## 証拠

- 操作中: `01_play_ui.png` / `01_play_world.png`
- 全体マップ: `02_map_ui.png`
- 拡大と撤去確認: `03_remove_confirmation_ui.png`
- 遮蔽上部カット: `04_occlusion_ui.png` / `06_cutaway_ui.png`
- engineホイール: `07_engine_zoom_corrected_ui.png`
- 生結果: `checks.json`, `followup_checks.json`, `wheel_checks.json` と各log

## NOT_RUN / 残課題

- 実キーボード→OS→ゲームの経路、実マウス操作。ユーザーの手動確認が必要。
- 長時間GPU負荷、全マップ/全姿勢/全照明条件、最大数の植物/敵での性能。水面反射の美術評価。
- tooltipはhoverを受け取る設定とクリック遮断を確認。OSカーソルを動かしてtooltip表示まで確認する試験は行っていない。
- 全体の楽しさ・バランス・アートの最終判断はユーザー。独立受入/全体合否は親の判断。
