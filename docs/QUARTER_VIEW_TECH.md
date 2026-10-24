# クォータービュー技術確認（TECH-QV-01）

更新日: 2026-10-15。親は専用マップでの技術確認と素材制作条件の整理を限定受入した。これは美術品質の承認、完成素材の承認、通常ゲームへの統合完了を示さない。

## 試験の範囲と方式

対象はHEAD `99013702eaf36db72a64d60d284680fb834f13c5` 上の専用シーン・スクリプト・起動bat。初回対象8件は[自己manifest](../evidence/quarter-view/self/source-manifest.json)、マウス修正後は9件の[r2 manifest](../evidence/quarter-view/self/source-manifest-r2.json)で固定した。既存のWorldStateとWalkerの論理座標・4単位セルを維持し、表示アダプターでのみ2:1 dimetric投影 `P(u,v)=(u-v,(u+v)/2)`、逆変換 `(u,v)=(x/2+y,y-x/2)` を適用した。参考画像の投影角を厳密に復元したものではない。

画面方向の入力を正規化し逆変換してWalkerへ渡すため、画面上の移動速度は各方向100内部px/s、斜めも同速。論理軸上の速度は等しくならない。既存の緑化グリッドとWorldStateは変形せず、表示と操作を専用試験内で変換する。

花は既存の16×16px仮表示をそのまま使った。衝突footprintと建物基底を同じ論理領域から作り、建物は画面の1px幅列に分けて列ごとの前端足元YでY-sortする。建物の奥側の上物が花に重なると上物全体をalpha 0.28へ落とす。これは単純な閉じた箱での最小遮蔽策であり、局所透過の実証ではない。屋根に衝突は付けない。

専用シーンだけ960×540のviewport、nearest、整数画素位置とし、`launchers/labs/run_quarter_view_lab.bat` が960×540を、`launchers/labs/run_quarter_view_lab.bat --1080` が1920×1080を起動する。カメラ追従時もシミュレーション位置は連続値に保ち、表示位置とカメラ位置を整数に丸める。

## 自己検証と親の確認

自己検証r1の [logic-results.json](../evidence/quarter-view/self/logic-results.json) は16 PASS / 0 FAIL / 2 NOT_RUN、[gpu-results.json](../evidence/quarter-view/self/gpu-results.json) は24 PASS / 0 FAIL / 1 NOT_RUN。logicのNOT_RUNはGPU未実施項目と物理入力、GPUのNOT_RUNは物理入力。両結果は重複項目があるため件数を合算しない。独立検証r1でマウスイベント経路のFAILが見つかり、実装者が専用labのイベント座標保持を修正した。マウス関連だけのr2限定再検証は[3 PASS / 0 FAIL](../evidence/quarter-view/independent/mouse-r2-results.json)。r2は全回帰を再走したものではない。

GPU実画面は [正面](../evidence/quarter-view/self/front_960.png)、[建物の後ろ・透過あり](../evidence/quarter-view/self/behind_faded_960.png)、[建物の後ろ・透過なし](../evidence/quarter-view/self/behind_opaque_960.png)、[左手前](../evidence/quarter-view/self/left_front_960.png)、[右手前](../evidence/quarter-view/self/right_front_960.png)、[カメラ斜め移動](../evidence/quarter-view/self/diagonal_camera_960.png) に保存した。親は正面・背面・右手前と1080p実画面を確認し、仮建物、足元通路、背面透過、前後の表示順を視認した。美術品質の評価は含まない。

自己報告によれば、PrintWindowで取得した実1920×1080クライアント画像と同時点の960×540 GPU画像を比較し、518,400個の2×2ブロックすべてが一致、ブロック内の不均一0。エンジンimportと専用シーンのheadless smokeは終了コード0・ERRORなし。初期フォーカス不変を示す読み取り証拠はNOT_RUN。OS入力送信、前面化API、カーソル移動は使用していない。

親の最終保全記録では、r2の専用9ファイル、通常ゲーム127ファイル、既存の未コミット非文書成果63件が不変。`project.godot` と通常ゲームの解像度640×360は変更していない（[final-integrity.json](../evidence/quarter-view/final-integrity.json)、[r2 integrity](../evidence/quarter-view/independent/integrity-r2.json)）。親は実装差分・画像・ログを確認し、専用技術確認と素材条件の整理だけを限定受入した（[親の受入判断](../evidence/quarter-view/parent-acceptance.md)）。

| 条件 | 現時点の記録 | 証拠・限界 |
|---|---|---|
| 専用シーン起動・960×540表示 | 独立検証 PASS、親受入 | [independent report](../evidence/quarter-view/independent/report.md)、通常ゲーム別プロセスsmokeもPASS |
| 前後左右の描画順・背面遮蔽 | 独立検証 PASS、親受入 | 花の前/左右82不透明画素一致。背面の不透明時0/82、透過時は視認。閉じた単純箱での確認 |
| 壁足元と衝突・通路周回・低障害物 | 独立検証 PASS、親受入 | 四面停止位置、近接周回、低障害物接触。別プロセス通常ゲームsmokeは1回PASS |
| 画面方向・斜め等速 | 独立検証 PASS、親受入 | 実physics入力経路へGodot内注入。画面上100px/sの範囲 |
| マウス座標変換・注入・地面マーカー | r1 FAIL後、r2限定再検証 PASS、親受入 | r1のFAIL/診断は保持。r2で3 PASS / 0 FAIL、マウス条件のみ再取得。r1の全検証や通常スモークを再実行していない |
| カメラ移動の画素安定 | 独立検証 PASS（限定） | 斜めcamera位置等の整数性と静止画を確認。連続動画・全位置網羅ではない |
| 1080pへの実2倍表示 | 独立検証 PASS、親受入 | 実native画像で全518,400ブロック一致、ブロック内不均一0 |
| 初期フォーカス不変の読取比較、物理入力 | NOT_RUN | OS入力・カーソル移動・前面化APIなし |
| HUDセル文字の追従 | 既知制限 | マーカー・座標は現在値だが文字表示は1 physics tick遅れる。今回の確認を阻害しない |

親は上記の限定範囲を受け入れた。これは一般建築や美術品質の承認、通常ゲームへの統合完了を示さない。

## 美術制作へ渡す試験条件

以下はこの単純な試験マップから得た制作向けの具体値・候補で、一般の建物全般の保証ではない。

| 項目 | 試験値・制作時の扱い |
|---|---|
| 地面表示格子 | 論理4×4単位が画面8×4pxの菱形。既存の状態格子を保持する |
| 地面素材のまとまり候補 | 論理16×16単位=32×16px、または32×32単位=64×32px。4単位の緑化セルと別の美術単位。960基準の1px単位で描く |
| 建物 | footprint 144×144論理単位（36×36セル）、高さ112画面px、外接画像288×256px。拡縮・回転なし |
| 建物原点 | 画像左上基準で南の足元角 `(144,256)`。基底の角 `(144,112),(288,184),(144,256),(0,184)`。原点とfootprintをメタデータで保持 |
| 試験通路 | paving範囲 x=256..576、y=224..488、建物footprint x=304..448、y=272..416（論理単位）。外側余白は左48・右128・上48・下72単位。低障害物との最小gapは32単位 |
| 低い障害物 | footprint 48×24論理単位、高さ12画面px、外接画像72×48px。立体の高さと地面衝突範囲を別に扱う |
| 分割・深度 | 壁と屋根を編集レイヤーで分離。ゲーム内ではfootprintに応じて前端Yを持つ列または帯に分割し、各前端足元Yでsortする。試験は1px幅列。建物全体を南角のY一点でsortしない |
| 独立partが必要な箇所 | 出入口上枠、門、橋・アーチ、ひさし、張り出す屋根、手前の柵、奥の壁、植生は、通れる地面や深度が異なるため独立part/深度/衝突情報を持たせる。今回の成立範囲は単純な閉じた箱 |
| 画素条件 | nearest、mipmapなし、整数配置、非整数拡縮・回転なし。高さは画面上の垂直px。地面に広域の明暗を直接描き込まない |

本格的な草地・建物素材は今回制作していない。これらの値は素材設計の入力条件であり、ユーザーによる美術品質の承認を意味しない。

## 通常ゲームへ統合する場合の残課題

- 通常ゲームの `RegionView` は4×4pxセルの平面ブロック描画。既存WorldState/Walkerを保った表示アダプターの設計と、通常シーンへの個別統合作業が必要。
- 弾道、敵、植物、拾い物、照準、射程UIの座標変換を統一し、論理距離を使う判定と画面等速入力の関係を決める必要がある。
- 壁・屋根の列/帯へのアトラス制作・書き出し、建物どうしの複雑な重なり、局所遮蔽、植生・開口部の前後関係、表示範囲のchunk化、描画性能は未検証。288列+72列の試験値は本番性能保証ではない。
- 他解像度で内部解像度を固定/可変にするか、余白をどう扱うかは未決定・NOT_RUN。
- 物理入力経路と初期フォーカス不変の読み取り確認は未実施。
- 複雑な開口・屋根張り出し・複数建物の重なり、量産素材、描画性能、通常ゲームへの移植、保存・戦闘等の全面回帰は対象外・NOT_RUN。

## 証拠

- [実装・自己検証報告](../evidence/quarter-view/self/report.md)
- [親の限定受入](../evidence/quarter-view/parent-acceptance.md)
- [自己検証結果](../evidence/quarter-view/self/logic-results.json) / [GPU検証結果](../evidence/quarter-view/self/gpu-results.json)
- [r1独立検証報告](../evidence/quarter-view/independent/report.md) / [r2マウス限定結果](../evidence/quarter-view/independent/mouse-r2-results.json)
- [r2対象固定manifest](../evidence/quarter-view/self/source-manifest-r2.json) / [最終保全記録](../evidence/quarter-view/final-integrity.json)
- [親の現状調査・方式選択](../evidence/quarter-view/parent-investigation.md)
- [開始時既存成果保全](../evidence/quarter-view/baseline-existing.json) / [通常ゲーム基準](../evidence/quarter-view/baseline-normal-game.json)
