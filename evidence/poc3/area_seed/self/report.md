# POC3-AREA-SEED 自己実装・検証

対象: 共有ツリー `C:/godot/greenvader`、INPUT受入コミット `5f7ac13901e28f7c24372cd44494dfd599b44fb0` ＋ `freeze.json` 記載の7ゲームファイル。Godot 4.7.2、Forward+、RTX 5070 Ti、640×360。AREA準備時の9d54a6dからINPUTを再適用せず、その受入差分の上へ接続した。共有文書・作業票・前タスクの配置データは未編集。

## 変更ファイルと実装

- `scripts/poc2/simulation/seed_area.gd`（前段準備分）: 1/3/5/7の中心正方形から新規播種できるセルを選ぶ。水/建物/既存種草/占有植物と、生存helperの現在セルを除外。中心距離二乗→y→x順で、予算内と予算不足を分割する読み取り専用計画。
- `scripts/poc2/simulation/combat.gd`: 通常発射で1個を預かり、弾に幅/預かりを保持。敵/巣は通常ダメージ5・1個消費・周辺播種なし。地面着弾で現在の有効セル、移動helper、預かり＋現在残高を再計算し、成功数だけ精算。0有効/壁は預かりを返し、弾は一度だけ除去。種バズーカの3個/威力25を維持。壁→敵/巣→地面の判定順を維持。
- `scripts/poc2/simulation/persistence.gd`: 飛翔中の弾の幅/預かりを保存・検証。既存PoC3通常弾でフィールド欠損なら幅1・支払済み預かり1と解釈。JSONの数値表現差はfloatで比較後intへ正規化。不正な幅/預かりは現在Sessionを変えず拒否。旧PoC2保存の移行なし。
- `scripts/poc2/poc2_session.gd`、`poc2_main.gd`: 読み取りプレビューを接続し、通常入力・モード分離を維持。
- `scripts/poc2/view/world_view.gd`、`ui/poc2_ui.gd`: 通常射程8mで制限した着弾予定セルに、薄い正方形、緑の予定セル、黄の種不足セルを描画。種の塗りつぶしアイコンと予定数を表示。現在の弾道上で敵/巣への命中が予測される場合は範囲を隠し1個攻撃表示。壁なら0・遮蔽表示。UI/設置/マップ/メニューではプレビューを隠す。仮の「選択のみ」「効果は後続」を除去。
- `tests/poc3/area_seed/self_*`: 限定logic、保存追試・診断、GPU、隔離/起動wrapper。importで対応uidを生成。

敵/巣の予測は現在位置での見込み表示であり、移動予測をしない。最終命中・消費・播種は実際の着弾結果で決まる。

## 実行と結果

すべて `self_run.ps1` でAPPDATA/LOCALAPPDATAを本ディレクトリの `profile/` へ隔離。一時overrideをCreateNewで競合保護して起動前にno_focus=true/mode=1を指定し、finallyで除去した。

| 実行 | 結果 | 証拠 |
|---|---|---|
| import | exit 0、構文エラーなし | import.log |
| logic初回 | 26 PASS / 3 FAIL（29条件） | logic_results.json、logic.log |
| 保存限定追試 | 4 PASS / 0 FAIL | save_followup_results.json、save_followup.log |
| 保存原因診断・正常Session・破損拒否再確認 | 5 PASS / 0 FAIL | save_diagnostic_results.json、save_diagnostic.log |
| GPU代表条件 | 15 PASS / 0 FAIL | gpu_results.json、gpu.log |

初回失敗は、試験が時刻0のまま繰り返し草をEMPTYへ戻し、active集合を未精算にしたfixtureが原因。`invalid_growth`を小さい再現例で確認した。fixtureだけに`rebuild_derived`を追加し、保存3失敗と復元後の固定幅着弾を限定追試した。新規Sessionをそのまま使った飛翔中実JSON往復も確認。初回末尾の不正幅/預かり拒否2件は正常な復元可能baseから再確認し、拒否理由が`invalid_entity_shots`であることとSession非変更を確認した。ゲームの保存直前rebuildや拒否条件の緩和は加えていない。初回結果は保持し、無関係な条件は再走していない。未解決の実装FAILは0。

4幅の最大消費/中心、混在障害/既存草/占有/移動helper、予算不足時の手計算順、予算0、飛翔中の残高/地面/helper変更、重複着弾、0有効・壁返却、種1での敵/巣攻撃、飛翔中JSON保存/復元、旧弾default、不正保存の原子的拒否を確認。GPUは実表示とHUD、幅変更時の中心、射程と発射先一致、敵予測時の表示、HUDクリック漏れ防止、マップ非表示、更新説明、nearest/整数拡大設定と最小化維持を確認した。

## 描画の目視確認

`preview_7_insufficient.png`（緑5/黄44）、`preview_3_affordable.png`（緑9）、`preview_attack.png`（範囲なし、種1・攻撃）、`help.png`を実際に開いて確認。地面投影の薄いセル、種アイコン/数、通常HUD、説明に欠け・はみ出しなし。輪郭線を追加せず、640×360の既存nearest表示を維持。ユーザーの美術・楽しさ評価を代行していない。

## 保全・終了

`context.json`に実ユーザー旧保存3ファイルと保護対象ソースの開始hash、`freeze.json`に前後照合、対象ソース/試験hash、残存プロセス・override確認を記録。実ユーザー保存は読取hashのみ。所有不明プロセスの停止、OS入力、前面化、カーソル操作なし。GPU開始/終了の両方でrootのunfocusable/minimizedを確認。

証拠作成時、index状態を記録する目的で誤って`git write-tree`を呼び、index.lockの権限拒否で失敗した。再試行・権限要求をせず親へ報告した。stage/commit/branch/pushは行っていない。親commitが並行するためindexのhash一致を合格条件にしていない。

NOT_RUN: 物理入力、広い回帰、全照明/解像度/長時間負荷、楽しさ/最終バランス、移動対象の未来予測、マップ端の専用実行試験。後続食害直後の保存とactive整合は既存基盤の別課題として親がWATER票へ記録済みであり、AREAでは変更していない。

実装・自己検証・画像確認を完了して編集/実行停止。独立検証へ引き渡し、最終受入は親が判断する。文書担当へは本差分、初回fixture失敗と限定追試、最終未解決FAILなし、NOT_RUN、保存保全と描画証拠を渡す。
