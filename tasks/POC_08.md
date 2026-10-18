# POC-08 PoCの開始・保存復元・操作案内

## 管理欄

- ID: POC-08
- 状態: 完了
- 担当ツール: なし
- 担当セッション: なし
- 更新日: 2026-10-18
- 予約中の編集範囲: なし（解除済み）
- 予約中の共有資源: なし（Godotプロセス残なし）
- 最終担当: claude-20261018-poc-opus

## 目的・依存

小街区を新規開始し、途中保存と再開ができ、目標と状態を読めるPoC入口にする。P5全体の完成とは区別する。

依存: POC-07。実行順・優先度の正本は[開発計画](../docs/03_DEVELOPMENT_PLAN.md)。取得と状態の正本は本票。

## 対象・編集と役割

- 対象: 共有 `C:/godot/greenvader`。計画時HEADは `99013702eaf36db72a64d60d284680fb834f13c5`、多数の既存未コミット試作を含む。取得時に現HEAD/差分を再確認し、他者の成果を破棄しない。
- 編集候補: scripts/poc/save/・ui/、data/poc/保存版定義、tests/poc/save/、run_game.bat/launchers/README.md/project.godotの必要部分（取得時予約）。候補は予約ではない。親が取得時に実ファイルと共有資源を記入し、必要なら本票内で実装割当を分ける。
- Claude親が設計/取得/統合/最終判定、Sonnet実装と別Sonnet独立検証、Haikuは確認済み記録。子の再委任禁止。Codexは今回計画文書のみ担当。
- 資料: AGENTS.md、tasks/README.md、[企画書](../docs/01_GAME_DESIGN.md)、[技術方針](../docs/02_TECH_AND_ART.md)、[STATUS](../docs/STATUS.md)、[DECISIONS](../docs/DECISIONS.md)、関連する旧P1/P2票、[町試作](../docs/TOWN_LAB.md)。
- 禁止: 他票の予約/検証凍結範囲、外部納品原本の編集、既存セーブの破棄、無関係な美術磨き込み、権限設定変更。Godot/import/共有文書/Git操作は同時占有しない。
- OSレベルの入力送信・フォーカス奪取・カーソル移動は禁止。入力はエンジン内注入、撮影は前面化なし。物理入力はユーザー手動確認。
- 確定ルールは維持。数値・内部設計は可逆的初期値として調整可、確定仕様を変える必要は親へ返す。

## 合格条件

- 新規開始・手動保存/再開・ポーズ・地域安定/緑化完了表示・操作説明を用意。内部緑化率を数値等で示し、舗装の草が薄くても100％を判別できる。
- 世界/マップ版、地形と植物/水分、資源/HP/位置、敵/巣/死骸、地域/遠距離拡散、時計/乱数、壁植生成長、解像度設定の保存責任を一覧化。揮発弾等の扱いも明示。
- 新規PoC専用の保存名前空間を使用し、旧セーブを変更/削除しない。一時置換とバックアップ、不正データ拒否、マップ版違いの案内を実装。拒否で現在状態や占有が半端に壊れない。
- 発芽中・戦闘中・安定後の代表状態で一往復。種/報酬/敵が重複せず、終了中の現実時間を加算せず、pause解除で停止時間がまとめて進まない。
- PoC専用入口を維持し、通常入口を切り替えるなら旧版へ戻れる起動先も残す。変更は明示し、既存labを壊さない。Windows export/テンプレート導入は依然後回し。

## 証拠・終了条件

- 証拠: `evidence/poc/08/` に対象版/実差分/再現手順/主要ログ/必要な画像とPASS・FAIL・NOT_RUN。旧証拠を書き換えない。
- 検証はほどほど。長い時間条件は早送り、1条件1回、回帰一式1回。ヘッドレス起動だけなら描画はNOT_RUN。
- 現在は計画のみで未実装・未検証。親が合格条件と証拠を確認した範囲だけ完了にする。
- 中断時は残差分・未確認・次の一手・所有プロセス・子の停止・予約解除を残す。担当移譲を状態ラベルだけで済ませない。


## 親の設計判断（2026-10-18、claude-20261018-poc-opus）

- 入口: 通常入口（run_game.bat、project.godotのrun/main_scene=旧main.tscn）は切り替えない。PoCは launchers/run_poc.bat → scenes/poc.tscn のまま。PoC起動時にタイトル（新規開始／続きから／操作説明）を出す。
- 保存先: `user://poc_saves/` のPoC専用名前空間（旧セーブと分離し、旧セーブは読まない・変更しない）。手動保存1枠＋直前のバックアップ。一時ファイルへ書いてから置換し、読込失敗時はバックアップを案内。自動保存はPoCでは任意（入れるなら手動枠と別名）。テストは `user://poc_saves_test/` 等の別名前空間を使う。
- 形式: JSON、`format_version`・`map_id`・`map_hash`（地形/target集合のhash）を持ち、版違い・マップ違い・破損は拒否して理由を表示。拒否時は現在の状態と占有を壊さない（新しいセッションへ読み込み、成功時だけ差し替え）。
- 揮発物: 飛翔中の弾は保存しない（保存時点で消滅。栽培植物の予約種は返却して重複も損失もさせない）。現実時刻は保存せず、読込後はゲーム時計の続きから進む（終了中の進行なし）。
- 保存責任の一覧（世界/マップ版、地形と植物/水分/肥沃、資源/HP/位置、敵/巣/死骸、地域/遠距離拡散、時計/乱数、壁植生、解像度設定）をreportと本票に記録する。
- 独立検証で部分FAIL（値だけ改ざんしたJSONの受理: far.job_zone=999でSCRIPT ERROR、plant_id 250・moisture 255・敵HP 99999受理、種/水/HP/tick負値などは黙ってクランプ）。親判断: 範囲外は拒否に統一し、実装担当へ差戻し（作業中へ戻す）。

## 引き継ぎ・完了記録（2026-10-18）

- 対象: HEAD 9901370＋未コミット差分。初回凍結37ファイル（poc08_freeze）は独立検証の開始・終了時に一致。差戻し修正後: poc_save.gd d23e0f9dbe32、tests/poc/save/logic.gd 2d8e97f22fb8（他は初回凍結と同一。poc_ui 357924b6f184、poc_main 941bc5ef71c5、poc_session 0b5561b2a8ee、poc_input 679a8608feb5）。
- 保存責任一覧: マップ版（format_version、map_id、map_hash、サイズ、zone割当）、WorldState全配列（地形・植物・段階・成長・水分・肥沃・占有・地域状態・sprout_seed）、GrowthSim/SpreadSim/FarSeedSim進捗、SimClock、PlayState（種・水・HP・選択・拾得物・栽培植物・供給源タイマー）、EnemyField（巣・敵・各個体rng・死骸）、壁植生、プレイヤー位置・地域ログ・統計、解像度index。保存しない: 飛翔中の弾（保存時に消滅し消費分と予約種を返却。上限満タン時は返却が上限で切られる軽微な制約）、照準、倍速、pause、現実時刻、表示状態。
- 保存先: `user://poc_saves/slot.json`＋`slot.bak.json`（一時ファイル→置換）。旧セーブは不変（独立検証でuser://全体のmd5前後比較）。拒否コード missing/corrupt/missing_key/version/map/hash/invalid。範囲外値はクランプせず拒否（親判断）。
- 実装（Sonnet 5.5）: save logic 58→修正後73、ui_logic 28、GPU 7 PASS、回帰7本PASS。証拠 `evidence/poc/08/`（report.mdは親が要約）。
- 独立検証（別呼出しSonnet 5.5）: 往復・重複なし・時間・UI・入口・回帰 PASS。拒否は値改ざんの受理（far.job_zone=999でSCRIPT ERROR等）で部分FAIL→差戻し→修正。影響範囲として独立検証者の poc08_core.gd を実装担当と親が各1回再実行し42 PASS / 0 FAIL（親ログ `evidence/poc/08/independent/core_recheck_parent.log`）。
- 入口: 通常入口（run_game.bat、main_scene=旧main.tscn）は不変。PoCは launchers/run_poc.bat でタイトルから開始。
- NOT_RUN（POC-09へ移管）: FarSeed実行中（job_zone≥0）の保存・読込、downed中保存、run_poc.bat実起動でのタイトル実描画、物理入力、自動保存（任意・未実装）。
- 履歴: 2026-10-18 claude-20261018-poc-opus 取得→検証待ち→作業中（差戻し）→完了。予約解除。
- 追記（POC-09統合確認から差戻し、2026-10-18）: downed中保存→読込で、PlayState.load_dict内の復帰処理後に poc_save.apply が保存位置で上書きし、安全地帯へ戻らない不具合。親がPOC-08の実装担当へpoc_save.gdの限定修正を依頼（POC-09の予約内で実施、POC-08の状態は完了のまま、修正は本記録に追記）。
- 追記: 修正後 poc_save.gd 363505044e13、tests/poc/save/logic.gd 6279810502ed。save logic 76 PASS、integration regress 20 PASS、poc08_core 42 PASS。
