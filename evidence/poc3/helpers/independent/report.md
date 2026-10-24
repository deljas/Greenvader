# POC3-HELPERS 独立検証

2026-10-24。**独立10 PASS / 0 FAIL、exit0**。初回独立失敗・追試なし。代表範囲で未解決ゲームFAILを確認しなかった。最終受入は親が行う。

## 対象・環境・保全

- 指定/実HEAD `a97fbcdb996ba90a74c9cf5cf66cdb8206d19786` + freeze.jsonの9ゲーム差分。既存7ファイルの実git diffと新規helper_work/helper_effectsの全文を直接読んだ。
- game9/自己試験6hashは開始時15/15一致、終了時15/15不変。project.godotと主人公HUDのpoc2_ui.gdも前後不変。旧PoC/PoC2保存3件はhash読取りのみで前後3/3一致、ロード/移行/書込なし。
- AGENTS.md、tasks/README.md、HELPERS票、PoC3仕様該当節、自己試験・生結果を読んだ。開始時未完成だったself/report.mdも完成後に読み、説明だけを証拠としていない。
- Windows / Godot `4.7.2.stable.official.ed1daf0bf`、headless / Dummy audio。APPDATA/LOCALAPPDATAは本証拠内profileへ隔離。GDScript/headless testingスキル継続適用、SceneTree入口/型注釈/未完走検出/失敗非0終了。独立実行1回、import/GPU再走なし。
- Git読取りは--no-optional-locks。index/commit/branch操作、他者差分の復元、ゲーム編集、再委任なし。
- 証拠: before.json / after.json / actual_diff.patch / status_before.txt / status_after.txt / results.json / logic.log / exit.json。試験はtests/poc3/helpers/independent_logic.gd。

## 独立実行

| 条件 | 結果 | 確認内容 |
|---|---|---|
| ARMY_PRIORITY_AND_8M_RELEASE | PASS | 至近侵入敵/食害敵より味方を攻撃中の敵を優先。同標的を持ち場7.8mまで維持し、8.1mでは他敵へ即再選択せず帰還要求(-1) |
| RETREAT_TO_ARMY_REAR_AWAY_FROM_UNSAFE_HOME | PASS | 敵側にhomeがあっても敵と反対のArmy後方座標を選択 |
| PERSONAL_AMMO_WIDTH1_RESERVE0 | PASS | 実Gatから発射してammo2→1、共有残高不変。幅1/reserved0、着弾前は土地EMPTY |
| SECOND_GAT_CANNOT_SHARE_FLIGHT_TARGET | PASS | 別の実Gatから同targetへ発射を試みても拒否、2番目のammoと共通備蓄は不変 |
| SOURCE_GONE_FLIGHT_JSON_FULL_STATE | PASS | 発射元だけ撤去、残る別Gatと飛行弾を実JSON保存/復元し全状態一致 |
| RESTORED_RESERVATION_THEN_SOURCELESS_LANDING | PASS | 復元後も別Gatは予約済targetへ発射できない。その後既存弾だけ着弾し1セルseed化。共通備蓄と別Gat ammoは不変 |
| DUPLICATE_FLIGHT_TARGET_ATOMIC_REJECT | PASS | 別idのhelper弾を同targetへ複製した保存をduplicate_helper_targetで拒否、元全状態不変 |
| REAL_EMPTY_JOB_RETURNS_AND_SLEEPS | PASS | 実Sprinklerの6m内に仕事がない条件で3.5ゲーム秒。homeでidle/sleeping、job空、水100を保持 |
| NEW_GRASS_JOB_WAKES_AND_WATERS_ONCE | PASS | 範囲内に新しいseedを1セル作ると次tickでZzz消去、moisture100、水100→99 |
| FIVE_SECOND_REFILL_PRESERVES_HOME | PASS | 実Sprinklerをbank/refillingへ置き、4.75秒で水95、次0.25秒で100・returning_water。home不変、補給中Zzzなし |

期待は仕様の優先順・6m/8m・3秒・5秒・個体ammo/共有予約分離から固定した。価格式や判断部品をテストの期待値生成へコピーしていない。土地/個体の変更は隔離メモリfixtureのみで、ゲームデータへ保存していない。補給の実際のhome帰還は下記自己証拠の実Session経路で別確認し、独立の直接補給時間試験と区別する。

## 既存証拠と実差分の独立監査

自己pure19、初回接続12 PASS/1 FAIL、idle限定3 PASSと影響5 PASS、marker1 PASS、GPU各走行7 PASSは別履歴として保持し、独立10件へ加算しない。

| 条件 | 結果 | 根拠・限界 |
|---|---|---|
| Army6m取得/8m追跡/標的安定/巣除外/帰還 | PASS（自己pure/接続と実差分レビュー） | self_pure.gdとpure_results.json、plants._army/_return_home。敵リストのみを対象にし母体/巣を選ばない。target消失時は帰還、同順位hysteresisあり |
| Gatの緑隣接cluster・飛行予約・共有資源非補充/非返還 | PASS（実差分/生結果レビュー） | helper_work.sow_target、plantsの局所frontierとshot予約、combat.helper_seed/_sow_ground/_refund_seed。self_logicの壁阻害/共有予約混入拒否/AREA代表の生PASSを確認 |
| Sprinkler未給水crop→草、有効job維持/給水済skip | PASS（自己pureと実差分レビュー） | self_pureの候補/優先/既存grass job維持/完了再選択、純粋判断の候補除外と到達範囲を確認。初回散水のみ水1 |
| 水切れ→5秒補給→元home、bank/home仕事marker | PASS（自己限定追試レビュー） | idle_followup_results.jsonの実補給帰還（home距離2px、水100、water_task空）。marker_results.jsonとself_markers.gdでtarget_posがbank/homeへ追従 |
| unsafehome回避・退避hysteresis・Zzz抑止 | PASS（実差分/自己証拠レビュー） | 危険距離3.5m/解除4.5m、帰還/空弾/水帰還でもunsafehome検査。初手が敵に近づく経路は移動しない。pureでArmy/資源切れ/補給/退避のZzz抑止、実接続でunsafehome距離を確認 |
| 同条件でGatの寄与 | PASS（自己比較証拠レビュー） | 自然拡張thresholdを両側同じ1e9にした局所6秒比較。なし0セル/あり2セル播種 |
| 同条件でSprinklerの寄与 | PASS（自己比較証拠レビュー） | なし/ありのwatered0/1、成熟進捗age3.0/5.875。通常世界全体の収支やバランス評価ではない |
| 同条件でArmyの食害保護 | PASS（自己比較証拠レビュー） | 同じlocust食害条件でArmyなしstage0/ありstage4。生結果と実試験を確認 |
| 主人公HUD維持/表示read-only | PASS（差分レビュー） | poc2_ui.gd無差分、前後hash不変。新Effectsは表示node/gauge/markにだけ書き、sourceの状態・資源を変更しない。mapの選択条件内にhome/range/job表示、追跡8m円は追加なし |

## 最新GPU画像の独立目視

次の3枚を実際に開いた。画像hashはafter.jsonへ記録。自己の機械的visible判定だけを目視合格の代わりにしていない。

- **PASS（静止画範囲）range_states.png**: 草上でも設置の薄い楕円を識別。個体上に離れたZzz/水補給/種不足マークと部分バーが見える。主人公右上HUDを保持。満タン非表示は自己構造検査とコードでも確認。
- **PASS（静止画範囲）flying_actions.png**: rangeプレビューは消え、個体の短い印/バーと飛翔の代表を確認。瞬間画像から全actionの時間的読みやすさを合格にしない。表示状態の一部は合成fixtureであり、自然プレイで全状態が同時成立するという証拠ではない。
- **PASS（静止画範囲）selected_map.png**: zoom4の選択個体付近にhome/6m楕円と仕事先の接続表示、部分ゲージを確認。全map状態や全重なり条件を検証したとはしない。

初回gpu_initial_results.jsonの7 PASSは構造/撮影条件の成功で、円が草へ隠れた目視不備は保持する。*_initial.png、*_range_followup.png、最終サフィックスなし3枚は別ファイル。最終helper_effectsは地面平面y0.045、幅0.08m、alpha0.55、depth非依存のガイドであり、草の上から読める変更を差分で確認した。GPU再走はしていない。完成美術や連続動作の承認ではない。

## 初回不具合の扱い

初回接続のreal_home_idle_sleep_after3 FAILは実ゲーム不具合。検索待ち中のtarget_pos=homeを仕事と扱いworking/wateringに入ったため、空jobガードを入れて帰還/待機を継続するよう修正された。logic_initial_results.json/logを保持し、idle_first_followupの3 PASS、idle_followupの5 PASS、marker1 PASSと分けて確認した。条件緩和や原FAILの削除はない。今回独立でも実Sprinklerの空仕事待機/Zzz/新仕事復帰を確認し、最終凍結版の未解決FAILとはしていない。

## NOT_RUN・終了

- NOT_RUN: 全map100%/全孤立地/広い回帰（INTEGRATIONへ）、全障害物経路/全状態組合せ、長期性能/経済/難易度/楽しさ、物理入力、独立GPU再走、連続動画の読みやすさ、完成美術、書き出しビルド。
- ゲーム/他tests/素材/設定/docs/票を編集していない。所有independent_logic.gdと本証拠のみ追加。他者変更保全、再委任なし。
- OS入力/カーソル/前面化/未知プロセス停止なし。開始/終了Get-ProcessでGodot0、overrideなし、15凍結hashと旧保存3件不変。
- 実行終了済み、以後実行しない。Godot/import権は親へ先に返却済み。受入の判断を返して停止する。
