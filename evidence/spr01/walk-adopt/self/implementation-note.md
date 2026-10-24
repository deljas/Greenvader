# SPR-01 通常歩行v2採用の仕上げ

対象は HEAD `151a53f20255489ef08481e2a353258cd8ac559c` と共有未コミット差分。今回は main/input/UI と player manifest、専用自己試験のみ編集。docs・票・actor・素材画素は変更していない。

- `poc_main.gd`: 比較モード変数・比較ボタン・切替関数・F6分岐・HUD案内を除去。actor.poseのmodeを0（採用通常歩行v2）固定にした。
- `poc_input.gd`: F6比較アクションを除去。
- `ui/poc_ui.gd`: 操作説明から比較案内を除去。
- player manifestは比較操作の説明を採用済み通常v2の記述に変更。旧hop sheetと原本/証拠は保存。

確認は `self_adopt.gd` による実GPU1回だけ。Godot 4.7.2、Vulkan Forward+、RTX 5070 Ti。Start-Process -WindowStyle Hidden、root.unfocusable=true、絶対パスlog指定。OS入力・前面化・カーソル操作なし。Input.parse_input_eventによるF6注入のみ。

結果: **4 PASS / 0 FAIL**。実移動で通常v2、F6で表示/位置/時計/位相不変、比較ボタン・HUD/ヘルプ案内・切替関数なし、停止時採用idle。walking.png/idle.pngを取得し、idle画面を目視確認した。右上は停止ボタンのみ。

`target-hashes.json` に今回対象5ファイルhashと保全確認を記録。actor/config/save/water/occlusion、3枚PNGと3import設定の計11ファイルは `preserved-hashes.json` と完全一致。採用walk-normal.pngのSHA256は `9505f78fa58e6e2afa957f25d51e79134bb60c4bdbb0fb486ec005481da38bfc`。

実行ExitCode0。sandbox下で既存user://shader cache作成警告が1件あるが、実GPU描画・試験は完了。新しいimportは行っていない。

NOT_RUN: 物理キーボード/マウス経路、広い回帰・保存/影の再試験、全天候/性能総当り。今回の限定変更では再実施不要という親の指示に従った。美術採用はユーザーが明示済みで、実装者が代行評価していない。

コード凍結、Godot実行中なし。追加作業・コミットなし。
