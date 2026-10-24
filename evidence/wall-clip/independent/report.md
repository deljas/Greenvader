# TECH-3D-10 独立限定検証

2026-10-16 / HEAD `99013702eaf36db72a64d60d284680fb834f13c5`＋共有未コミット成果。対象manifest SHA256 `9d0d43d42f8fb154c158b0875a1e492527b192c5051d2f9c07568571f6fa4c37`。Windows / 提出GPU: Godot4.7.2 Vulkan Forward+ RTX5070Ti。

**5 PASS / 0 FAIL / 3 NOT_RUN**。作業票・実差分・製品actor/session・試験経路・rawと代表GPU7枚を確認。独立Godot再実行なし。

| 条件 | 結果 | 方法・根拠 |
|---|---|---|
| wall_clipping_fix | PASS | 実差分/ソース・提出GPU目視: A/B右壁beforeで頭/胴が欠け、afterで全身が見える。固定角画像も欠けなし。actorはyaw直立＋高さ補正。raw8組のcornersから独立に投影16×24と上下XZ不変を再計算し一致。 |
| local_collision | PASS | 実session・raw幾何再計算/自己回帰レビュー: sessionは局所HALFと説明だけの変更で0.10→0.28m。A/B前/右壁と置換固定角の5地点をfootprint境界＋0.28mと比較、最大誤差約0.00000031m。自己logic13PASSと1.5秒壁押し経路をレビュー。独立runtime再実行ではない。 |
| depth_shadow_reflection | PASS | 実actor・実GPU/自己rawレビュー: depth無効化なし。behind画像は完全遮蔽し自己計測0/168、壁側は168/168。frame4×flip2のtexture/flip/physical foot同期rawを確認。反射画像に直立キャラ、反射ON/OFFの320画像で42px差。影板は同じ補正高さを使用。 |
| pixel_projection | PASS | 提出GPU独立offline: after_A_rightは640×360/1920×1080、全RGBA画素nearest3一致。raw足元は整数pixel付近。16×24 nearest fixture/alpha discardを維持し、移動は連続で表示だけsnap。 |
| freeze_preservation | PASS | 独立SHA256/ログ: 指定manifest digest一致、source7件・保全114件・証拠63件が全件一致。ground/map/water/shaderも保全内。before/after/corner exit0、stderr空。 |
| independent_engine_run | NOT_RUN | 未実施: 既存実GPU/raw/ソースが足りるためGodot再実行・追加入力・独立paired visibility計測なし。168/168等は自己GPUの計測をレビューしたもの。 |
| native_physical_input | NOT_RUN | 未実施: native/BAT起動・フォーカス・物理入力。OS入力/前面化/カーソル操作なし。ユーザーGodotへ操作なし。 |
| broad_regression | NOT_RUN | 範囲外: 全位置/全角度/連続動画/長時間/性能/全ゲーム回帰。全角での壁押しや全frameのGPU画像を新規網羅していない。 |

角は初回after-rawの滑走位置を証拠として採らず、corner-raw/resultsと差替PNGを採用。実座標(0.2800003,1.0800003)を独立に確認。cornersからの投影再計算・境界座標・nearest・反射差は `offline-checks.json`、凍結/保全は `hash-checks.json`。hashは1回のみ。

限界: 縮小16×24の仮sprite、無受光、光向き影板は体厚を持たない近似。足元判定拡大はこの小マップのみに作用し、地形や成長/資源ルールは変わらない。表示修正で影の物理高さも増える。全位置の見た目保証や美術承認はしていない。

独立証拠だけ保存、製品/docs/票・他者差分は変更なし。GodotやGUI/OS入力を新規実行していない。編集停止・共有実行資源返却。最終受入は親判断。
