# TECH-3D-02 硬い影と控えめな色・階調補正

- 対象版: HEAD `9901370` 上の既存3D試作＋今回の専用2ファイル追加。Vulkan Forward+ / Godot 4.7.2 / RTX5070Ti。実装・撮影対象は凍結済み。
- 変更: `tests/render_study_3d/self_capture_style.gd`、`assets/render_study_3d/style_grade.gdshader`、本証拠フォルダのみ。既存study/geometry/concrete/scene/project.godotの5件は実行前後ハッシュ一致（`integrity.json`）。共有文書・作業票は編集していない。
- A: 同じ640×360昼、カメラ/太陽の方向・色・強さ/形状/材質を保持して影設定だけ変更。`RenderingServer.SHADOW_QUALITY_HARD`、`shadow_blur=1.0`、`shadow_bias=0.10`、`shadow_normal_bias=1.0`、angular_distance=0。影atlasは元の4096のまま。
- B: Aの描画済みGPU viewportを停止して同じフレームを参照し、640×360のGPU canvas shaderで補正。その後別GPU viewportへnearest3倍。暗部はわずかに青緑、明部はわずかに暖色。輝度だけ20段に丸めた値を20%混ぜ、元の連続階調を80%保持。RGB別の減色、輪郭線、ぼかし、ディザ、新しいノイズは追加していない。1回のtexture sampleと色計算のみで、明示的なgamma変換/powはない。既存材質の細粒は維持。

## 実行した確認と結果

- 最終の機械的確認: A/Bそれぞれの1920×1080 GPU画像が、各640×360画像の正確なnearest3倍と全画素一致。A/B共通の元フレーム保持、A/B画像の差、4PNGの保存もPASS（`capture-results.json`）。このバイト検証だけで視覚品質を合格としていない。
- 実画像確認: 元 `../640/noon_640.png` と最終Aを目視し、右側へ伸びる地面投影影の境界が明瞭になったことを確認。最終A/Bで初回の規則的な全面斜線は解消。1920画像でパラペット、窓庇、瓦礫、建物の足元の影を確認し、目立つ付け根の浮きは認めなかった。静止画での限定確認であり全接触点の厳密評価ではない。残るshadow-mapサンプリング/補間を完全二値化とは呼ばない。
- 最終プロセスPID14528、OS終了0、stderr空（`process.json` / `capture.log` / `stderr.log`）。root.unfocusable=true、Hidden起動。OS入力・カーソル移動・前面化APIは使用していない。全Godotプロセス0件、GPU資源返却・編集停止済み。
- 初回はHARD＋blur0＋既存bias0.035/normal_bias0.45で屋根/地面全体に自己影の斜線が出て**視覚FAIL**。機械的な3倍一致がPASSでも提示不可とした。初回画像・結果・ログ・撮影コード原文は `initial/` に保持。親の指示に従い影設定3値だけ変更し、修正後1回再撮影した。設定ごとの総当たりや原因の単独切り分けは実施していない。

## 出力・未検証・残課題

- 最終A: `A_hard_shadow_640.png` / `A_hard_shadow_1920.png`。
- 最終B: `B_hard_shadow_grade_640.png` / `B_hard_shadow_grade_1920.png`。
- hash: `source-manifest.json`。旧証拠は変更なし。画像は実GPU viewport取得で、生成画像や事後のCPU色加工による代用ではない。
- NOT_RUN: 動的ちらつき、native表示/初期フォーカス実測、物理入力。他の太陽方向/距離/多数物体/性能の評価、回帰一式は実施していない。
- 親・独立担当が最終画像/差分を確認する。A/Bの美術採用はユーザー判断。通常ゲーム統合、解像度採用変更、Unity移行、P2再開は行わない。
