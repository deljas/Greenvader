# TECH-3D-03 歩行スプライトと輪郭影の同期

- 対象版: HEAD `99013702eaf36db72a64d60d284680fb834f13c5` と既存ART/TECH差分上の専用追加。Godot 4.7.2 / Vulkan Forward+ / RTX5070Ti。実装凍結・編集停止済み。
- 変更ファイル: `scripts/render_study_3d/sprite_shadow_fixture.gd`、`sprite_shadow_lab.gd`、`scenes/sprite_shadow_lab.tscn`、`run_sprite_shadow_lab.bat`、`tests/render_study_3d/self_sprite_shadow_capture.gd`、`assets/render_study_3d/sprite_shadow/fixture_0..3.png`、本証拠フォルダ。既存study/geometry/concrete/style/scene/project.godotの6件は前後SHA-256一致（`integrity.json`）。共有文書・作業票は変更なし。
- 実装内容: 自作コードから輪郭線なし32×48pxの4コマ歩行fixtureを生成し、カメラ正対の表示Sprite3Dと、同じalpha切抜きを持つ影専用Sprite3Dを別に配置。表示は影をcastしない。影専用はSHADOWS_ONLYでカラー描画しない。共通のフレーム/flip/論理足元から両者を更新し、表示時だけ共有の足元を画面整数へ丸める。両板の下端は舗装面y=0.015に対しy=0.016で揃える。
- ピクセル条件: カメラsize10.2 / 内部高さ360 = pixel_size約0.0283333。表示板の軸をカメラbasisへ揃え、1texelが内部1pxとなる大きさ。Nearest、alpha scissor、AAなし、固定カメラ。native用のwindow.content_scale_sizeと直下TextureRectも640×360へ実行時変更し、640→960の非整数中間拡大を避ける。1920×1080の別GPU viewportはnearest3倍。既存シーンのソースは変更していない。
- 影の方式と限界: 昼の元DirectionalLightとTECH-3D-02の硬影A設定（HARD / blur1 / bias0.1 / normal bias1）を維持。影の板は垂直で、yawだけ太陽の水平方向へ正対させる。これは輪郭を読みやすくする美術上の近似で、立体の身体の厚みを再現したものではない。影自体は板の高さ/位置/alpha形とライト方向に従う真の3D投影で、地面へ描いた楕円や貼り絵ではない。表示用はunshadedであり、キャラ自身の受光/明暗は今回対象外。

## 実行した確認と結果

- 最終GPU: **4 PASS / 0 FAIL**（`checks.json`）。代表640PNGと1920GPU出力の全画素nearest3倍一致、固定2コマの実影存在と輪郭差、全採取サンプルの同期を確認。OS終了0、stderr空（`process.json` / `gpu.log`）。
- `parse.log` のheadless試行には `NOT_RUN: real GPU required` のERRORがある。これは描画をdummyで合格にしないためのGPUガードで、最終GPU撮影のエラーとは区別する。全ログが無エラーだったとは扱わない。
- 固定足元/同一ライトの0コマと2コマを各影ON/OFFで取得。表示スプライトを保ち、影専用パーツだけ非表示にした各参照との差は、0コマ **284px** / 2コマ **250px**。差分maskの形も異なり、プロパティ一致だけで影の同期を証明していない。`fixed_pose{0,2}_{on,off}_640.png` と `shadow_mask_pose{0,2}.png`（CPU差分の診断画像）が証拠。
- `sync-frames.json`: 歩行72枚と固定4枚の各サンプルで、表示/影のtexture instance ID・左右反転・復元した足元の一致を記録し、76サンプル全てPASS。4コマ、左右反転サンプル36枚。最後に追加した後方遮蔽1枚のsnapshotも記録（全77記録）。
- 固定closeupで頭/腕/脚の投影輪郭と足元の接地を目視。後方位置1例 `behind_building_640.png` では、depth testにより仮キャラが建物に隠れることを確認。全位置/全角度の遮蔽や各足の厳密な立体接触を保証しない。
- 歩行は前面空地を4秒で往復するループ。t=i/18の72サンプルを採取し、18fpsで再生する動画を作成。これは提示用の時間軸で、実時間のFPS/性能測定ではない。MP4から0/18/36/54フレームを復号した `video_decode_contact.png` も目視し、歩行位置/腕脚/反転/影の変化を確認。動画プレーヤー上の全フレーム連続目視は未実施。
- 初回は影板をカメラyawに揃えていたため、昼の光が板へほぼ横から当たり、影が靴下の線程度になった。数値同期と実影差（45px/35px）は成立していたが、**視認性不足**と判断。初回画像/72連番/結果/旧lab原文は `initial/` に保持。親が許可した影板yawだけの修正後、影響する画像と連番を1回再取得した。追加の光条件/美術磨き込み/総当たりは行っていない。
- 起動はroot.unfocusable=true＋Start-Process Hidden。OS入力送信・前面化API・カーソル移動・外部操作ツールなし。全自己Godotプロセス終了、Godot0件で実行/import資源を親へ返却済み。追加importは不要、生成ImageTextureとコードを直接使用。

## 起動・証拠

- 手動起動: `run_sprite_shadow_lab.bat`。同じ昼の前面空地で4秒の自動往復。大きなUIや操作追加なし。通常ゲームの起動入口ではない。
- 動画: `walk_full_4s.mp4`（1920×1080）、`walk_closeup_4s.mp4`（1152×672、640元画像のRect(272,222,192,112)をnearest6倍）。どちらも72枚/18fps/4秒、H.264 CRF16 / yuv420p。圧縮と色差サンプリングがあるため、動画の全画素一致や元PNGと同一の色は保証しない。元のlossless PNGは `frames/walk_000_640.png`〜`walk_071_640.png`。
- 代表画像: `fixed_pose0_on_640.png` / `fixed_pose0_on_1920.png`、`fixed_pose0_closeup_6x.png`。closeupはGPU元PNGの整数crop/nearest拡大であり、別のnative撮影ではない。
- コードfixture PNGは技術用生成物で完成主人公アートではない。AI画像や外部素材は利用していない。ソース・fixture・PNG・MP4のハッシュは `source-manifest.json`。

## 未検証・残課題・文書担当へ

- NOT_RUN: nativeウィンドウ/初期フォーカス実測、物理入力、全光方向、自由カメラ、複数キャラ、多数の遮蔽物、長時間のちらつき/性能、動画プレーヤーでの連続全フレーム確認。
- 影板yawはシルエットの視認性を優先する近似。表示板のカメラpitchと影板の直立は異なり、立体身体と厳密一致する影や全足の接触ではない。表示unshadedのため昼夜のキャラ受光は別検討。
- 親・独立担当の限定確認とユーザーの見た目判断を残す。通常ゲーム統合、主人公完成デザイン、正式な解像度採用、Unity移行、P2再開は今回対象外。文書担当は上記の承認済み事実を記録し、子は共有文書を更新しない。
