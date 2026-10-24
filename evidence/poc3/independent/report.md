# POC3-VERIFY 最終独立確認

2026-10-24。**最終独立の新規実行8 PASS / 0 FAIL、native exit0、stderr空。** 主要な技術完了条件は以下の独立実行・有効な機能別証拠・統合生証拠の監査で確認し、未解決の主要FAIL/NOT_RUNは確認されなかった。最終受入・コミット・文書確定・試遊引渡しの判断は親へ返す。全条件の新しい一式再走や、楽しさの合格ではない。

## 対象・環境・保全

- 実HEAD `f8fd0035e566e241c0abf48b3b2165d48f76e1fd` + `integration/self/freeze_after.json` のmain終了/Walker EPS差分。実diffはこの2ゲームファイルのみ。準備中の対象は未凍結として区別し、親の最終実行許可・実装停止/実行権移譲を受けて実施した。
- Windows / Godot `4.7.2.stable.official.ed1daf0bf`、headless / Dummy audio。新規独立実行1回。APPDATA/LOCALAPPDATA/user_dataは `evidence/poc3/independent/profile/` へ隔離。
- freeze_afterの18件（ゲーム/設定11、自己試験7）は開始時18/18一致、終了時18/18不変。旧PoC/PoC2実save3件はhash読取だけで前後3/3不変、旧saveのロード/移行/書込みなし。final_before.json / final_after.json参照。
- 編集は所有 `tests/poc3/independent/final_check.gd` と本証拠のみ。ゲーム/他test/docs/票/Git index/commit/branchを変更しない。他者CONTENT等の成果を戻していない。Git読取は--no-optional-locks。
- OS入力/前面化/カーソル/未知process停止なし。GPUの新規実行なし。開始/終了Godot0、overrideなし。実行権は結果取得後先に親へ返却済み、以後実行しない。
- 仕様/票/TASK_TEMPLATEと機能別証拠の読取経緯はpreparation.md。最終self/report、actual_diff、freeze、各raw結果/実試験、最終GPU画像を読み、実装者の説明だけで判断していない。

## 新規独立実行の8条件

生結果はfinal_results.json、final.stdout.log、final.stderr.log（0byte）、final.exit.json（native_exit0）。Godotスクリプトは型注釈・未完走検出・失敗非0終了を備える。実装の期待値を写さず、元の失敗座標と仕様の拒否/保存/入力条件を基準にした。

| 条件 | 結果 | 直接観測 |
|---|---|---|
| FORMER_NORTH_STEP9_NOW_PASSES | PASS | 元FAIL直前logic(461.9998,418.0002)から実Session.walkで目標(462,414)へ移動し(461.9998,413.9998)へ到達、誤差0.01px未満 |
| WATER_CONTACT_REMAINS_BLOCKED | PASS | 水際(450,418)から水方向へ実歩行しても(450,418)を保持。EPSを広げて足が水へ抜けない |
| FINAL_COMPOSITE_JSON_FULL_EQUAL | PASS | 実設置clover2株/給水/helper/お気に入り/播種幅/残存敵階級等の組合せを実JSONへ保存、復元後全保存状態一致 |
| HISTORICAL_PAID_WATER_FAVORITE_WIDTH_NO_OFFLINE | PASS | 株支払10/11、watered、Sprinklerお気に入り、幅3、時計と株年齢を保持。復元時に壁時計分を進めない |
| SAME_TICKS_AFTER_FINAL_RESTORE | PASS | 元/復元Sessionを各0.5ゲーム秒進め全保存状態一致。読込後のsystem接続を確認 |
| NORMAL_ENTRY_LIST_STOPS_TIME | PASS | project main_scene経由で新規開始、engine内E入力で一覧。main.tickしてもSession時間停止 |
| FINAL_UI_HELD_PRESS_DOES_NOT_FIRE | PASS | 一覧内で押した左ボタンを保持したままEで閉じても、通常tickで射撃/種消費なし、_primary未作動 |
| NORMAL_EXIT_RELEASES_SYSTEM_OWNERSHIP | PASS | main.freeによる本来_exit_tree経路を実行。手動session.closeで隠さず、combat/plantsのSession参照、tile_listener、clock接続が解放されることを確認。終了stderr空 |

複合保存のSprinkler解放だけは明示的fixtureとし、解放経路の証拠には使っていない。資源は初期60から実価格で決済。自然な解放/攻略/投資の成立は後述の別journey証拠で確認する。

## 主要完了条件の監査結果

機能別件数や自己件数を新規8件へ合算しない。準備時の機能hash不一致は後続機能変更を意味するため、受入コミット以降の関連差分を確認した。reuse_audit.jsonで8つの中核scopeに変更がないことを独立にGit照合。最終未コミット差分2件は移動と終了だけで、全世界成長/戦闘倍率/価格/保存/入力状態機械を変えていない。

| 主要条件 | 結果 | 根拠と再利用範囲 |
|---|---|---|
| 通常入口一本・新規開始 | PASS | run_game.bat→project main_scene→poc2_mainを静的追跡、独立main起動と最終new_start画像。SOURCEの入口/履歴保全証拠も再利用。OSダブルクリック経路の代行ではない |
| 新規→開拓/化石/複数前線/攻略/投資 | PASS（統合生証拠監査） | self_journey.gd/10Pのtraceを読む。実歩行でcarrot化石、近巣へfire3+bazooka1で撃破/Army解放、Gat/Sprinkler化石、北前線接触、中央帰還、実収入残高でcarrot+3helper、JSON全一致/続行。HP/種/unlocked/地形/位置の直接注入なし。全敵を人間が攻略した証拠とは区別 |
| 草/栽培の給水・途中進捗・乾燥再生 | PASS | WATER独立とLOCUST独立、HELPERS給水連携を再利用。growth/world_state/spread/farはwater受入a63487dから不変。最終独立にも給水/成長/保存を含む |
| 幅播種・着弾決済・価格/実払返還 | PASS | AREA独立9P、PRICE独立10P、HELPERS個体弾分離証拠。seed_areaは119efb5から不変、価格/返還処理は後続地域変更でも保持。最終coreの幅3実着弾9種決済、独立のpaid10/11保存を確認 |
| 植物UI/お気に入り/入力分離 | PASS | PLANT-UI/INPUT独立を再利用。input_latchは5f7ac13、plant widgetsは9d54a6dから不変。main後続差分はAREA/HLP表示と終了、入力分岐を変えない。最終独立E保持、統合GPUのTab保持漏れ/停止も確認 |
| 地図の検知/記憶/接近回収 | PASS | MAP-INFO原FAILとmemory_fix4Pを分離して再利用。camera_geometry不変、_remember_discoveries/生存helper/草検知を維持。LOCUST食害の検知喪失/別検知源とjourneyの化石接近回収/保存で接続確認 |
| 中央開始/地域免疫なし/移動 | PASS | WORLD独立とLOCUST配置証拠、177草/中央112/1地域を保持。旧WalkerFAILは原ログを残し、自己4限定追試・独立北/水対照・journey実移動で修正影響を確認 |
| 固定tier・後生産報酬0 | PASS | ENEMY-TIERS独立9P/LOCUSTの初期1・生産0/親継承、TiersとLOCUST AI中核不変。HELPERS攻撃対象情報/個体弾を加えた後も報酬処理は変更なし |
| バッタ食害/分散/占有/非攻撃性 | PASS | LOCUST独立9Pと自己cap/安定/誘引/検知証拠。AIはa97fbcdから不変。HELPERSはArmyで草を保護する有無比較に接続 |
| helpers仕事/資源/退避/待機と比較 | PASS | HELPERS独立10P、自己Gat播種0/2、Sprinkler水0/1・年齢3/5.875、Army食害0/4。helper gameplay7ファイルは4550123から不変。反射/終了変更で仕事を変えない |
| 種/水切れでも進行 | PASS（自己core監査） | 種0でfire拒否後20秒の実生産で1へ、給水済株成熟、水0で給水拒否後に実bank更新で20補給。明示資源枯渇/岸配置fixtureと自然探索を混同しない。通常dry成長は別WATER証拠 |
| 安定後の再侵入/再出現なし | PASS | coreの実damageによる全排除→通常更新で安定→hostile route空→100%後も敵巣空。LOCUSTのlive stable route検査も再利用 |
| 孤立地込み入力なし正確100% | PASS（全map生証拠監査、再走なし） | 自己coreで38330/38330、孤立0/16→16/16、cleared/counters一致、2401ゲーム秒/上限3207.5。120秒固定clock20回で元growth/spread/far信号を維持、播種/成長値変更なし・入力/直接stage書込0。省略は敵不在combat/income/reveal/未設置helper/crop。2つの最終修正はこの成長条件に影響しない |
| 新状態の保存・終了中進行なし | PASS | 各機能の不正値原子的拒否/旧形式拒否/特殊shot/orphan進捗証拠、最終journey全JSON一致、独立複合保存/同刻み再開/時間不増。旧保存を移行する処理はない |
| 正常終了と残存解消 | PASS | 元39 ObjectDB/21resourceのログを保持。自己限定終了native exit0/stderr空、独立main解放後native exit0/stderr空。過去37/20履歴も削除していない |
| 代表GPU/反射・640 nearest | PASS（実画像監査） | 以下の最終画像とメタデータを直接確認。新規独立GPUを実行した件数ではない |

## 最終実GPU画像の独立目視

実際に開いた画像7枚とhashはfinal_after.json。

- new_start.png: 中央円形緑地/水路/主人公、5枠、種60を確認。
- map_helpers.png: クォータ向きの地形と現位置/helper表示、Tab閉じる案内を確認。全域開示を要求せず探索済み範囲と区別。
- plant_list.png: clover株1/未成熟生産+0.000/次11、Army25/Gat30/Sprinkler20と生産なし、5枠・右上HUDを確認。草上の株と個体も背景に見える。最終mask差分版の画像として再利用。
- water_followup_0/2/3/5.png: 西岸の水面側に顔/葉の鏡像を確認。歩行/反転の代表で極端な潰れ・位置飛び・消失は見られない。

反射は実Session.walk DOWN3/UP3、0.08秒×6=0.48ゲーム秒。water_followup_results.json/self_gpu.gdの時系列・walking・frame変化・matching_feet/flip/texture・640反射を照合した。これは短い実歩行時系列の代表確認で、全時刻/角度/全動画frameのちらつき保証ではない。元の南岸/北橋岸の撮影成功は目視根拠不足として保持し、最終西岸証拠へ置換の理由を確認した。

共通Water/Actor/shader/Cardを変えず、PoC3コピーtuningだけdivisor1。反射以前の2/1比較で粗さ改善を確認済み。CPU同期force_draw中央値0.358msをGPU専用時間/全mapfps保証にしない。

## 原失敗・実行ハーネスの履歴

- core14P1Fの北step9原失敗を保持。EPS1e-4→5e-4px以外の足幅/速度/substep変更なし。自己4Pは別追試、独立元座標/侵入拒否は別の新規2条件で再確認。
- HELPERS初回idleFAILと修正後5P/marker1P、機能別の型/保存fixture失敗も各報告のまま保持。HELPERS独立件数は10P（自己報告中の旧9P表記を技術結果へ採用しない）。
- 自己のmovement/journey/gpu/startup_after_fixにnative exit=nullの早期process-handleハーネス記録がある。raw完走JSONとstdout/stderrを監査し、native exit0と読み替えない。以後の西岸GPU・終了限定追試はexit0で記録。今回独立は直起動のLASTEXITCODE0とstderr空を別取得。
- 自己GPUのnotify_mouse_entered重複WARNINGは試験通知由来、ゲームERROR/残存の解消と区別。独立stderrには同警告もない。
- 全map100%/journey/機能別一式を再走していない。条件を緩めて原失敗を隠していない。

## 残すNOT_RUNと親へ返す事項

主要な技術完了条件の未解決FAIL/NOT_RUNは本代表確認範囲ではなし。以下は合格へ読み替えず、試遊時の限界として残す。

- 物理マウス/キーボード→OS→Godot経路、batのOSダブルクリック操作。
- 長時間の人間プレイ、楽しさ/難易度/最終経済バランス、全敵を通常操作だけで攻略する走行。
- 全時刻/天候/角度/窓サイズ/素材/障害物の総当たり、他GPU・全map GPU専用性能、完成アート、書き出しビルド。
- 新しい独立GPU再撮影と全回帰一式（有効な既存証拠を再利用）。

最終ガイド/既知制約文書の確定と機能/統合コミットは親・文書担当の引渡し作業であり、独立担当は共有docsを編集/確定していない。通常入口とガイドの操作/保存先は実挙動に整合する範囲を読取確認。古い「統合自己確認中」等の進捗表現を最終受入後に更新する責任は親へ返す。

実行/編集停止。freeze18件/旧save3件不変、Godot0、overrideなし、runtime返却済み。P6/追加機能へ着手しない。
