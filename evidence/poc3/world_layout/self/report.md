# POC3-WORLD-LAYOUT 自己確認

対象: 初回HEAD `4d4da323affcd35f4a2b6a6acdfa60175a347dd4` + 受入済PRICINGとWORLD差分。経路追試/GPU/最終凍結は親PRICING commit後の `a72c39f71324367eccd00518725dc8dc4c640e64` + WORLD差分。共有treeの他者成果・indexを戻さず、stage/commitなし。最終対象hashはfreeze.json。

## 実差分

- sessionのMAP_PATHを既存準備town_03へ接続。新規開始と死亡復帰は共通start_position()からmap.player_start_cellを読む。中央(112,112)、初期177成熟草、種60/HP水100、1セル0.02種/分を維持し初期3.54種/分。補填なし。
- 全224×224セルをzone0の1地域・未制圧とし、初期成熟草に恒久免疫を与えない。_check_zone/snapshotの旧index1参照を除き、全敵巣排除で安定し、その後の侵入禁止を維持する。
- persistenceは新mapのみ受理し、1地域/状態1要素と値域整数/zone_of全0を検証。旧town_02 mapと不正2地域は状態採用前に拒否する。PRICING等の既存保存検証を保持。
- town_03.jsonは別Solの候補から変更不要。SHA-256 A1E4F6109E03BB201538EBBD6A90AC2CB4F8C27056C10F0B92EC1D85E5CB7515、既存静的14PASS証拠を保持し再走しない。旧town_02/data/素材は変更しない。

## 自己結果

| 実行 | 結果 | 証拠 |
|---|---|---|
| headless import | exit0 | import.log |
| 初回logic | 17 PASS / 1 FAIL、exit1 | logic_results.json / logic.log / context.json |
| 四方向到達性の限定追試 | 4 PASS / 0 FAIL、exit0 | routes_followup.json / routes_followup.log |
| 通常新規→開始/マップGPU | 5 PASS / 0 FAIL、exit0 | gpu_results.json / gpu.log / followup_context.json |

初回PASSは開始/177草/率/1地域、実free_position後距離・歩行可能地、水辺経路3.2mと自動補給（種不使用）、初期と30ゲーム秒早送りの非接触休眠、接近起動、遠方緑化接触起動、中央へのhostile実移動、全敵巣撃破後安定、保存復元、旧map/不正2地域拒否とsnapshot不変、死亡復帰。初期敵の最短距離13.6059m、巣14.0513/22.2926/25.2032/26.5089/36.2083m。8m内配置なし・最寄り小巣1方向12–16m・他方向20m以上を満たす。

初回FAILはnavの斜めAStar経路を半幅2pxのWalkerで各セル中心まで厳密に再生する条件。経路そのものは4方向すべて存在した。親承認により、4近傍・衝突幅を考慮して独立に求めた経路を実Walkerで再生し、東15.2m/北25.6m/西25.6m/南28.8mの到達性を別確認した。元FAILを追試PASSへ上書きせず保持。ゲームnav/Walkerを変更していない。

## 残す経路診断（HELPERS / INTEGRATIONへ）

routes_followup.jsonは元経路の最初のずれも記録する。東西はずれなし。北はstep9でcell(115,104)→(115,103)、移動前logic(461.9998,418.0002)、実結果(461.9998,418)、目標(462,414)、誤差4px。南はstep9で(115,120)→(115,121)、移動前(461.9998,481.9998)、実結果(461.9998,482)、目標(462,486)、誤差4px。

Xの約0.0002pxのずれはWalker.EPS=0.0001より大きく、半幅2px/セル幅4pxの水際境界で隣セルを跨いだ判定になる可能性がある。これは診断値とソースからの原因候補であり、丸めだけが原因と確定していない。単なるfixture誤りとも断定しない。nav.moveはWalkerを通さず経路を直接補間し、予算が足りると正確なセル中心へ合わせるため、助手/敵の実移動停止は今回再現・確認していない。四方向への実プレイヤー到達性は別経路で確認済みだが、元の厳密追従FAILは後続の関連移動検証へ引き継ぐ。

## GPU目視

new_start.png / new_map.pngを実際に開いて確認。中央の円形緑地・主人公・水路横断の広場、周囲へ開く進路、HUDとお気に入り5枠が640×360内で読める。全体マップでは探索済領域と水路・記憶/現在検知の情報が表示され、閉じるTabも読める。通常main sceneからGodot内部クリックで新規開始、内部Tabでマップを開いた。最小化を維持したSubViewport GPU画像であり、物理入力/通常窓の確認ではない。美術・楽しさを最終承認しない。

## 保存・環境・停止

起動前にCONTENT-01の別sandbox予約とGodot0を照合。APPDATA/LOCALAPPDATAを本証拠内profileへ隔離（Git除外）。既存実ユーザーPoC/PoC2保存3ファイルは読取hashのみで、最終列挙でも件数/hash一致。旧PoC3 map保存への移行・上書きは行わない。

override.cfgはCreateNewで作成し、起動前no_focus=true/mode=1。既存overrideを上書きしない。GPU開始/終了のroot.unfocusableとMODE_MINIMIZEDを確認。try/finallyで自作overrideを削除。OS入力/前面化/カーソル/復元/所有不明process停止なし。Godot0件、override無し、最終source/testhashをfreeze.jsonへ固定して編集・実行停止。

## NOT_RUN / 限界

全マップ100％緑化・孤立地100％、長時間テンポ/楽しさ、物理入力、全サイズ/全照明、全分担戦術、助手/敵の水際移動の詳細回帰、広い全体回帰は未確認。100％と全体統合は後続票。敵階級/バッタは本票では未接続。独立検証と限定受入は親へ返す。
