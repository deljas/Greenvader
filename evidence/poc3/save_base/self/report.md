# POC3-SAVE-BASE 自己報告

- 対象版: HEAD `aecdf159ea46ba058d10ff18f785f4fa15fafde3` + 指定4ファイルの差分（8行置換）、限定自己試験2本。`results.json` のcontextに最終SHA256を記録。
- 変更: `save/poc2_save.gd` の既定保存先を `user://poc3_saves`、外包形式を `greenvader_poc3_1`。`simulation/persistence.gd` のcapture/restore両側を内包 `greenvader-poc3` / version 3へ。`poc2_main.gd` と `ui/poc2_ui.gd` の窓/タイトルを「PoC3 作業版」へ。コードパスは維持し、WorldState/マップの別スキーマ番号、保存ファイル名、ゲームルール、描画設定は変更なし。
- 自己検証: CONTENT-01共有資源なし/Godotプロセスなしを実行直前確認。APPDATA/LOCALAPPDATAは自己証拠配下の `profile/` に隔離。Godot 4.7.2 import 1回 exit 0、エラーなし。
- 保存の主要条件: 8 PASS / 0 FAIL。隔離profile必須、旧slotがあっても新Sessionの種60/新slot未作成、新保存の状態往復一致、外包/内包の新形式、旧外包拒否、旧内包の直接restore拒否、不正state拒否と現行保存状態不変、旧fixture一覧/内容不変。各条件1回。旧fixture種987と新規種60を区別し、旧進行を採用していないことを確認。詳細は `results.json` と `logic.log`。
- 実ユーザー保存: 実APPDATAの旧PoC slot.json、PoC2 slot1.json/.bakの3件は一覧/サイズ/SHA256が前後一致。試験から実ユーザー保存への書込/読込操作なし。比較hashは `results.json` のcontext。
- GUI: 実GPU Forward+/Vulkan RTX 5070 Tiで窓title/UI版表示、タイトル停止、新規状態の種60、新保存先を確認。`title.png` の日本語版表示を目視し、切れや崩れなし。
- フォーカス制約の限界: 初回は_initでroot.unfocusable=trueにしていたが、起動後の値falseを検出（版表示自体はPASS、focus guardはFAILとして別記録）。自己probeのrun冒頭にも設定を加えたGUI限定追試はexit 0、起動後の値true。親の停止連絡受信前に追試は終了済み。起動瞬間のフォーカス奪取防止は立証できず未確認。明示的な前面化/復元/OS入力/カーソル操作APIは使用していない。初回は `title_initial.log`、追試は `title.log`。両結果をresults.jsonに別記し合算しない。親の停止指示後はGUI追加なし。
- 終了: Godotプロセス0件。子の編集/実行停止。共有文書/作業票は未編集。
- NOT_RUN: 物理入力、起動瞬間の非前面化保証、各ゲーム機能の広い回帰、長時間、全照明/全ウィンドウサイズ。旧進行の移行は仕様対象外。
- 付随生成: importで `tests/poc3/source/independent_entry.gd.uid` が未追跡生成。割当外なので削除/変更せず保持し親へ連絡。
- 文書担当へ: 通常入口はrun_game.batを維持、内部poc2パスは共通コード名のまま。現行表示はPoC3作業版、新保存はpoc3_saves/slot1.json（.bak/.tmp方式継続）、旧進行の移行なし。PoC3新機能の完成やプロジェクト全体の受入を意味しない。
