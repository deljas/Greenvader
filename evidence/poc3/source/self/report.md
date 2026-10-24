# POC3-SOURCE 自己確認

- 対象: HEAD `642963497286e5ea1cc880a806c2b4d464c697b3`（tag `poc2-before-poc3`）+ `implementation.diff` + `tests/poc3/source/self_entry.gd`。ゲーム実装の既存差分なし。最終ファイルhashは `source_hashes.json`。
- 実装: `project.godot` の通常入口を `res://scenes/poc2.tscn` へ、`run_game.bat` のコメントを現役入口に更新。旧通常2本・旧比較3本のbatだけ削除。ゲームのルール・素材・保存コードは未変更。
- 履歴/静的確認: 削除5本はすべて保全HEADのblobが存在。通常batはルートの `run_game.bat` 1本、残した7 labのシーンはすべて存在。詳細 `static_checks.json`。
- 残すlab用途: town=納品7棟/歩行/昼夜/水面、vine_compare=旧/納品ツタの成長比較、asset_showcase=6カテゴリ24件の材質/寸法/受影、greening_map=地面/壁面緑化/反射/受影、vegetation=植生部品/苔/ひび成長、light=太陽角/周回点光源/影、sprite_shadow=歩行spriteと3D投影影の同期。
- 実行直前: CONTENT-01共有資源は第1段階なし。Get-ProcessでGodotなし。CIMは読取権限なしのためNOT_RUN。
- import初回: 標準APPDATAへのeditor data/config作成がsandboxで拒否され開始できずNOT_RUN。`import.log`。既存保存は操作せず、APPDATA/LOCALAPPDATAを `self/runtime_profile/` 下へ隔離して再試験。
- 隔離import: Godot 4.7.2 `--headless --path C:\godot\greenvader --import` 成功、exit 0、エラーなし。`import_isolated.log`。
- headless: 設定されたmain_scene読込、タイトル停止、224×224、保存名前空間、640×360/nearest/整数倍の6 PASS / 0 FAIL。`headless_results.json`。これは自己probeの入力注入修正前であり、headless経路は修正の影響なし。
- GPU初回: Forward+/Vulkan RTX 5070 Ti。9 PASS / 2 FAIL。Input.parse_input_eventが非フォーカス窓のGUIボタンへ届かず、新規開始とその後のmapが失敗。ゲーム変更せず、証拠は `gpu_initial/` に保持。
- GPU限定追試: 自己probeの注入だけを `root.push_input(event, true)` に変更。11 PASS / 0 FAIL、exit 0。`gpu_results.json`。タイトル、新規開始、Mによる時間停止マップまで確認。root.unfocusableを_init最初で設定し、OS入力/前面化/カーソル操作なし。
- 描画: 実GPUのroot viewport撮影 `title.png`、`play.png`、`map.png` を目視。日本語UI/主人公/緑地/建物/影/マップを確認。640×360の鮮明な画素を保持。nativeウィンドウ外観や全照明の検査はしていない。
- 保存保全: 実ユーザー領域の `poc_saves/slot.json`、`poc2_saves/slot1.json`、`slot1.json.bak` の3件が前後SHA256/サイズ/一覧一致。`saves_before.json`、`saves_after.json`、`save_preservation.json`。保存/読込の操作は実施せず。
- 終了: `processes_after.json` のGodot 0件。自己実行は終了済み。runtime_profileは生成キャッシュとして親が限定ignore済み。
- NOT_RUN: batのOSダブルクリック、物理入力、各labの実起動、広いゲーム回帰/長時間/全照明/全サイズ。従来の既知問題とゲーム全体の受入はこの試験に含めない。
- import付随生成: 未追跡の既存試験uid3件（tests/poc2/map_orientation/independent/affected.gd.uid、independent/corner.gd.uid、self/corner.gd.uid）を検知。編集割当外のため削除/変更せず親へ報告。
- 文書担当への情報: 上記の入口、残す/削除するbat、保全タグ、限定結果とNOT_RUNを起動一覧/現役案内へ反映可能。共有文書/作業票は子から未編集。
