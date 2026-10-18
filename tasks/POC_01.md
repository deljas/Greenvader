# POC-01 3D共通基盤・座標と解像度切替

## 管理欄

- ID: POC-01
- 状態: 完了
- 担当ツール: なし
- 担当セッション: なし
- 更新日: 2026-10-18
- 予約中の編集範囲: なし（解除済み）
- 予約中の共有資源: なし（Godotプロセス残なし）
- 最終担当: claude-20261018-poc-opus

## 目的・依存

town_labの表示とgreening_mapの論理接続を読み、3D PoCの起動基盤を一つにする。WorldState等の論理状態を保持し、2Dの表示Nodeへ直接依存しない境界を作る。

依存: なし。最初に取得する。実行順・優先度の正本は[開発計画](../docs/03_DEVELOPMENT_PLAN.md)。取得と状態の正本は本票。

## 対象・編集と役割

- 対象: 共有 `C:/godot/greenvader`。計画時HEADは `99013702eaf36db72a64d60d284680fb834f13c5`、多数の既存未コミット試作を含む。取得時に現HEAD/差分を再確認し、他者の成果を破棄しない。
- 編集候補: scripts/poc/ の共通座標・セッション・入力境界、scenes/poc.tscn、tests/poc/base/、launchers/README.mdとPoC専用入口（候補）。候補は予約ではない。親が取得時に実ファイルと共有資源を記入し、必要なら本票内で実装割当を分ける。
- Claude親が設計/取得/統合/最終判定、Sonnet実装と別Sonnet独立検証、Haikuは確認済み記録。子の再委任禁止。Codexは今回計画文書のみ担当。
- 資料: AGENTS.md、tasks/README.md、[企画書](../docs/01_GAME_DESIGN.md)、[技術方針](../docs/02_TECH_AND_ART.md)、[STATUS](../docs/STATUS.md)、[DECISIONS](../docs/DECISIONS.md)、関連する旧P1/P2票、[町試作](../docs/TOWN_LAB.md)。
- 禁止: 他票の予約/検証凍結範囲、外部納品原本の編集、既存セーブの破棄、無関係な美術磨き込み、権限設定変更。Godot/import/共有文書/Git操作は同時占有しない。
- OSレベルの入力送信・フォーカス奪取・カーソル移動は禁止。入力はエンジン内注入、撮影は前面化なし。物理入力はユーザー手動確認。
- 確定ルールは維持。数値・内部設計は可逆的初期値として調整可、確定仕様を変える必要は親へ返す。

## 合格条件

- 640×360 / 960×540を実行中に切替可能。同じカメラ範囲・世界寸法を維持し、1920×1080ではnearest 3倍 / 2倍。非整数窓では整数倍率＋余白。収まらない解像度は黙って縮小せず、選択不可または明示した低い設定へ切替。
- 固定正投影クォータービュー（試作の仰角30°/方位45°を初期値）、画面上が北。仮2D人間spriteで歩ける。世界座標と論理座標の往復、地面クリック変換、余白/UI上の誤入力拒否を確認。
- 1論理セル=0.4m、既存4論理px=1セルを接続の初期値とし、定数を集約。射程・速度・回収距離も変換し、画面解像度で変化しない。これは画面上4px固定の要求ではない。
- WASD等はInputMapから画面方向へ変換し斜め移動を正規化。世界状態の正本を一つにし、town_labのキー辞書や別時計を本編の第二の状態にしない。
- 切替でプレイヤー位置・状態・照準先が飛ばず、spriteと影が同期し、輪郭線なし。カメラ追従の画素のにじみを両設定で短く実画面確認。旧run_gameとlabはこの段階では保持。

## 証拠・終了条件

- 証拠: `evidence/poc/01/` に対象版/実差分/再現手順/主要ログ/必要な画像とPASS・FAIL・NOT_RUN。旧証拠を書き換えない。
- 検証はほどほど。長い時間条件は早送り、1条件1回、回帰一式1回。ヘッドレス起動だけなら描画はNOT_RUN。
- 現在は計画のみで未実装・未検証。親が合格条件と証拠を確認した範囲だけ完了にする。
- 中断時は残差分・未確認・次の一手・所有プロセス・子の停止・予約解除を残す。担当移譲を状態ラベルだけで済ませない。


## 親の設計判断（2026-10-18、claude-20261018-poc-opus）

- 基準: HEAD `99013702eaf36db72a64d60d284680fb834f13c5`＋既存未コミット差分（取得時 `git status --porcelain` のsha256 `726a77e0…ebe2`）。既存差分は保持し、PoCは新規ファイル中心に追加する。
- 構成: `scripts/poc/` に表示非依存の `poc_config.gd`（定数集約）、`poc_coords.gd`（世界m⇔論理px⇔セル）、`poc_session.gd`（WorldState/SimClock/各Simの唯一の所有者、pause・早送り）、`poc_input.gd`（InputMap登録）と、表示層 `poc_main.gd`（SubViewport描画・カメラ・解像度切替・UI）、`poc_actor.gd`（仮sprite＋影板）。新規`class_name`は使わずpreloadで参照し、global class cacheへの依存を増やさない。既存のclass_name（WorldState等）は利用可。
- 座標: 論理(x,y)→地面(X,Z)=ORIGIN+論理px×0.1m（4論理px=1セル=0.4m）。カメラは正投影、仰角30°/方位45°（town_labと同じ）。画面上=北=地面(-1,0,-1)方向、画面右=(+1,0,-1)。
- 解像度: 640×360/960×540。`camera.size`（縦の見える範囲m）は両設定で同一。SubViewportとwindow.content_scale_sizeを切替え、整数stretch＋余白。仮spriteは「1テクセル=1画面px」となるよう解像度別フレーム（640: 32×48原図の1/2=16×24、960: 3/4=24×36のnearest近似）を使い、pixel_sizeをカメラから導出する。960用の0.75縮小は仮素材の近似として限界に記録する。
- 町labとgreening_mapは読むだけで変更しない。必要部分はPoC側へ複製・整理する。

## 引き継ぎ・完了記録（2026-10-18）

- 対象: HEAD 9901370＋未コミット差分。PoC新規ファイルの凍結sha256（先頭12桁）: poc_actor 5be6605dc78a、poc_config 602b61d2623c、poc_coords bc0e62ac0092、poc_input bf8f88fce03e、poc_main 1f7ac949e7e8、poc_session 5c1f83cb09b0、scenes/poc.tscn ef5950dcf216、launchers/run_poc.bat a15d17ebd5f9。独立検証の開始・終了時に一致。
- 実装（Sonnet 5.5 実装担当）: 自己logic 40 PASS / GPU 14 PASS / 0 FAIL。証拠 `evidence/poc/01/`。
- 独立検証（別呼出しのSonnet 5.5）: 切替・座標・定数・単一時計・描画の5条件 PASS / 0 FAIL。証拠 `evidence/poc/01/independent/`。
- NOT_RUN: 物理キーボード/マウス、実1920×1080窓・非整数窓（1366×768等）の実表示、実際の窓リサイズイベント経路（テストはwindow_size_override）。GPU撮影は1280×720窓で行い、1080p画像はnearest拡大。
- 既知の限界: 仮spriteは1テクセル=1画面px方針で身長約1.23m相当。960用24×36は32×48原図のnearest 0.75縮小の近似。HUDは既定フォント。終了時ObjectDBリーク警告（機能影響なし）。
- 親判定: 合格条件の範囲で完了。物理入力はユーザー手動確認で補う。
- 履歴: 2026-10-18 claude-20261018-poc-opus 取得→検証待ち→完了。予約解除。
