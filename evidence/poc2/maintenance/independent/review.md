# POC2-06 独立検証報告

2026-10-22。**限定独立検証は30 PASS / 0 FAIL。今回の受入条件に未解決の実装FAILはない。** 最終受入は親が判断する。

対象: HEAD `151a53f20255489ef08481e2a353258cd8ac559c` と既存未コミット差分。正本は `../freeze-manifest.json`（第二弾全16件、初回受入から変更5ファイル）。実差分 `../self/change.diff`、`../view/main.patch` と現ソースを読んだ。ui/poc2_ui.gdのtitle/pause actionsは型付き配列へのassignになり、以前の実行時型エラーへの修正も確認した。

環境: Windows、Godot `4.7.2.stable.official.ed1daf0bf`。GPUはVulkan 1.4.341 / NVIDIA GeForce RTX 5070 Ti。実行は独立検証者が専有し、logicとGPUを各一回。修正後の再試験は不要だった。旧3500秒試験や全58項目は再実行していない。

## 条件別結果

| 条件 | 結果 | 独立に確認した事実 |
|---|---|---|
| 未知障害を早期公開しない | PASS | 未知の水面へ命令を受理し、`exploring`のまま移動。既知化するまでunreachableを出さない。境界fixtureでknownの切替を制御 |
| 到達不能状態が次tickで消えない | PASS | 障害が既知になった後、複数tickで`unreachable`・停止を維持 |
| 到達不能状態の保存・再開と有効命令での復帰 | PASS | JSON保存復元後も静止。新しい有効な持ち場への命令で復帰し、`guarding`・元位置へ到達 |
| 部分給水中の退避で水・home・補給意図が失われない | PASS | 実際に水辺へ到達し、水35で脅威を一tick与える。`fleeing`へ移行しても水35と元homeを保持 |
| 退避途中と帰路途中の保存復元 | PASS | 退避状態を保存再開し、水100まで補給して`returning_water`へ。さらに帰路状態を保存再開し、元homeへ水100で帰還・作業再開 |
| 植物撃破同tickの保存・復元 | PASS | 残弾19のガトリンガーとクローバーを未制圧地で実combatによりHP0へ。同じadvance内で配列/占有を解放し、直後のJSONを復元できる |
| 撃破時の費用・残弾返還なし | PASS | ガトリンガーの種451、クローバーの種490が撃破前後/復元後で不変。敵一体が復元後も残る |
| 通常current_sceneのタイトル起動 | PASS | `change_scene_to_packed`を使用して本来の_ready分岐を通した。タイトルmenuと3ボタンを生成し、新規開始で停止解除・playへ遷移 |
| タイトル由来helpのF5で既存slotを上書きしない | PASS | 専用の実Save wrapperによるslotを先に作成。タイトル→F1説明→F5でファイルbytes不変。F1でタイトルだけへ戻る |
| 設置補給→help→戻りで一意のpopup・停止・投入量を維持 | PASS | 数量37の補給popupからF1で説明へ。補給popupとpause menuを隠す。help要求をさらに2回与えても戻り先を保持。F1で補給popup一つ、数量37、ゲーム時刻0・pauseを維持。さらにF1往復しても同じ状態 |
| 通常プレイ中のF5が機能する | PASS | popupからEscで戻った後、種432をF5保存。専用slotを読み直して種432を確認 |

詳細: `logic-results.json` / `logic.log` は21 PASS。`view-results.json` / `view.log` は9 PASS。fixture成立のチェックも含む項目数で、30種類の独立したゲーム機能を網羅したという意味ではない。

`supply-after-help.png`を独立に目視した。数量37の設置補給popupが一つ表示され、説明画面・pauseメニューは重なっていない。通常画面の既存景観・ミニマップを保持している。描画確認はこの限定画面だけで、最終美術評価ではない。

## 証拠の扱い

backendの旧再現JSONでは、unreachable→returning、部分給水の退避後watering、水34.75、撃破同tick保存のinvalid_entity_helpersが発生していた。これらの修正前sourceとrawは保持されている。独立試験は実装者のPASS報告だけを採用せず、公開挙動と保存・資源の観察から確認した。

view自己試験の初回2 FAILはtitle/pause menuの型エラーによるもので、`menu-array-checks.json`の限定追試5 PASSがある。独立側でも通常current_scene起動からタイトル3ボタン・help復帰・新規開始を再確認し、未解決FAILとはしない。

## 保全・終了

- PASS: 実行前後の第二弾凍結16件のSHA256一致。
- PASS: 実行前後の第一弾baseline91件のSHA256一致。`freeze-before.json` / `freeze-after.json`。
- PASS: HEAD不変、ゲーム/設定/素材/通常slot/共有進捗は未編集。commit・再委任なし。
- GPUは正規require_escalated承認で実行。`root.unfocusable=true`、入力は`Input.parse_input_event`だけ。実OS入力・カーソル移動・前面化なし。
- 保存先は `user://poc2_maintenance_independent_20261022` だけ。通常の第一弾/第二弾slotへアクセスしていない。
- 終了時Godotプロセス0件。実行/import専有権を親へ返却する。

## NOT_RUN・限界

- 全58項目回帰、3500秒100%の再走、全状態組合せ、全敵との退避経路、全破損保存形式。
- 独立試験の到達不能代表はアーミー。ガトリンガー/スプリンクラーの同分岐と旧保存互換は差分/自己試験証拠の確認にとどめ、独立実行で全種類を反復しない。
- 物理キーボード/マウスからOS経由の入力、配布用export、長時間性能、バランス、楽しさ・最終美術。
- 補給popup確定による設置一回性はこの独立UI試験では反復せず、view自己試験と既存仕様に依存。今回はhelp往復後の一意表示・停止・投入量・通常保存の境界が対象。

限定修正の実行確認を終え、親へ結果を返して編集を停止する。
