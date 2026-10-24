# POC3-CROP-PRICING 独立検証

2026-10-24。**独立10 PASS / 0 FAIL、exit 0**。初回失敗・追試なし。限定価格検証で未解決ゲームFAILは確認されなかった。最終受入は親が行う。

## 対象・環境・差分

- 指定・実HEAD `4d4da323affcd35f4a2b6a6acdfa60175a347dd4` + core3ファイルの未コミット差分。`poc2_session.gd`、`plants.gd`、`persistence.gd`の実git diffと現在コードを読んだ。self/freeze.jsonのcore3/自己試験3/protected7のhashは開始時13/13一致、終了後も13/13不変。
- AGENTS.md、tasks/README.md、作業票、TASK_TEMPLATE.md、POC3_SPEC栽培価格、自己報告、自己試験と生結果/ログを確認した。実装者の報告だけで判定していない。
- Windows、Godot `4.7.2.stable.official.ed1daf0bf`、headless / Dummy audio。独立試験1回。APPDATA/LOCALAPPDATAは本証拠内profileへ隔離。import/GPU再走/全回帰なし。
- 既読のGDScript/headless testingスキルを継続適用。SceneTree入口、型注釈、未完走検出、FAIL時非0終了を備えた。
- 変更内容は、同種hp>0の株数からの価格、配置ごとの決済/支払額保持、整数支払額による返還、保存validatorの歴史的支払額許容。UIは既存current_cost参照を維持し差分なし。
- 証拠: before.json / after.json / actual_diff.patch / status_before.txt / status_after.txt。他者の並行差分を復元/編集していない。

## 独立実行結果

`tests/poc3/crop_pricing/independent_logic.gd` を実行。生結果は results.json / logic.log / exit.json。期待値は仕様の十進数例を先に計算して固定し、実装の価格関数を期待値生成に使っていない。

| 条件 | 結果 | 期待動作と観測 |
|---|---|---|
| SAME_KIND_LIVING_IMMATURE_ONLY | PASS | 未成熟スイカ10株に死亡スイカと異種小麦を追加。スイカ現存10/価格196、小麦価格42。死亡・異種をスイカnへ加えない |
| HELPERS_FIXED | PASS | 同種helper複数があってもarmy25/gatlinger30/sprinkler20 |
| CONSECUTIVE_PAYMENT_RECOMPUTED | PASS | 小麦の連続3株は40、42、45。300種から残173、次価格47。40×1.05²=44.1、×1.05³=46.305の切上げを固定期待値に使用 |
| BLOCKED_NO_CHARGE_OR_COUNT | PASS | 占有済セルへの設置拒否。種/現存数だけでなく保存対象の全状態も不変 |
| INSUFFICIENT_NO_CHARGE_OR_COUNT | PASS | 次価格47に残46で拒否。保存対象の全状態不変 |
| REMOVE_PAID42_REFUND8_COUNT_DECREASE | PASS | 2番目の実支払42株の撤去で8返還。残181、現存2、次価格45 |
| DESTRUCTION_REFUND_ZERO_COUNT_DECREASE | PASS | 最初の支払40株をhp0にしてcleanup。残181のまま、現存1/次42。cleanup前から死亡株は価格のnへ数えない |
| JSON_HISTORICAL_PAID_SURVIVES | PASS | 残った3番目株の実支払45を実JSONへ保存復元。全状態一致、実支払45、次価格42を保持 |
| RESTORED_REFUND_FROM_PAID_NOT_CURRENT | PASS | 復元した株を撤去。現在価格42や基本40から逆算せず支払45の1/5=9返還、残190、次価格40 |
| FRACTIONAL_PAYMENT_ATOMIC_REJECT | PASS | 保存支払45.5を拒否し元Session全状態を保持 |

保存試験は隔離 `profile/roaming/Godot/app_userdata/グリーンベーダー/poc3_saves/slot1.json` を実際に書き読みした。旧ユーザー保存を入力に使っていない。敵破壊は既存のhp0→cleanup_defeated経路を代表し、戦闘プレイ全体は実施していない。

## 既存証拠の独立レビュー

再利用した自己証拠は独立実行の10件へ加算しない。自己logic23 PASS/GPU9 PASSの生結果と該当試験ソースを読み、下記を確認した。

| 条件 | 結果 | 根拠・限界 |
|---|---|---|
| スイカn0/5/10/20の120/154/196/319 | PASS（証拠レビュー） | self_logic.gd/prices、logic_results.json。固定十進数期待値を使用。n10は今回独立にも確認 |
| 保存historical1234/返還246、旧基本額、helper支払検査、未使用弾返還 | PASS（証拠レビュー） | self_logic.gd/transactionsと対応生結果。現在nから過去支払を再構築しないvalidator差分も直接確認 |
| 範囲弾予約と購入の種勘定 | PASS（証拠レビュー） | self_logic.gd/reservation、logic.log末尾。12種→射出予約1→clover購入10→追加播種1、残0/播種2/shot消滅。購入を予約後残高へ決済して負額を作らない |
| HUD次価格154 | PASS（既存GPU画像目視） | self/hud_next_cost.pngを実際に開いた。640x360画面右上「設置 ●154」を確認 |
| 一覧の現存5株/次154 | PASS（既存GPU画像目視） | self/list_next_cost.pngを実際に開いた。スイカ行5株/+0.000/コスト154、未成熟も現存数へ含む |
| 撤去後のHUD/一覧同時更新 | PASS（証拠レビュー） | self_gpu.gdとgpu_results.json。撤去後4株/146へ両クライアント更新。撤去後の新画像は今回撮っていない |
| 表現overflow防止 | PASS（静的/既存証拠レビュー） | current_costで有限性/int64変換範囲を確認しINT64_MAXへ表現飽和。購入判定はcost>seeds-ammo、返還は整数除算。通常価格式に新しい上限は追加していない。有効save残高上限1e9で当該価格は購入不能 |

GPU自己実行は共有HEAD2e5ad7e時で、最終freezeはSPRITEコミット後4d4da32。対象core3hash一致をfreeze記録と現物照合で確認した。今回GPU新規実行はしていない。

## NOT_RUN・停止・返却

- NOT_RUN: OS物理入力、通常窓/全照明/全解像度、経済バランス・混植の動機・楽しさ、広い全回帰、書き出しビルド、全戦闘プレイ。
- OS入力/カーソル/前面化/復元操作なし。未知プロセス停止なし。開始前/終了後Get-ProcessでGodot0、override.cfgなし。
- 旧PoC/PoC2保存3件はhashのみ読取りで前後3/3不変。core3を含む凍結対象13件も不変。before.json / after.json参照。
- ゲーム、設定、素材、他者試験、docs、作業票を編集していない。所有のindependent_logic.gdと本証拠のみ追加。Git index/commit/branch操作なし。
- 実行終了済み、以後実行しない。共有Godot/import権は親へ返却済み。受入範囲と未検証項目の最終判断を親へ返す。
