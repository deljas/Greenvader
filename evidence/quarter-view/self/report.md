# TECH-QV-01 実装・自己検証報告

- 対象: HEAD `99013702eaf36db72a64d60d284680fb834f13c5` に専用シーン等の未コミット追加。既存の文書/ART成果は保持。`source-manifest.json` 参照。
- 環境: Godot 4.7.2 stable / Windows / Vulkan Forward+ / RTX 5070 Ti。
- 変更: `scenes/quarter_view_lab.tscn`、`scripts/quarter_view_lab/{lab,projection}.gd`、`run_quarter_view_lab.bat`、`tests/quarter_view/self_checks.gd` とそれぞれのGodot生成uid。通常ゲーム・project.godot・既存素材のソース変更なし。

## 起動・操作

`run_quarter_view_lab.bat` で960×540、`run_quarter_view_lab.bat --1080` で1920×1080。Godotエディタから専用シーンを実行してもよい。

WASD/矢印は画面方向、斜めも100内部px/秒。Fは遮蔽透過の比較、Cはカメラ追従、Rは開始位置。黄色の小さい菱形がマウス下の論理4単位セル。実マウス・キーボードによる操作は未実施。

## 実装方式

論理(u,v)は既存WorldState/Walkerの座標。表示P=(u-v,(u+v)/2)、逆変換=(x/2+y,y-x/2)。これは参考絵の厳密な測定ではなく専用2Dの2:1 dimetric試験。画面入力を正規化して逆変換し、既存Walkerへ渡す。したがって論理軸の速度は等速にはならない。花は既存PixelArt.flowerの16×16を非変形で使用。

建物footprintと低障害物を4単位格子へ登録し、同じfootprintから上物の色面を作る。屋根には別の衝突を付けない。大建物を画面の1px列に分割し、各列の最前端の地面Yをソート原点とする。同じY-sort親に花と列を置くため、建物全体の南端一点だけでは隠れてしまう左右の手前通路でも花が前に出る。地面<マーカー<上物・花を明示。

花の表示矩形が自分より手前にある上物の列と重なると、その建物全体のalphaを0.28にする。切り欠き/局所透過ではなく、専用マップでの最小の遮蔽対策。Fで無効にできる。カメラは花から画面上へ60pxずらして整数位置追従。シミュレーション座標は非整数のまま、表示とカメラを丸める。nearest、ズーム1、内部960×540を専用シーンだけで設定し、1080pではviewport整数2倍。

## 結果

- `logic-results.json`: 16 PASS / 0 FAIL / 2 NOT_RUN（このpass単体のGPU、物理入力）。
- `gpu-results.json`: 24 PASS / 0 FAIL / 1 NOT_RUN（物理入力）。論理とGPUの重複項目は合算しない。
- 四面の足元接触・一周通路・低い障害物、画面方向/斜め等速、エンジン内D入力注入、カメラ込みのマウス逆変換、遮蔽発動、整数表示変換を確認。
- 等速の数値許容差は0.02内部px。既存Walkerが0.25以下のfloat32小刻みを累積し、600付近で50px移動が50.00854pxとなるため。画像丸めより十分小さい。最初の0.001許容での失敗はこの丸め誤差。入力注入はphysical_keycodeに加えてkeycodeを設定して再実行しPASS。
- `front_960.png`、`behind_faded_960.png`、`behind_opaque_960.png`、`left_front_960.png`、`right_front_960.png`、`diagonal_camera_960.png`を実GPUで取得・目視。前後順序、裏の透過、左右の手前で花が前に出ることを確認。
- `overview_1080_native.png`はPrintWindowで前面化せず実ウィンドウclientを撮影。`overview_1080_960.png`は同時点のGPU内部画像。518400個の2×2ブロックで原画との不一致0、ブロック内不均一0、492色。CPU拡大画像による代用なし。
- `import.log`: 最終headless editor importは終了0、ERRORなし。`scene-smoke.log`: 専用シーンheadless起動は終了0、ERRORなし。
- 起動のsandbox制約でStart-Processが子生成前に待機したため中断し、同一Hidden起動を承認レビュー付きで実行して成功。GPUはroot.unfocusable=trueを最初に設定。OS入力・前面化API・カーソル移動なし。初期フォーカス不変の読み取り証拠は取得できずNOT_RUN。起動完了後のGodotプロセスはなし。
- importの初回sandbox失敗はAPPDATA/ログ相対パスの権限、次回はeditor設定safe-save権限。そのため検証用APPDATAを指定し、承認されたheadless importで正常化。キャッシュruntimeは証拠として不要なため自己生成した専用フォルダだけ削除。
- 通常ゲームの起動スモークは親指示により独立検証側へ委譲。全機能/保存/成長/長時間/性能/物理OS入力/他解像度は今回NOT_RUN。

## 美術制作へ渡す条件

| 項目 | 今回の具体値・推奨 |
|---|---|
| 地面の状態格子 | 4×4論理単位→画面8×4px菱形。緑化の基礎格子は保持する |
| 美術用のまとまり | 16×16論理単位→32×16px、32×32→64×32pxを候補とする。これは格子4単位とは別の素材単位。元画像は960基準の1px単位で制作 |
| 大建物 | footprint144×144論理単位（36×36セル）、高さ112px、画像外接288×256px、拡縮なし |
| 建物原点 | 画像左上から南の足元角(144,256)。基底の角は(144,112),(288,184),(144,256),(0,184)。原点とfootprintをメタデータに保持 |
| 低い障害物 | footprint48×24論理単位、高さ12px、外接72×48px。立体の高さと地面衝突を別扱い |
| 通路 | 検証建物の周囲に最低24論理単位、左右には48単位以上の平面を確保。花の足元半幅2単位/軸。素材の壁基底は必ず衝突footprintに合う |
| 分割 | 壁と屋根の編集レイヤーを分離し、ゲーム書き出しはfootprintに応じた前端Yのある列/帯へ。今回の実証は幅1px列。大きな一枚を南角Y一点ではソートしない |
| 別パーツが必要な場所 | 出入口の上枠、門、橋/アーチ、ひさし、張り出す屋根、手前の柵、奥の壁は通れる地面と深度が異なるので独立part/深度と衝突情報を必要とする。今回は単純な閉じた箱まで |
| 画素条件 | nearest、mipmapなし、整数配置、非整数拡縮・回転なし。高さは画面上の垂直pxとして描く。地面の広域明暗は素材に入れない |

## 統合時の残課題

通常ゲームのRegionViewは平面4×4のブロック描画なので専用表示アダプターへの移植が別途必要。弾道/敵/植物/拾い物/照準/射程UIも論理→表示の統一が必要。既存通常ゲームの入力速度の解釈、2D距離判定と画面等速の関係、分割atlasの制作/自動書き出し、建物同士が重なる複雑な構造、局所的な遮蔽、表示範囲のchunk化、他解像度の方針は未確定。今回の288列+72列方式を本番性能保証とはしない。美術品質の承認と通常ゲーム統合完了は今回の成果に含まない。

## r2 マウス限定修正

独立検証r1でマウス注入がFAIL。直接screen_to_ground変換は正しかったが、物理更新ごとにViewportのOS由来マウス位置を読み、注入MouseMotionの位置を使用していなかった。r1証拠と `source-manifest.json` はそのまま保持。

親指定に従い、`lab.gd`に最新のviewport内screen位置を保持し、`_input(InputEventMouseMotion)`で更新する処理を追加。初期値だけ_readyで取得し、その後の物理更新はカメラ更新後に保持位置から逆変換する。入力イベントとカメラ移動の両方へ対応し、物理OSマウスを動かす必要がなくなった。

`tests/quarter_view/self_mouse_r2.gd` をheadlessで1回実行し、3 PASS / 0 FAIL。camera(70,365)で注入screen(494,413)→logical(550,466)/cell(137,116)、マウス静止でcamera(40,344)へ変更→logical(514,460)、Viewport.push_input(local=true)の別位置screen(520,400)→logical(550,440)/cell(137,110)。証拠は `mouse-r2.log` と `mouse-r2-results.json`、新しい対象ハッシュは `source-manifest-r2.json`。Viewportへ既にmouse enteredが通知済みという無害な警告1件がある。ERRORなし。GPU再描画は自己側NOT_RUNとして独立側のマウス限定再確認へ渡す。回帰一式を再実行していない。OS入力・前面化・カーソル移動なし。専用シーン以外のゲームソース変更なし。
