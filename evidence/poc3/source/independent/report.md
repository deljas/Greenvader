# POC3-SOURCE 限定独立検証

検証日: 2026-10-24。独立担当はゲーム実装を変更していない。最終受入判断は親が行う。

## 対象と環境

- 共有ツリー `C:/godot/greenvader`。HEAD/tag `poc2-before-poc3` はともに `642963497286e5ea1cc880a806c2b4d464c697b3`。
- 凍結対象は HEAD + project.godot/run_game.bat/旧bat5本の削除/.gitignore。文書担当の案内修正は並行しており、検証者は編集していない。
- 実際の入口差分は `actual_entry.diff`。自己提出 `self/implementation.diff` と実際のコード・bat差分が一致した（`diff_comparison.json`）。.gitignoreの追加は自己検証隔離profileだけ。
- `source_hashes_before.json` と `source_hashes_after.json` で対象13件が自己提出値とすべて一致。project.godot SHA256 `8689FA888C87DE441EA13D2A4325E20C5AEF826F4A76CB4DB1EBC18C9062FCE8`、run_game.bat `7878CD148C7F867AAE72B7778DE6B4D66CC64A090A7187202AD4D559AE95285A`。
- Windows NT 10.0.26200.0 / AMD64、Godot 4.7.2-stable official `ed1daf0bf001b61586d9930840f2f1394092c079`。独立実行はheadlessのみ。
- APPDATA/LOCALAPPDATAは `independent/profile/{roaming,local}` へ隔離。実際のGodot user_dataもこの配下だった。実ユーザー保存領域は一覧・サイズ・SHA256の読取のみ。
- 実行直前のCONTENT-01は第1段階でGodot/import予約なし。Godot既存プロセスなし。親から移管された実行権で代表smokeを1回実行。OS入力送信・前面化・カーソル操作・エンジン内入力注入はいずれも行っていない。

## 条件別結果

集計: 10 PASS / 0 FAIL / 6 NOT_RUN。起動smoke内の観測は6 PASS / 0 FAILで、集計の起動条件1件にまとめた。

| 条件 | 結果 | 独立確認と証拠 |
|---|---|---|
| 指定版が固定されている | PASS | HEAD/tag一致、13件の前後hash一致、実diffと提出diff一致。`source_hashes_*.json`、`diff_comparison.json` |
| 通常ゲームbatが1本で最新の遊べる版へ接続する | PASS | ルート通常batはrun_game.batのみ、launchers直下batなし。batはGodot実体を確認して `--path "%~dp0."` で起動し、固定シーン引数なし。configのmain_sceneはscenes/poc2.tscn、実体はpoc2_main.gd。`static_summary.json`、`actual_entry.diff` |
| 残す7labに実体と具体用途がある | PASS | 7bat→7scene→7scriptを追跡し全て存在。用途は下表と実コードを照合。`labs.json` |
| 削除bat5本を履歴から復元できる | PASS | tagのblobを `git cat-file blob` で証拠内restoredへ実復元。5件とも `git hash-object --no-filters` が元blobと一致。検証後、親の指示でworkspace内の復元先を検査し、作成したbat5本だけを削除。`restoration.json`にblob値と削除済みを記録。元の削除先は復元していない |
| 保存コードと保存先を変更しない | PASS | scripts/scenes/assets/dataにHEAD差分なし。poc2_save.gdはuser://poc2_saves/slot1.json、formatもHEADのまま。独立起動のsave_dirもuser://poc2_saves。`diff_comparison.json`、`smoke_results.json` |
| 実ユーザー保存データを削除・上書きしない | PASS | poc_saves/slot.json、poc2_saves/slot1.json、slot1.json.bakの3件が独立実行前後で一覧・サイズ・SHA256一致。自己検証前の3件とも一致。`saves_before.json`、`saves_after.json`、`save_preservation.json` |
| 既存成果を保全する | PASS | 保全manifest2939件を実ファイルと照合し2927件hash一致。差分12件は承認済み案内文書8件と削除bat4件のみ（run_poc.batは元からHEAD追跡済みで本manifest外）。欠落した4件は上のblob復元で保全確認。全追跡削除は承認されたbat5件だけ。コード・素材・既存試験・証拠の追跡差分なし。`preservation_check.json`、`preservation_summary.json`、`static_summary.json` |
| 実装差分が入口整理の範囲内 | PASS | main_scene/説明コメントとbat5削除、自己profileのignore追加。ゲームルール、素材、保存実装の変更なし。文書・試験・証拠の追加は別の承認範囲。`actual_entry.diff`、`git_status_after.txt` |
| 代表起動smoke | PASS | 独立probeからconfig指定シーンをchange_scene_to_fileし、実current_sceneがPoC2、title停止、保存先不変、隔離user_dataを確認。exit 0。`smoke_results.json`、`smoke_console.txt`、`smoke.log`。終了時残存診断は下記の観測事項として区別 |
| 提供GPU画像の独立目視 | PASS | self/title.png、play.png、map.pngを独立担当が実際に表示して確認。タイトル「グリーンベーダー PoC 2」、プレイの主人公/緑地/建物/影/日本語HUD、全体マップの菱形地形と既知部分を確認。640×360で画素が明瞭。画像hashは`reviewed_images.json`。新しいGPU実行の証拠ではない |
| batのダブルクリック・OS経由の起動 | NOT_RUN | 許可された限定範囲に従い実行しない。batの静的接続と設定シーンの起動を区別 |
| 物理キーボード・マウス経路 | NOT_RUN | OS入力・前面化禁止。ユーザー手動確認の範囲 |
| 独立GPU再起動・独立撮影 | NOT_RUN | ゲーム描画コード差分がなく、提供GPU画像3枚と対象hashを確認できたため追加再走不要と判断 |
| 7labそれぞれの実起動 | NOT_RUN | 実体・用途の静的照合まで。全lab再走は割当外 |
| 広いゲーム回帰・保存往復・通常終了 | NOT_RUN | SOURCEは入口整理のみ。旧既知問題、種/水切れ、安定/100%、長時間/全域性能、保存読込の動作を今回PASSにしない |
| 書き出し後のWindows動作 | NOT_RUN | 配布ビルドの変更・作成は今回の割当外 |

## 7labの具体用途

| lab | 実コードで確認した用途 |
|---|---|
| town | BUILDINGSの納品7棟、actor歩行、day_cycle、water、街灯 |
| vine_compare | 旧growth_patchと納品vines、ID選択、growth/play_durationによる成長比較 |
| asset_showcase | 6カテゴリ4件ずつのモデル読込、model_bounds、材質/受影、カテゴリ・個別表示 |
| greening_map | 歩行・地面緑化、WallGrowth、Water、太陽方位/仰角 |
| vegetation | 3棟共通植生、set_growth、moss/cracks表示 |
| light | 太陽方位/仰角、周回点光源、影 |
| sprite_shadow | 自動歩行fixture、pose_at_time/apply_pose、スプライトと投影影 |

用途の存在確認であり、外部納品原本の全件可用性や各lab動作の新しい合格ではない。

## 終了時診断（起動条件と別の観測事項）

- 重大度: 低・要注意情報。SOURCE起因の不具合としては未確定。
- 対象: `tests/poc3/source/independent_entry.gd` のprobe終了経路。
- 期待: probe終了時に生存リソースを解放する。実際: 6条件PASS・exit 0の後、`37 ObjectDB instances were leaked` と `20 resources still in use at exit` が出た。`smoke_console.txt`、`smoke.log` に原文を保持。
- 最小再現: APPDATA/LOCALAPPDATAを証拠内profileへ隔離し、`Godot_v4.7.2-stable_win64_console.exe --headless --path C:/godot/greenvader --script res://tests/poc3/source/independent_entry.gd` を1回実行する。
- probeはscene.session.close()を呼ばずquitする。既存session.close()には循環参照/接続解放があり、自己probeはそれを明示的に呼んでいるため、独立probeの後処理不足の可能性が高い。ただし原因を切り分ける再実行はしていない。通常のゲーム終了でも発生するとは結論しない。親の指示で追加再走なし。
- blob復元の初回照合でrun_poc.batだけfiltered hashが違ったが、raw復元bytesの `--no-filters` 照合は一致。Gitの改行正規化を避ける検証手順の修正であり、復元内容の不一致ではない。初回filtered値もrestoration.jsonに残した。

## 終了状態

- Godotプロセス0件（`processes_after.json`）。起動は終了済み、Godot/import権を親へ返却する。
- 編集は `tests/poc3/source/independent_entry.gd` と `evidence/poc3/source/independent/` のみ。共有進捗・ゲームコード・設定・素材・実ユーザーsave・他担当文書は未編集。stage/commit/branch/push/再委任なし。
- 自分の編集を停止。最終受入は親へ返す。
