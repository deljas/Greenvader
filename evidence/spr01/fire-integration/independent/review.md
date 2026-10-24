# SPR-01 正面発射v3ゲーム組込み・独立レビュー

2026-10-20。対象は共有HEAD `151a53f20255489ef08481e2a353258cd8ac559c` と凍結済み未コミット差分。`self/target-hashes.json` の68件を実ファイルと照合し、実行後も68/68一致。旧素材・設定・保存・発射ルール等の保全baselineは128/128一致した（`target-before.json` / `target-after.json`）。変更前4原稿との実差分、新controller、runtime素材を確認した。最終受入は親が判断する。

環境はWindows、Godot 4.7.2 stable ed1daf0bf、Vulkan Forward+、RTX 5070 Ti。独立logic＋GPUを1回実行し、期待値誤りの2条件だけheadlessで1回再確認した。非フォーカス設定・Hidden起動、エンジン内入力注入のみ。保存先は本証拠下の専用領域に分離した。

## 実行結果と初回失敗の扱い

- **R1: 23 PASS / 2 FAIL**。初回結果は `results.json` と `engine.log` に保持した。
- **R2: 2 PASS / 0 FAIL**。対象は `seed66_input_selection_aim_and_release_origin` と `logical_release_cost_once` のみ。`selection-followup.json` / `selection-engine.log` に実測を保存した。全GPU試験は再走していない。

初回2 FAILは、栽培種を発射した時点で袋の `seeds` が減るという試験期待値の誤りだった。既存の `scripts/play/play_state.gd` の `reserve_plant` は発射時に `reserved_seeds` と飛翔数を増やし、`land_plant` は着地して配置できた場合に袋の種を消費する。変更前session原稿にも同じ予約呼出があり、今回その仕様を変更していない。独立テスト側だけを修正した。

最小再現は、carrotを選び65msまで溜め、kiwiへ選択変更し1px移動して66msへ進める操作。初回の誤期待は袋20→17、実動作は袋20・予約3・使用可能17。R2ではこの既存仕様を期待値とし、発射種carrot、入力時target `(123,82)`、発射時origin `(99,82)`、1回だけの予約と発射を確認した。製品修正を要する未解決FAILは見つからなかった。R1の失敗件数をR2で上書きしていない。

## 条件別判定

| 条件 | 判定 | 確認範囲 |
|---|---|---|
| 種66ms/400ms、水400ms/800ms、溜め中の再入力拒否、発射後recovery中断 | PASS | 独立境界試験。発射/資源予約・消費/音要求の重複なし。音はAPI要求回数で確認し、聴感ではない。 |
| 入力時の種/aim保持、発射時origin、移動継続 | PASS | R2の栽培種実測とR1のゲーム入力・移動・通常種発射。 |
| 資源0・弾上限・無効点の開始拒否、発射時再確認 | PASS | 不足や満杯のまま発射せず、再試行による二重発射なし。 |
| pause/menu/viewpoint停止、death/load/newgame取消 | PASS | 専用セーブを含む主要経路でpendingの残留発射なし。 |
| 全方向aimと正面共用、終了後の歩行/静止復帰 | PASS | 4方向の論理aimは保持、発射中は正面、終了後は既存4方向素材へ復帰。 |
| 640表示、24×36原画、足元と影texture同期、形成→飛翔 | PASS | 実texture/pose検査と実GPU画像。水399msの大玉保持、400msの表情と分離、種66msの弾き粒を確認。 |
| 即時API・保存形式・既存発射ルール保全 | PASS | `session.fire` の即時発射を直接確認。保存/弾道ルール等の実差分と128件hashを確認。 |
| 凍結版の保全・プロセス終了 | PASS | 対象68件・保全128件とも不変。終了後Godotプロセスなし。 |
| 物理入力、連続再生の印象、楽しさ/美術採用 | NOT_RUN | OS入力は使用していない。正面共用は全方向完成アートの採用を意味しない。 |
| 旧即時main入力前提の全回帰、全天候・性能・書出し | NOT_RUN | `main.click_fire` はpending受付へ契約変更された。旧 `tests/poc/play/*` 等の即時発射前提試験は実行/改造せず、今回の独立入力・action・音要求試験に限定した。 |

GPU目視は独立取得の `water399.png`、`water400.png`、`seed66.png`、`walk_return.png`（各640×360）を確認した範囲。重大な表示崩れは認めなかった。起動ログにはsandboxの既存 `user://` shader-cache作成エラーがあるが、実GPU描画と証拠保存は完了した。

証拠は `results.json`、`selection-followup.json`、4画像、各ログ、`target-after.json`。実装・素材・共有文書は変更せず、独立テストと本証拠のみを編集した。追加実行は終了し、Godot実行資源を親へ返す。
