# POC-03 種まき・給水・資源循環の3D接続

## 管理欄

- ID: POC-03
- 状態: 完了
- 担当ツール: なし
- 担当セッション: なし
- 更新日: 2026-10-18
- 予約中の編集範囲: なし（解除済み）
- 予約中の共有資源: なし（Godotプロセス残なし）
- 最終担当: claude-20261018-poc-opus

## 目的・依存

既存P1のPlayState/GrowthSim/SpreadSim等を再利用し、地面即時緑化ボタンの試作から、資源を消費して開拓する遊びへ接続する。

依存: POC-02。実行順・優先度の正本は[開発計画](../docs/03_DEVELOPMENT_PLAN.md)。取得と状態の正本は本票。

## 対象・編集と役割

- 対象: 共有 `C:/godot/greenvader`。計画時HEADは `99013702eaf36db72a64d60d284680fb834f13c5`、多数の既存未コミット試作を含む。取得時に現HEAD/差分を再確認し、他者の成果を破棄しない。
- 編集候補: scripts/poc/play/、必要最小限のscripts/play/表示依存分離、data/poc/調整値、tests/poc/play/（候補）。候補は予約ではない。親が取得時に実ファイルと共有資源を記入し、必要なら本票内で実装割当を分ける。
- Claude親が設計/取得/統合/最終判定、Sonnet実装と別Sonnet独立検証、Haikuは確認済み記録。子の再委任禁止。Codexは今回計画文書のみ担当。
- 資料: AGENTS.md、tasks/README.md、[企画書](../docs/01_GAME_DESIGN.md)、[技術方針](../docs/02_TECH_AND_ART.md)、[STATUS](../docs/STATUS.md)、[DECISIONS](../docs/DECISIONS.md)、関連する旧P1/P2票、[町試作](../docs/TOWN_LAB.md)。
- 禁止: 他票の予約/検証凍結範囲、外部納品原本の編集、既存セーブの破棄、無関係な美術磨き込み、権限設定変更。Godot/import/共有文書/Git操作は同時占有しない。
- OSレベルの入力送信・フォーカス奪取・カーソル移動は禁止。入力はエンジン内注入、撮影は前面化なし。物理入力はユーザー手動確認。
- 確定ルールは維持。数値・内部設計は可逆的初期値として調整可、確定仕様を変える必要は親へ返す。

## 合格条件

- 有限の通常種で播種し、水を消費して促進し、発芽・成熟・自然拡張・種生産・回収がつながる。にんじん/キウイとHPも既存機能を仮表示で接続。全補給ボタンを必須手段にしない。
- 種ゼロでも安全地帯供給源から復帰でき、水ゼロでもゆっくり成長し水辺で補給できる。地面の拾得物、在庫、成長状態を画面で区別可能。
- 3D地面照準・射程・弾の飛翔/着弾を論理状態へ接続。ProjectileField等の2D表示依存は分離し、壁越し発射/植付や対象外地への誤加算を防ぐ。敵命中との順序はPOC-04で接続。
- 入力はUI操作と競合せず、解像度切替・カメラ追従で着弾位置がずれない。ポーズ中は成長・供給・弾・回収を停止。
- 必要なP1回帰を1回実施。旧表示の全テストを書き換えて合格数を増やさず、描画非依存の保証を維持。

## 証拠・終了条件

- 証拠: `evidence/poc/03/` に対象版/実差分/再現手順/主要ログ/必要な画像とPASS・FAIL・NOT_RUN。旧証拠を書き換えない。
- 検証はほどほど。長い時間条件は早送り、1条件1回、回帰一式1回。ヘッドレス起動だけなら描画はNOT_RUN。
- 現在は計画のみで未実装・未検証。親が合格条件と証拠を確認した範囲だけ完了にする。
- 中断時は残差分・未確認・次の一手・所有プロセス・子の停止・予約解除を残す。担当移譲を状態ラベルだけで済ませない。


## 親の設計判断（2026-10-18、claude-20261018-poc-opus）

- 既存P1ロジック（PlayState、GrowthSim、SpreadSim、Landing、GroundPickups、SeedSource、PlantProducer、Cultivation、PlayerHealth）はscripts/play・scripts/worldから変更せずに再利用する。PoCの全進行は `poc_session.advance_game` の一本のループ（SimClock→PlayState→論理弾）で行い、旧本編のSimulationDriver/PlayDriver/ProjectileFieldのようなNodeごとのフレームdelta駆動を持ち込まない。
- 弾は2D Sprite依存のProjectileFieldを使わず、scripts/poc/play/ に表示非依存の論理弾リスト（同じ直進・射程・寿命・敵命中フック）を作り、3D表示は別Nodeで描く。壁はPOC-02のblocks_projectileで遮断し、封鎖屋内セルも遮断扱いにする。
- 配置のattach/rebuildはセットアップ専用。実行中は再適用しない。
- 試作用の全補給ボタンを必須手段にしない（デバッグ用に残す場合は既定で無効/明示）。

## 引き継ぎ・完了記録（2026-10-18）

- 対象: HEAD 9901370＋未コミット差分。凍結14ファイル（`poc03_freeze`）は独立検証の開始・終了時に一致。主な先頭12桁: poc_projectiles 9cfcc7e2df77、poc_play_view db520c8904c8、poc_session 7537e5c4f34d、poc_main f3b0769f9cbb、poc_input e1a5fb68199c、placement ac65f885d47b、play_setup.json 1a14b9a17d92。scripts/play・scripts/worldはPoCで未変更。
- 実装（Sonnet 5.5）: 自己logic 69 / POC-01回帰 40 / POC-02回帰 45 / GPU 8 PASS、旧P1 checks 6本全て失敗0。証拠 `evidence/poc/03/`（report.mdは親が転記）。
- 独立検証（別呼出しSonnet 5.5）: 循環・復帰・弾・pause・単一ループ・回帰の6条件 PASS / 0 FAIL（検証側オラクル不備による初回FAILは検証側修正で解消、実装変更なし）。証拠 `evidence/poc/03/independent/`。
- 親判断: 壁越し植付の禁止は着弾点基準（着弾点から壁越しのセルへ散布しない）。発射位置から見えない角の向こうでも着弾点から見えるセルへの散布は許容。低い小物（消火栓・柱・木・バス停）は弾を通す。壁に当たった種・水は失われ、栽培植物の弾は種返却。水の散布が壁の反対側の水分を上げうる点は軽微な制約。
- NOT_RUN: 物理入力、実1080p窓、独立のGPU描画再確認（自己画像のみ）、にんじん/キウイ/HPの独立確認（自己logicでは確認済み）、実時間の長時間プレイ。
- 履歴: 2026-10-18 claude-20261018-poc-opus 取得→検証待ち→完了。予約解除。
