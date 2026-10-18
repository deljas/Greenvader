# POC-04 自己検証報告（親が実装担当の返却本文から転記）

実装担当（Sonnet 5.5）の返却本文を親（claude-20261018-poc-opus）が要約転記した。合否は変更していない。

- 対象: HEAD 9901370＋既存未コミット差分＋scripts/poc・data/poc・tests/poc（未追跡）。scripts/enemy・world・play・data直下は未変更。
- 変更: poc_session.gd（load_combat: EnemyField/ZoneProgress/EnemyCombat/FarSeedSimを接続、順序 clock(growth→spread→far)→play→enemies→projectiles、rng_seed 20261018）、poc_main.gd（`-- --combat`で戦闘fixture、HUD・通知）、assets/placement.gd（reach_seeds、既定空）、新規 combat/poc_enemy_view.gd、data/poc/combat_setup.json、data/poc/maps/fixture_04.json、tests/poc/combat/logic.gd・gpu.gd。
- 命中順: 壁→敵→地面。壁の向こうの敵には当たらない。命中した弾は着弾しない。水は敵を通過。
- 100％上限: `far.completion_bound_seconds()` = (sweep_delay 120s + 1tick) + (lap_steps_bound 20 + 1)×掃引周期5s + 最遅発芽≈11s = 237.0s。実測: 安定93.5s、100％到達285.0s（安定後191.5s、上限内）、greened 1170/1170厳密一致、資源・入力不使用。
- 結果: logic 48 PASS / 0 FAIL、GPU 7 PASS（640、戦闘中・安定直後・100％後）、回帰 poc base 40 / assets 45 / play 69 PASS、旧p2_01〜05_checks失敗0。p2_06系はNOT_RUN。
- 注意: GPU撮影ではボアを手前へ移動・静止させた（湧き・移動の証明ではない）。戦闘ボットのシナリオのみcontact_damage=0。
- NOT_RUN: 物理入力、実1080p窓、960での敵表示、POC-01〜03 GPUの再実行、長時間実時間プレイ。
