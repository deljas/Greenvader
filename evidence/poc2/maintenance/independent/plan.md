# POC2-06 独立検証準備

2026-10-22。親から読取・試験作成だけを許可。backendがGodot/importを専有中のため、**Godot未実行、試験スクリプト未パース、現版の合否判定はしない**。指定作業票 `tasks/POC2_06.md`、AGENTS、初回POC2仕様と独立報告、maintenance/selfの再現sourceとJSON、実装中の実ソースを読んだ。

所有は `tests/poc2/maintenance/independent/**` と本証拠領域。ゲーム・設定・素材・他者差分・共有進捗を編集しない。再委任・commit・OS入力・実カーソル・前面化なし。期限は本日12時JSTで、不要な深掘りをしない。

## 根拠と狙い

- 旧再現: 到達不能になった直後はunreachable、次tickでreturningへ上書き。
- 旧再現: 水35で補給中のスプリンクラーが退避すると、給水へ戻らずwateringに遷移して水34.75へ減る。
- 旧再現: 実combatでhelperのHP0になった同tickに保存すると死体が残り、restoreがinvalid_entity_helpersで失敗。
- 親の静的監査: タイトル由来helpのF5が既存slotを書き換える、設置補給由来helpから戻るとpopupとpauseメニューが重なる。

期待値はPOC2_06の合格条件と既存仕様から導く。新実装のblocked_order/water_taskなどの内部フィールドそのものを正解値として写さず、外から見える待機・補給完了・帰還・資源保存・slot不変を確認する。

## 凍結後一回ずつの少数試験

`logic.gd`:

1. 未知の水面へ命令→探索中は障害非公開→公開後到達不能→複数tick静止。途中JSON保存再開後も待機し、新しい歩行可能な命令で復帰する。
2. 元homeから水辺へ補給に行き、部分補給中に一度だけ脅威で退避。その状態を保存再開し、安全時に100まで補給、帰路でも保存再開して元homeへ戻る。元home・部分水量を保持する。脅威fixtureはworker判断一tickだけに使用し、不完全な敵辞書を保存しない。
3. 未制圧地のガトリンガー（残弾19）とクローバーをそれぞれ実combatで撃破。同tickで配列・占有が解放され、費用/残弾の返還なし。そのtickのJSONをrestoreでき、敵と資源が保持される。

`view.gd`:

4. change_scene_to_packedで通常current_sceneとして起動し、タイトル3ボタン生成を確認する（単純instantiateではtitle分岐を通らないため禁止）。実Save wrapperで専用test slotを作り、タイトル→help→F5でbytes不変。戻るとタイトルだけが表示され、新規開始でplayへ入れる。
5. 設置補給量37→help（補給popupは隠れる）→help要求を追加2回→戻る。補給popup一つ、量37、pause/時計を保持。さらにF1往復一回で崩れない。Esc後の通常F5保存が機能する。

GPU試験はroot.unfocusable=true、Input.parse_input_eventのみ。画像座標にはwindow変換を適用せず、入力注入だけroot.get_final_transformを使用する。専用保存先は `user://poc2_maintenance_independent_20261022`。通常第一弾/第二弾slotへアクセスしない。

## 凍結と報告

親の停止・凍結連絡後に対象manifestと実SHA256、HEAD、第一弾91件を確認。実差分も読む。logic一回、GPU/view一回。実装失敗なら証拠・再現を親へ返し、自分でゲームを直さない。fixture誤りなら原記録を保ち影響条件だけ再取得。元3500秒や全58項目は反復しない。終了後hash一致とGodot process終了を記録して実行権を返却。

現時点: 準備のみ。logic/GPU/保存試験はすべてNOT_RUN。物理入力・全組合せ・広い回帰・楽しさ・最終美術は対象外。
