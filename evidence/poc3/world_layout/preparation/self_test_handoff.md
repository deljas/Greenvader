# WORLD-LAYOUT 接続後自己試験の準備

対象: 共有HEAD `2e5ad7ef579c4640857e63914d5ea1482512db9b` とPRICING/SPRITE等の既存差分。取得票の指定に従い、今回の編集はtests/poc3/world_layout/self_logic.gd、self_gpu.gdと本証拠のみ。別SolのJSON・準備証拠を保全。town_03.jsonのSHA-256は既存引継ぎと同じ `A1E4F6109E03BB201538EBBD6A90AC2CB4F8C27056C10F0B92EC1D85E5CB7515`。既存静的14 PASSは再走していない。

## 用意した試験

- self_logic.gd: 隔離profileとSession.MAP_PATH==town_03をガード。中央(112,112)/224角/初期種60・HP水100、177成熟草と半径3m・初期3.54種毎分、全セルzone0未制圧を確認。
- combat.free_position後の全初期敵/巣の実位置で8m安全、最寄り巣12–16m・残り20m以遠・歩行可能地を測定。四方向の実巣へのnav経路を、プレイヤーと同じ幅のWalker.moveで各1回辿る。水辺(112,104)まで3.2mと隣接water、実補給で種を消費しないことを確認。
- 初期/30ゲーム秒の非接触休眠（advance_gameで早送り）、主人公接近、遠方への緑化接触を各独立fixtureで1条件ずつ。初期緑地へのhostile移動を実行し恒久免疫なしを確認。全敵・巣撃破後のzone安定と侵入禁止を確認するが、全体100％到達は本試験で扱わない。
- 隔離user://で新マップ保存復元、旧town_02の作業保存map拒否とsession不変、新town_03なのに2地域を宣言した不正状態の拒否・不変、死亡復帰のmap開始点を確認。
- self_gpu.gd: 起動時no_focus/minimizedとprofile/mapガード。通常main sceneからGodot内部クリックで新規開始し、開始HUD画像1枚、内部Tabで全体マップ画像1枚を取得。開始/終了の最小化・unfocusableを確認。画像は実行後に別途目視する。

両runnerは条件結果を記録してquit(1/0)する。未接続の旧マップで他条件を走らせない。内部入力はroot.push_inputのみ。CreateNewの一時override作成/削除、CONTENT予約/既存process、実保存前後hashとsource freezeは実行を許可された時の外側手順で行う。

## 接続時の注意

現時点の既存ゲームコードは未変更で、MAP_PATH/開始・死亡復帰(191,188)、zone0安定＋zone1未制圧、_check_zone/snapshotのindex1が残る。親の接続許可後にmap.player_start_cell、全体未制圧zone0へ合わせる。1セル0.02種/分と種60を維持し、旧250セル/5種毎分への補填をしない。

現在persistenceのmap照合は既にあり旧map拒否に利用できる。一方WorldStateの復元器は汎用の複数地域を扱えるため、town_03の1地域形状をsave整合で厳格に維持する場合はsession側persistenceでの追加検証が必要。上記不正2地域の条件を準備した。復帰/新規/ロードそれぞれに旧ハードコードを残さない。

四方の経路は既存準備のAABB近似PASSの代用ではなく、Godotの実placementラスタ化後に検証する。free_position後に距離条件が崩れた場合だけ対象配置の局所修正を親へ返す。ゲームテンポ/楽しさはユーザー試遊。

## NOT_RUN / 停止

Godot/import・構文チェック実行・headless/GPU/保存/操作はすべてNOT_RUN。SPRITE独立が実行資源、PRICINGがcoreを所有しているため、ゲームコード/既存データ/Git/共有文書・票を変更しない。OS入力/前面化/カーソル/プロセス停止なし。試験と記録の準備だけで編集停止。接続・実行許可を待つ。
