# POC3-LOCUST 独立検証

2026-10-24。**独立9 PASS / 0 FAIL、exit0**。初回独立失敗・追試なし。今回の代表範囲で未解決ゲームFAILを確認しなかった。最終受入は親が判断する。

## 対象・環境・保全

- 指定/実HEAD `dc2033baed11be964f1fd423da742f6efe0def27` + LOCUST5ゲーム差分。locust_ai全文とcombat/persistence/world_view/town_03の実git diffを直接読んだ。
- self/freeze.jsonのゲーム5/自己試験5hashは開始時10/10一致、終了時10/10不変。project.godotも不変。旧PoC/PoC2実保存3件はhash読取のみで前後3/3一致。ロード/移行/書込なし。
- AGENTS.md、tasks/README.md、LOCUST票、TASK_TEMPLATE.md、POC3_SPECバッタ節、self/report/freeze、実自己試験・生結果・初回ログを確認した。実装者の報告だけを証拠としていない。
- Windows / Godot `4.7.2.stable.official.ed1daf0bf`、headless / Dummy audio。専用profileへAPPDATA/LOCALAPPDATAを隔離。独立実行1回、import/GPU/全回帰再走なし。GDScript/headless testingスキルを継続適用し、型注釈・SceneTree入口・未完走検出・失敗非0終了を備えた。
- 開始時CONTENT-01は完了・共有資源予約なし、Godot0を確認。他者差分に触れていない。Git読取りは--no-optional-locks、index/commit/branch操作なし。
- 証拠: before.json / after.json / actual_diff.patch / status_before.txt / status_after.txt / results.json / logic.log / exit.json。試験はtests/poc3/locust/independent_logic.gd。

## 独立実行結果

| 条件 | 結果 | 仕様からの期待と観測 |
|---|---|---|
| SIX_DISTINCT_NONOCCUPIED_GRASS_TARGETS | PASS | 実新規Sessionの6匹を中央へ置き、中心へ実cloverを配置。6匹すべて別の緑地を予約し、植物占有セルを選ばない |
| STUN_RESTARTS_CONTINUOUS_3_SECONDS | PASS | 対象上で1.5秒食害→stunで進捗0→復帰後2.5秒でも草が残る。壁時計経過だけで完了しない |
| THREE_SECONDS_EMPTY_AND_CLAIM_RELEASE | PASS | 復帰後さらに0.5秒、合計3秒でその1セルをEMPTY、水分0、対象予約解除 |
| GRASS_ONLY_NO_PLAYER_CROP_DAMAGE | PASS | 上記AI進行前後で主人公/実栽培株のHP不変。実diffでもlocustは通常対人/対株_enemy経路を通らない |
| EATEN_CELL_RESEEDED_DRY | PASS | 食害セルをseedへ戻すとmoisture0/growth0。新しい草へ給水状態を継承しない |
| DEATH_BEFORE_COMPLETION_PRESERVES_GRASS | PASS | 別の実個体を対象上で2.75秒食害後にdamage_enemyで撃破。その後草は成熟のまま、予約なし |
| EATING_ORPHAN_JSON_FULL_STATE | PASS | 生産配下だけを残し親巣を実撃破、1.25ゲーム秒食害して実JSONへ保存。復元後全状態一致。親は消失したまま |
| RESTORED_LAST_QUARTER_SECOND_COMPLETES | PASS | 復元後1.5秒で累積2.75秒/草残存、次0.25秒でEMPTY/対象解除。id/source/eat_tileの整数正規化も確認 |
| INVALID_COMPLETED_EATING_ATOMIC_REJECT | PASS | 未完了状態へeat_elapsed=3.0を入れた保存をinvalid_entity_enemiesで拒否し、元Session全状態不変 |

独立期待値は仕様の継続3秒と中断リセットから固定した。AI単体へ大きなdtを入れる代表と、Session.advance_game経由の保存継続を分けて確認。ゲーム実装の計算式を期待値にコピーしていない。中央への配置変更は隔離メモリfixtureのみで、ゲーム配置ファイルは編集していない。

## 既存自己証拠・実差分の監査

以下は再実行せず、自己試験ソースと生結果を照合した範囲。独立9件へ加算しない。

| 条件 | 結果 | 根拠と限界 |
|---|---|---|
| 初期6、休眠、生産20秒、初期込みcap12、欠員のみ補充 | PASS（既存接続証拠レビュー） | self_integration.gdとintegration_results.json。30秒遠隔休眠、接近後19.75秒時6→20秒時12→20秒後12、2匹撃破後2匹だけ補充。combatの生存数集計にinitialを含むlocust分岐と空枠までspawn_countを直接確認 |
| 階級継承と初期/生産/巣報酬 | PASS（実差分/生証拠レビュー） | 初期群れtier1/HP6.5が親から継承。初期報酬floor(1×1.5)=1、生産0、巣45。combat生成/報酬は固定tierを使い現在位置で再計算しない |
| 新巣配置 | PASS（既存接続証拠レビュー） | town_03への追加はsmall locustセル(170,70)だけ。実位置(682,282)、28.644m、歩行可能でnav経路あり。旧最寄巣14.051m/初期敵最短13.606mを維持 |
| 通常射撃/バズーカ/Armyで対処 | PASS（既存接続証拠レビュー） | 内tierはHP5、通常1発。中tier群れのバズーカ排除、Army実攻撃で排除を自己生結果と試験で確認 |
| 草喪失による収入/検知、別検知源 | PASS（既存接続証拠レビュー） | 遠方の実成熟草を食害。land_rate0.02低下、grass由来detected喪失、同地点helperがあれば再検知。検知/収入実装へバッタ専用の別勘定を加えていない |
| 予約解放・対象無効化・ラフレシア誘引・安定侵入禁止 | PASS（既存単体証拠レビュー） | self_unit.gdとunit_results.json。新占有/草消失/actor削除の解放、成熟ラフレシア近傍草への誘引、安定帯を対象/経路から除外。AIはlive zone状態でも経路を再検査 |
| 食害後の孤立小世界100% | PASS（限定訂正追試の証拠レビュー） | regrowth_followup_results.json、15x3/水帯の2陸地、30/30・40ゲーム秒・上限42、乾燥再播種/counters整合。全town_03の100%とは区別 |
| 不正食害state/整数値の保存検査 | PASS（実差分/既存接続証拠レビュー） | eat_tileの範囲/整数型、elapsed<3、phase、source整数、不正時原子的拒否を確認。予約/経路は派生し、保存進捗を維持して再構築 |

## GPU画像の独立目視

**PASS（既存GPU静止画の目視範囲）**: self/eating.pngを実際に開いた。中央草地に6匹のオリーブ色仮表示が離れて見え、各個体を識別できる。640x360で既存場面の草/建物/HUDと共存している。自己GPUソースとgpu_results.jsonは食害phase/6脚/高さ0.48未満の圧縮/最小化維持を確認している。画像hashはafter.jsonへ記録した。

静止画から食害の連続時間の見栄えや、3秒予兆の理解しやすさを合格にしていない。完成素材やtier別外見の承認ではない。独立GPU再走なし。

## 初回失敗の保持

- unit.logの初回SCRIPT ERRORは、typed Array[Dictionary]引数へuntyped空配列を渡したfixture型不備。結果JSONなし、frame limitのexit0をPASSとみなさない。訂正後unit_corrected.log/unit_results.jsonの10 PASSは別走行。
- regrowth_results.jsonは37秒で1/30、1 FAILとして保持。初期stable状態でFarSeedを生成したfixtureでは初期安定地域としてfair sweepを使わない。実Sessionと同じ「生成後stable遷移」へfixture順を訂正した限定追試は40秒30/30で1 PASS。元FAILを上書きせず、ゲームコード修正による条件緩和はしていない。
- 自己の単体10/接続11/再緑化訂正1/GPU4は異なる実行として扱い、独立結果へ合算しない。

## NOT_RUN・終了

- NOT_RUN: 全town_03/全孤立地の100%、広い回帰、全個体長時間プレイ、物理入力、独立GPU再走、連続動作動画/予兆の時間的読みやすさ、楽しさ/緊張感、完成アート、書き出しビルド。全世界100%と広い回帰はINTEGRATIONへ返す。
- ゲーム/設定/素材/他tests/docs/票を編集していない。編集は割当independent_logic.gdと本証拠のみ。他者差分を戻していない。再委任なし。
- OS入力/カーソル/前面化なし。未知プロセス停止なし。開始/終了Get-ProcessでGodot0、override.cfgなし。5ゲーム・自己試験・実save3件不変。
- 実行終了済み、以後実行しない。共有Godot/import権を親へ返却済み。受入の判断を親へ返し停止する。
