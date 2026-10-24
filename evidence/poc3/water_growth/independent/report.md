# POC3-WATER-GROWTH 独立検証

2026-10-24。限定ロジック検証の事実を返す。最終受入は親が判断する。

## 対象と環境

- 指定基準 `119efb5fdf5f397e9288748b477aca45038cb56e` + self/freeze.json のゲーム5ファイル。実HEADは `6364f290b9bdd9181c21816df370cbb3a98eaf4a`。後者のコミット差分は `.claude/README.md` の記録のみであることをgit showで確認し、親がこの対象版での継続を指示した。
- Windows / Godot `4.7.2.stable.official.ed1daf0bf`、headless、Dummy audio。共有作業ツリー。CONTENT-01票の別sandbox予約を確認してから実行。Godot importは実施していない。OS入力、カーソル操作、前面化は実施していない。
- AGENTS.md、tasks/README.md、本票、TASK_TEMPLATE.md、PoC3仕様の給水・草地・スプリンクラー条件と関連資料を読んだ。self/actual_diff.patchと実git diffを直接読み、凍結内容hashを照合した。実装者の結論だけを証拠にしていない。
- ゲーム5、自己試験3、protected5のhashは開始時freezeと一致、終了時も13/13不変。実ユーザー旧保存3件はhashのみ読み、ロードせず、前後3/3不変。before.json / after.json参照。
- APPDATA/LOCALAPPDATAは本ディレクトリのprofile配下へ隔離。実JSONは `profile/roaming/Godot/app_userdata/グリーンベーダー/poc3_saves/slot1.json`。旧保存は試験へ入力していない。
- CIMプロセス一覧はアクセス不可。代わりにGet-Processで確認し、開始前と終了後のGodotプロセスは0。未知プロセスは停止していない。process_before.json / after.json参照。

## 独立実行結果

初回は **11 PASS / 1 FAIL**、失敗条件だけのハーネス修正後追試は **1 PASS / 0 FAIL**。異なる走行を合算した件数では表現しない。最終的に下記12条件の未解決FAILはない。初回results.jsonとlogic.logは保持している。

| 条件 | 最終結果 | 独立した期待と観測 |
|---|---|---|
| CROP_PROGRESS_REPEAT | PASS | 小麦T=45秒。18秒dryで進捗9秒、初回給水後36秒で成熟。11秒後の追水による上積みなし。44.5時未成熟、45時成熟を確認 |
| CROP_REPLANT_DRY | PASS | 成熟給水株を撤去し同セルへ再植付。age=0、watered=false |
| GRASS_PARTIAL_PENDING_LAG | PASS | 地力0・日照1・手播きは給水30秒、dry60秒。7tick=3.5秒時に3tick未処理の草へ給水。精算進捗3500、以後2秒で7500。遡及加速なし |
| GRASS_REPEAT_NO_EXTRA_SWEEP | PASS | 給水済み草へ追水。変更件数0、無関係な草の未処理tickを精算しない、給水状態維持 |
| GRASS_EATEN_REGROW_DRY | PASS | stageをEMPTYへ食害降格した直後に水分0・active除去、新しいseedは進捗0・dry |
| LEGACY_OPT_IN_FALSE | PASS | 新規WorldStateの旧モード既定false。1tickの旧dry増分1000、一時水分100→99を維持 |
| SPRINKLER_CROP_FIRST_WET_SKIP | PASS | 近い給水済cropと直下dry grassを置いても、離れた未給水cropを選択 |
| SPRINKLER_ONE_CHARGE_RESELECT | PASS | 0.75秒の初回有効散水で水6→5、crop/grassへ給水。再選択は仕事なし、次回で水5を維持 |
| JSON_SAVE_IMMEDIATE_DAMAGE | PASS | 実Sessionで4草・処理予算1・1.5秒後に先頭草を食害降格。次tick前の実JSON保存/復元で全状態（active/order/lag含む）一致 |
| JSON_SAME_TICKS_CONTINUATION | PASS（限定追試） | 両GrowthSimの処理予算1、同じ2秒進行後に全状態一致。追試証拠continuation_followup.json/log |
| WATERED_NON_BOOL_ATOMIC_REJECT | PASS | watered=1（bool以外）を拒否し、元Session全状態は不変 |
| MIGRATION_EQUAL_CLOCK_DRY_GRASS_WET | PASS | 作業版保存のmissing watered、wet_until==saved clockはdryへ移行。正moisture=1の成長草は100へ移行し、成長順とlagは維持 |

独立試験の初回FAILは製品不具合ではなく比較時の設定誤り。復元Sessionの `sim_tuning` と復元GrowthSimの `tuning` は別Resourceであり、最初は前者のみに処理予算1を設定していた。実GrowthSimの予算が一致せず、分割処理順が異なった。実装を変更せず、後者へ同じ予算を設定して当該1条件だけ追試した。初回再現は independent_logic.gd の `loaded.session.growth.tuning.max_growth_tiles_per_tick = 1` を旧試験行 `loaded.session.sim_tuning.max_growth_tiles_per_tick = 1` とした比較。これは試験コードの不備で、ゲームFAILとして親へ誤確定していない。

## 再利用した自己証拠と差分レビュー

以下は再実行せず、実試験ソース・生結果・ログと関連実差分を読んで確認した範囲。独立実行件数へ加算しない。

| 条件 | 結果 | 根拠と限界 |
|---|---|---|
| 設定T=20/15/45/30/90、スイカdry180/wet90/60秒dry後残60秒 | PASS（証拠レビュー） | self_logic.gd/crops、logic_initial_results.jsonとlogic_initial.logの対応するPASS。現在実CATALOG値も直接確認 |
| 草dry60/wet30、荒地/成熟草への水は事前給水なし | PASS（証拠レビュー） | self_logic.gd/grassと生結果。set_moistureのstage制限・成熟時clearを実差分で確認 |
| 孤立地を含む自動100%、自然発芽先dry | PASS（小世界の証拠レビュー） | 15x3の水帯で2陸地を分離、30/30 targets、上限30秒内。self初回の該当PASSは後続teardownエラー前に出力済。全224x224は未確認 |
| 半速後の100%上限式 | PASS（静的レビュー） | spread.hop_boundとfar.slowest_greened_ticksはtuning.moisture_growth_minを参照、PoC3の0.5を反映。自然倍率・処理待ちも含む。共通式ファイルは無変更 |
| 保存時wet_until>clockのmissing watered移行、成熟/荒地のmoisture除去 | PASS（証拠レビュー） | self/save_followup_results.jsonの移行PASSとself_logic.gd/save_cases。実restore/growth.load_dictの検証後正規化を確認 |
| 日照provider経路の成熟clear | PASS（証拠レビュー） | self_followup.gdとcontinuation_results.jsonの対応するPASS。新しい独立試験では常時日照1の通常経路 |
| headless通常入口起動 | PASS（既存証拠レビュー、終了残存は既知） | self/startup.log、親記録exit0。終了時ObjectDB37/resource20あり。独立ロジック実行では新しいSCRIPT ERROR/ERRORなし |

自己試験の履歴も分けて保持する。初回18 PASS / 3 FAIL、保存限定修正後4 PASS、継続3 PASSは異なる実行。self初回のSpreadSim.close不存在によるteardownエラーもログに残る。初回PASSを現在の保存追試や独立結果へ機械的に合算していない。修正後ゲーム5hashで今回の保存境界を独立実行した。

## NOT_RUNと終了

- NOT_RUN: GPU実画面、給水の描画表示、物理入力、書き出しビルド動作、広い全回帰、全224x224での長時間100%、楽しさ・最終バランス。
- 食害は既存WorldState.set_stage(EMPTY)で代表。未実装バッタの実戦行動は対象外で未実行。
- ゲーム、設定、素材、他の試験、作業票、共有進捗文書を変更していない。Git index/commit/branchの操作なし。追加/編集は `tests/poc3/water_growth/independent_logic.gd` と本証拠ディレクトリのみ。
- 実行停止済み、終了時Godot0。共有Godot/import権を親へ返す。新規ゲーム不具合は確認されず、受入範囲と未実施項目の最終判断を親へ返す。
