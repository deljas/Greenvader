# POC3-ENEMY-TIERS 独立検証

2026-10-24。**独立9 PASS / 0 FAIL、exit0**。初回独立失敗・追試なし。指定範囲で未解決ゲームFAILを確認しなかった。最終受入は親が判断する。

## 対象・環境・保全

- 指定/実HEAD `e7d86a5adedf3a221fe90b88be099a4b530bfb98` + combat/persistenceの未コミット差分と新規enemy_tiers.gd。2coreの実git diffと新規部品全文を直接読んだ。self/freeze.jsonの対象3/自己試験4/protected5は開始時12/12一致、終了時12/12不変。
- AGENTS.md、tasks/README.md、ENEMY-TIERS票、TASK_TEMPLATE.md、POC3_SPEC階級、self/report/freeze、実試験と生結果/診断ログを確認。実装者の説明だけで判定していない。
- Windows / Godot `4.7.2.stable.official.ed1daf0bf`、headless / Dummy audio。独立実行1回、GPU/import/全回帰なし。GDScript/headless testingスキルを継続適用し、型注釈・SceneTree入口・未完走検出・失敗非0終了を備えた。
- APPDATA/LOCALAPPDATAは本証拠内profileへ隔離。CONTENT-01の別sandbox予約を確認。旧PoC/PoC2保存3件はhash読取だけで前後3/3不変。旧保存ロード/書込/移行なし。
- before.json / after.json / actual_diff.patch / status_before.txt / status_after.txtに版・実差分・hash・状態を記録。独立試験はtests/poc3/enemy_tiers/independent_logic.gd、結果はresults.json / logic.log / exit.json。

## 独立実行

| 条件 | 結果 | 仕様からの期待と観測 |
|---|---|---|
| EXACT_18_32_METRE_BOUNDARIES | PASS | 原点(400,400)から負方向17.95mは0、18m等値は1、32m等値は2。0.1m/logic pxで独立に指定 |
| INITIAL_OFFSPRING_PARENT_TIER | PASS | 初期配下すべてが親固定tierを保持。近小巣tier0/HP40、遠大母tier2/HP408 |
| MIDDLE_STRONG_REWARD_FLOOR | PASS | 実damage_enemy経路で中strong初期個体を撃破し報酬22。15×1.5=22.5の切捨てを固定期待値に使用 |
| MOVED_MOTHER_PRODUCES_FIXED_OUTER_TIER | PASS | 遠母を開始地点へ移し主人公も移動した後に生産。母はtier2、配下tier2/HP34/initial=false。現在位置から再判定しない |
| MOVED_MOTHER_REWARD_STAYS_400 | PASS | 中央へ移った遠大母の実撃破報酬は400。子は消失母のsource idを保持 |
| JSON_FULL_STATE_WITH_MISSING_PARENT | PASS | 親消失・子生存の実JSON保存復元で全状態一致、親は復元されない。型正規化を含む保存境界を実行 |
| RESTORED_ORPHAN_FIXED_TIER_ZERO_REWARD | PASS | 復元子はtier2/HP34。実撃破経路で残高増分0。報酬は現在位置・親存在から再計算しない |
| FRACTIONAL_TIER_ATOMIC_REJECT | PASS | tier0.25のenemy保存をinvalid_entity_enemiesで拒否、元全状態不変 |
| BOOL_ZERO_TIER_ATOMIC_REJECT | PASS | nestのtier=falseを数値0とみなさずinvalid_entity_nestsで拒否、元全状態不変 |

期待値の生成に実装の倍率計算関数をコピーしていない。代表の生報酬とJSON境界を重点確認し、倍率表の総当たりは再実行していない。位置変更は隔離Session内のfixture操作であり、ゲームデータを編集していない。

## 再利用した証拠と差分レビュー

自己のpure18 PASS、初回統合20 PASS/1 FAIL、保存限定1 PASS、validator限定6 PASSは別々の履歴として保持し、独立9件へ加算しない。

| 条件 | 結果 | 根拠・限界 |
|---|---|---|
| HP/攻撃/報酬の全3帯倍率とfloor | PASS（既存証拠レビュー） | self_pure.gdとpure_results.json。基本HP20/40/100/240、攻撃5/12/10、報酬6/15/30/80/200の明示期待値。pure部品の倍率配列も仕様表と直接照合 |
| 地形補正後の配置点と固定start | PASS（実差分/既存fixtureレビュー） | add_nestはfree_position後にs.start_position()との距離を確定。self corrected_combatの補正位置fixtureと統合PASSを確認。現在の主人公位置は使用しない |
| 実加害の倍率接続 | PASS（既存証拠レビュー） | self_integration.gd/attacksとintegration_initial_results.json。中crop/helper6、遠主人公7、遠boar突進16.8、遠母接触14を実分岐で確認済。今回独立は報酬経路を実行 |
| 移動中live母の保存固定、missing tier互換 | PASS（既存証拠レビュー） | self初回の対応PASS。旧作業版missing tierは0で元能力維持、現在位置から再配置しない。旧PoC/PoC2保存を読み込む処理ではない |
| 不正tier/HPの検査 | PASS（最終版の既存限定追試レビュー） | validation_followup_results.jsonのtier1.5/3/-1/string/boolとmax_hp不一致の6条件PASS。validatorは数値型を確認してfloat候補0/1/2と厳密比較、合格後intへ正規化 |
| 非対象の速度・予兆・生産・表示の不変 | PASS（静的差分レビュー） | combatの変更は配置tier/HP/加害/報酬、persistenceはtier検証/正規化。移動speed、予兆時間、回復時間、spawn interval/capの定数は無変更。view/UI/画像に対象diffなし。実画面の再確認とは区別 |

自己初回のJSON失敗は隠さず保持する。期待は親消失の子を含む保存往復、実際はJSON float0.0がint候補membershipへ一致せずinvalid_entity_enemiesで復元拒否。self/integration_initial_results.jsonとsave_diagnostic_rejection.logへ記録されている。最終validatorの数値型確認後float候補比較、save_followup.logの `type=float / int_membership=false / normalized_membership=true`、限定1 PASSを照合した。今回の独立JSON全状態一致でも修正後境界を確認した。

診断中のtyped Arrayへのuntyped Array代入エラーはsave_diagnostic_harness_error.logに保持された試験側不備。製品修正の根拠やPASS件数に含めていない。これらは過去の失敗履歴であり、現凍結版の未解決FAILとはしていない。

## NOT_RUN・停止

- NOT_RUN: GPU/実画面、物理入力、全敵の長時間移動/戦闘、難易度/楽しさ、全回帰、書き出しビルド。
- ゲーム/設定/素材/他者試験/docs/作業票を編集していない。所有のindependent_logic.gdと本証拠だけ追加。Git index/commit/branch操作なし。他者差分の復元なし。
- OS入力/カーソル/前面化なし。未知プロセス停止なし。開始/終了Get-ProcessでGodot0、override.cfgなし。対象hashと旧保存の保全はafter.json参照。
- 実行終了済み、以後実行しない。共有Godot/import権を親へ返却済み。未検証範囲と限定受入の最終判断を親へ返す。
