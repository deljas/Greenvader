# POC-06 自己検証報告（親が実装担当の返却本文から要約転記）

- 対象: HEAD 9901370＋既存未コミット差分。新規 scripts/poc/occlusion/occlusion.gd（Node非依存の判定・ヒステリシス・alpha補間）、occlusion_view.gd、data/poc/occlusion.json、tests/poc/occlusion/logic.gd・gpu.gd。変更 poc_main.gd、assets/placement_view.gd。wall_view.gdは未変更。
- 判定: 主人公の足元・胴・頭・胴±0.2mの5点からカメラ方向へ線分、MeshInstance世界AABBで粗判定→三角形で精判定。進入は即時、解除はrelease_hold 0.35s後。fade_out 0.15s / fade_in 0.25s、target_alpha 0.4。
- 透過の方式: 最前面の面だけを0.4で合成する single_layer（深度のみの前段パス＋next_passの色）。DEPTH_DRAW_ALWAYS・ALPHA_DEPTH_PRE_PASS・不透明のみとの比較画像 depth_variant_*_960.png。
- 影/反射: 透過中の表示は影を落とさず、影専用複製（layer 8）で地面の影を維持。反射用の不透明複製（layer 16）は透過中のみ反射カメラへ描画。WallVegはGeometryInstance3D.transparencyで追従（反射内では半透明のままという軽微な差）。
- 結果: occlusion logic 35 PASS、回帰 base 40 / assets 45 / play 69 / combat 48 / environment 81 PASS、GPU 22 PASS（640/960×昼夜、植生成長済みミル背面、透過時の主人公可視 162/364px、透過なし0px、ミル外の差分0px、影複製・反射複製の効果確認、離脱後の復帰）。0 FAIL。
- NOT_RUN: 物理入力、実1080p窓、実速度での通過の目視、実水面での反射（既定fixtureに湖なし）、実マップ性能、敵の遮蔽。
- 残課題: 開始位置(24,20)がruin_01の背後で開始直後から透過→POC-07で開始位置を見直す。カメラ cull_mask は layer 16 以外。
