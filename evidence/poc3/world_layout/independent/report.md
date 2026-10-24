# POC3-WORLD-LAYOUT 独立検証

2026-10-24。**独立10 PASS / 0 FAIL、exit0**。新しい失敗は確認されなかった。ただし、既存自己試験の斜め経路追従FAILは保持し、解消済みとしない。限定受入と後続対応の最終判断は親へ返す。

## 対象と保全

- 指定/実HEAD `a72c39f71324367eccd00518725dc8dc4c640e64` + 凍結3ファイル。session/persistenceの実未コミットdiff、新規town_03.jsonの開始・paint・配置データ、該当処理を直接読んだ。
- self/freeze.jsonと開始時のゲーム3/自己試験5hashは8/8一致。終了後も8/8不変。project.godot不変。旧PoC/PoC2保存3件はhash読取だけで前後一致、ロード/書込なし。
- AGENTS.md、tasks/README.md、WORLD票、TASK_TEMPLATE.md、POC3_SPECの中央開始、self/report/freezeと自己試験・生結果を確認した。自己報告だけで判定していない。
- Windows / Godot `4.7.2.stable.official.ed1daf0bf`、headless / Dummy audio。APPDATA/LOCALAPPDATAは本証拠下profileへ隔離。CONTENT-01の別sandbox予約と開始時Godot0を確認。
- GDScript/headless testingスキルを継続適用。SceneTree入口、型注釈、未完走検出とFAIL時非0終了。独立実行は1回、長時間はゲーム時間で早送り。
- 証拠はbefore.json / after.json / actual_diff.patch / status_before.txt / status_after.txt / logic.log / results.json / exit.json。試験はtests/poc3/world_layout/independent_logic.gd。

## 独立実行

| 条件 | 結果 | 確認内容 |
|---|---|---|
| CENTRAL_INITIAL_RESOURCES | PASS | cell(112,112)の中心logic(450,450)、224x224、種60/HP100/水100 |
| EXACT_3M_CIRCLE_177_AND_INCOME | PASS | 全50176セルを走査し、0.4mセルで半径3mの集合と成熟草集合が完全一致。177セル、土地収入3.54種/分。期待集合は距離から導きmapのpaint列を写していない |
| ONE_UNCONQUERED_REGION_NO_INITIAL_IMMUNITY | PASS | 全セルzone0、zone_count=1/state0、snapshot.stable=false、中央はhostile経路で禁止されていない |
| INITIAL_ENEMY_NEST_DISTANCE_SPACING | PASS | 初期実敵最短13.6059m、巣14.0513/22.2926/25.2032/26.5089/36.2083m。8m内なし、最寄12–16m、他方向20m以遠 |
| TOWN03_ACTUAL_JSON_ROUNDTRIP | PASS | 隔離user領域の実JSON保存/復元で全保存状態一致 |
| OLD_MAP_ATOMIC_REJECT | PASS | mapを旧town_02へ変えた保存をinvalid_saveで拒否し元Session全状態不変 |
| REGION_FRACTIONAL_STATE_ATOMIC_REJECT | PASS | 1地域でもstate[0]=0.5はinvalid_zonesで拒否、全状態不変 |
| RESPAWN_READS_CANONICAL_MAP_FIELD | PASS | メモリ上の隔離fixtureだけ開始欄を(113,112)へ変え、死亡復帰はlogic(454,450)へ追従。旧固定座標/中央literalへの復帰ではない。ゲームjsonは編集していない |
| REMOTE_IDLE_TIME_DOES_NOT_ACTIVATE | PASS | 初期位置のまま12ゲーム秒早送りで全巣休眠・敵数不変 |
| APPROACH_ACTIVATES_ONLY_NEAREST | PASS | 最寄り巣へ接近して0.25秒進行、最寄りだけ起動、他巣は休眠 |

## 再利用した自己証拠と実画像

自己の初回17 PASS / 1 FAIL、別経路限定4 PASS、GPU5 PASSは別実行として保持し、独立10件へ合算しない。自己ソースと生結果を読んで以下を確認。

| 条件 | 結果 | 根拠と範囲 |
|---|---|---|
| 水辺3.2mの到達と自動補給 | PASS（既存実行レビュー） | self_logic.gdの実Walker経路、logic_results.jsonのbank2条件PASS。水側セル(112,103)、歩ける岸(112,104)。補給で種を使わない |
| 四方向への通路存在/実衝突到達 | PASS（別経路の証拠レビュー） | self_routes_followup.gdは四近傍BFSにWalker.is_clearの幅制約を加え、得た経路を実Walker.moveで再生。東15.2m/北25.6m/西25.6m/南28.8m、全4件PASS。静的経路だけの証拠ではない |
| 緑化接触で遠方巣起動 | PASS（既存実行レビュー） | self_logic.gd/greenケースと生結果。主人公が90pxより遠い条件で遠方巣周辺を発芽させ起動 |
| 中央へ敵が進入可能、全敵巣撃破後安定 | PASS（既存実行レビュー） | self_logic.gd/centralケースはhostile navで中心へ実移動、敵巣へdamageを与えた後zone0安定/中央hostile禁止を確認。_check_zone/nav.setupの実ソースも確認 |
| 不正2地域保存拒否 | PASS（既存実行/実diffレビュー） | self初回の2地域shape拒否と状態不変PASS。最終validatorはcount/state長/値域整数/zone_of全0を検証 |
| 通常開始画面 | PASS（既存GPU画像目視） | self/new_start.pngを実際に開いた。640x360内で中央の円形緑地、主人公、水路を横断する広場、所持60と5枠が見える。恒久免疫は画像から推定せず別ロジックで確認 |
| 地図表示 | PASS（既存GPU画像目視） | self/new_map.pngを実際に開いた。中央付近の探索済地形と水路、現在表示領域と「閉じるTab」を確認。全世界の探索/地図情報完成を意味しない |

GPUはa72c39f時点で、followup_context.jsonのexit0とfreezeの対象hash一致を確認。GPU新規再走はしていない。画像hashはafter.jsonへ記録。長期配置テンポや美術/楽しさの評価は行っていない。

## 保持するFAILと後続確認

**FAIL（既存、移動精度の中程度の課題、実AI影響未確定）: 斜めAStar経路を幅付きWalkerで厳密追従すると北/南で止まる。** 通路の不存在と同一視しない。

- 期待: nav.routeで得た隣セル中心への移動を半幅(2,2)のWalkerで再生し、各目標へ到達する。
- 実際: 北step9、logic(461.9998,418.0002)→目標(462,414)に対し(461.9998,418)まで。南step9、(461.9998,481.9998)→目標(462,486)に対し(461.9998,482)まで。いずれも残差4px。
- 最小再現: 新Sessionのtown_03中央から北巣/南巣へnav.routeを取得。先頭セル中心から各隣セル中心へ `Walker.move(state,4,pos,target-pos,Vector2(2,2))` を順次適用。self_routes_followup.gd/failure_pointが同操作と最初のずれを記録する。
- 対象: scripts/poc2/simulation/navigation.gd、scripts/play/walker.gd、data/poc3/maps/town_03.json。今回はこれらを修正していない。
- 証拠: self/logic_results.jsonのfour_front_routes_replayed_with_player_collision FAIL、self/routes_followup.jsonのoriginal_nav_first_error。元結果を保持し、今回再走していない。
- 原因候補: 約0.0002pxの横ずれとWalker.EPS/セル境界。原因を断定しない。nav.moveはWalkerを通さず経路を直接補間する実ソースを確認したため、実AIの停止を確認済みとはしない。
- 別の幅付き四近傍経路では全4方向が実Walkerで到達済み。元FAILを解消へ変更せず、HELPERS/INTEGRATIONの関連移動確認へ返す。

## NOT_RUN・終了

- NOT_RUN: 独立の全経路/GPU再走、助手/敵の水際移動の詳細回帰、全マップ/孤立地100%、全分担戦術、長時間テンポ/バランス/楽しさ、全サイズ/照明、物理入力、広い全回帰、書き出しビルド。
- ゲーム/設定/素材/他者試験/docs/作業票は編集していない。追加編集は所有のindependent_logic.gdと本証拠のみ。Git index/commit/branch操作なし。
- OS入力・カーソル・前面化・復元なし。未知プロセス停止なし。開始/終了Get-ProcessでGodot0、override.cfgなし。旧保存3件/対象hash不変。
- 実行終了済み、以後実行しない。Godot/import権を親へ返却済み。上記既存FAILの後続割当と限定受入の判断を親へ返す。
