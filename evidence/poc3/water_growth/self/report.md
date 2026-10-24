# POC3-WATER-GROWTH 実装者自己報告

- 対象版: HEAD `119efb5fdf5f397e9288748b477aca45038cb56e` + 本機能未コミット差分。共有ツリーでAREA-SEEDの上へ実装。開始時HEAD `5f7ac13901e28f7c24372cd44494dfd599b44fb0`、親のAREAコミットによりHEAD変動。対象ゲーム5ファイルと試験3ファイルのSHA-256は `freeze.json`、実差分は `actual_diff.patch`。
- 環境: Windows / Godot `4.7.2.stable.official.ed1daf0bf`、headless、Dummy audio。APPDATA/LOCALAPPDATAはこのディレクトリ下のignored `profile/`へ隔離。ユーザー保存はhashだけ取得しロードしていない。

## 変更ファイル・実装

- `scripts/world/world_state.gd`: 既定falseの`permanent_water`でPoC3だけ一度給水。草の水分0/100、荒地・成熟草の給水拒否、外部stage変更で局所的なactive除去。食害後は乾燥開始、他セルの処理順とlagを保持。GrowthSimの配列退避中だけ`set_stage`の活動集合同期を呼出側へ委ねる。
- `scripts/world/growth_sim.gd`: 成熟時に退避中のlocal moistureを0化しactiveから除外。保存のcursor末尾を0へ正規化。ロードは旧active順序/lagを先に検証し、成熟/荒地の水分を除去、正水分の成長草を100へ移行。全世界rebuildでlagを捨てない。重複active・不正lagも拒否。
- `scripts/poc2/poc2_session.gd`: PoC3をopt-in、dry速度0.5/wet1/減衰0。地力0・日照1・手播きはdry60秒/wet30秒。自然発芽倍率2を含む既存補正は維持。共有SimTuning既定値、spread/far上限式は変更なし。
- `scripts/poc2/simulation/plants.gd`: 新株`watered=false`、一度給水でtrueを成熟後まで保持、dry速度0.5/wet1。既存成熟Tは20/15/45/30/90秒。初回給水候補の乾いた成長草がある場合だけcatch_upして再評価し、遡及加速を防止。追い水・荒地/成熟草・cropのみは全active精算しない。スプリンクラーは未給水crop優先→未給水成長草、一度給水後に再選択し反復を仕事にしない。内部水消費は有効な初回散水1回につき1（従来の継続散水時dt消費から変更）。home/退避等は既存のまま。
- `scripts/poc2/simulation/persistence.gd`: cropのwatered bool検証・保存、旧作業PoC3のmissing wateredは`wet_until > saved clock.elapsed`で移行。年齢進捗保持。
- `tests/poc3/water_growth/{self_logic.gd,self_followup.gd,self_run.ps1}`: 代表試験、保存限定追試、同刻み継続・provider経路確認、隔離headless runner。Godot生成の`self_logic.gd.uid`も本試験に属する。

## 実行結果と証拠

- import: `import.log`、exit0、エラーなし。
- 初回logic: `logic_initial.log` / `logic_initial_results.json`（原`logic.log` / `logic_results.json`も保持）、18 PASS / 3 FAIL。草/栽培の成熟、途中給水、食害active/lag、sprinkler、孤立地30/30到達などを各条件1回、ゲーム内時間早送りで確認。
- 初回3 FAIL: 食害によるactive削除直後にcursor==新active.sizeとなり、読み込みが同義の0へ正規化した表現差。保存自体は成功していた。保存時に次sweepの開始位置を正規化して修正し、比較除外・条件緩和はしていない。
- 初回には試験のteardownが存在しない`SpreadSim.close()`を呼ぶSCRIPT ERRORもあった。`tile_listener=Callable()`へ訂正。既に成功した孤立条件は再走していない。
- 保存影響限定追試: `save_followup.log` / `save_followup_results.json`、4 PASS / 0 FAIL。実SessionのJSON保存往復、watered/草進捗/active順序/lag、invalid watered拒否と状態不変、旧作業保存の移行。
- 追加確認: `continuation.log` / `continuation_results.json`、3 PASS / 0 FAIL。食害直後の実JSON保存後、同じ1秒（0.25秒刻み）進めた全snapshotが一致。追い水で無関係lagを精算しない。sunlight providerがある非fast経路でも成熟時水分0/active除去。
- 重複を除いた最終有効結果: **24 PASS / 0 FAIL**（`results.json`、各条件の元証拠を併記）。全回帰一式は実施していない。
- 通常入口headless起動: `startup.log`、`--quit-after 3`、exit0。parse / runtime SCRIPT ERRORなし。ただし終了時にObjectDB 37件・resource 20件残存のwarning/errorあり。起動終了の資源解放問題として親へ報告、表示側を含む範囲外の修正はしない。
- `git diff --check`は対象5ファイルで成功。CRLFへ変換予定というGit noticeのみ。
- 実ユーザー保存3件は開始前後SHA-256一致（`context.json` / `freeze.json`）。既存保存へ書き込み・ロードなし。

## 未検証・残課題・文書担当への情報

- GPU描画・ピクセルパーフェクトの実画面・物理入力・操作感はNOT_RUN。描画設定・美術素材は本機能で編集なし。
- 全224x224世界の長時間100%と広い回帰はNOT_RUN。今回は分離された2つの陸地を持つ15x3世界で入力なし・無給水30/30到達の代表確認。
- 保存移行は代表のwet cropと正moisture草・成熟/荒地を確認。全旧作業保存の網羅はしない。旧PoC/PoC2保存は移行対象外。
- スプリンクラーの本格的home/退避/待機表示は後続HELPERS。終了時resource残存の原因は本票で特定していない。
- 共有STATUS・企画・作業票を子から更新していない。文書担当へは上の実装済範囲、内部水消費1/初回散水、最終有効24 PASS、初回FAIL履歴、NOT_RUN、終了時warning/errorを渡す。
- コミット・stage・ブランチ切替・再委任・OS入力なし。凍結時Godotプロセス0（`freeze.json`）。編集とGodot実行を停止し、独立検証可能として親へ返却。
