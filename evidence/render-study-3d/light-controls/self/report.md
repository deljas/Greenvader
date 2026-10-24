# TECH-3D-04 太陽角度と周回点光源

- 対象版: HEAD `9901370` と既存ART/TECH差分上の専用追加。Godot 4.7.2 / Vulkan Forward+ / RTX5070Ti。実装凍結・編集停止済み。
- 変更: `scripts/render_study_3d/light_lab.gd`、`scenes/light_lab.tscn`、`run_light_lab.bat`、`tests/render_study_3d/self_light_capture.gd`、本証拠。既存 `sprite_shadow_lab.gd` だけは真上光で水平normalがゼロになる場合のfallbackを追加。変更前原文 `before/` と限定差分 `existing-safety.patch` を保持。その他の既存8ファイルは前後SHA一致（`integrity.json`）。背景・材質・通常ゲーム・project.godot・過去証拠・共有文書は変更していない。
- 実装: 方位0〜360° / 仰角−90〜90°をsliderとSpinBoxで連動（0.1°刻み）。方位0°=+Z、90°=+X。Euler basisで太陽の方向を作り、仰角<=0では直射OFFと明示。太陽checkboxでも直射を切替。初期は従来の昼方向。
- 点光源: 影有効OmniLight3Dが半径X5.3/Z4.6、高さ2.4を周回。初期は青白色、energy5、range11、90°/秒。点光源ON/OFF、自動周回ON/OFF、停止中の角度操作を用意。小球markerはunshaded/影cast OFF。位置が建物の裏に回ると、遮蔽により効果が奥側へ移る。
- 複数影: worldはlayer1、太陽専用板はlayer2(bit2)、点光源専用板はlayer3(bit4)。両ライトのlight_cull_mask=7、shadow_caster_maskは太陽3 / 点光源5で世界を共通にし、専用板を分離。共通frame/flip/footから両板へ同期。板は各ライトの水平向きへyawを揃える美術近似。表示spriteは引き続きunshaded/cast OFFで、キャラ受光の試作ではない。

## 限定確認と結果

- GPU自己 **15 PASS / 0 FAIL**（代表2条件のサイズ/3倍項目を含む）。終了コード0、stderr空（`gpu.log` / `checks.json` / `process.json`）。
- UI経路で135.7°/25.4°、315.2°/61.2°を設定しslider/SpinBox連動とGPU陰影変化を確認。仰角90°/−90°でsun/影板basis有限、−90°で直射OFFとUI明示を確認。sunはlook_atを使用しない。
- 点光源単独45°/225°とOFFのGPU画像を採取。位置/OFFによる背景画像差を確認。停止中の角度操作、自動周回の再開による角度進行を確認。自動周回中に値を変えると次の更新から進むため、任意角度を止めて見る場合は「自動周回」をOFFにする。
- 点光源単独45°で、太陽専用板だけを非表示にしてもworld画像が全バイト一致。点光源専用板だけを非表示にすると **616画素** が変化。単なるmaskプロパティ一致だけで分離を合格にしていない。
- 全58採取状態で両板のtexture/flip/foot同期と有限basisを確認（`snapshots.json`）。表示spriteとmarkerのcast OFFもPASS。
- UI付きGPU root画像は640×360。1920UI PNGはその同じGPU root画像からCPUで最近傍3倍に書き出した提示用画像で、native撮影や別GPU1920読取りとは区別する。背景のみは別GPU1920 viewportを読取り、640の全画素nearest3倍と一致。
- `default_ui_640.png`、`point_only_45_ui_640.png` / `point_only_225_ui_640.png` を目視。日本語UIと数値が読め、主要建物/歩行fixtureを隠さず、点光源の照明/硬影が見えることを確認。極端角度は有限性と代表画像までの限定確認。
- `parse.log` はheadlessで構造load後に「GPU NOT_RUN: structural load only」で終了したもの。dummyを描画合格にはしていない。GPU実行はHidden/unfocusable、OS入力・カーソル・前面化なし。Godot終了・プロセス0件で資源返却済み。

## 動作手順と証拠

- `run_light_lab.bat` で専用画面。太陽ON、方位/仰角、点光源ON、自動周回と周回位置を左パネルで操作。歩行は自動。既存の専用batや通常ゲーム起動は別。
- UI画像: `default_ui_1920.png`、`point_only_45_ui_1920.png`、各640元画像、`sun_135_25_ui_640.png`、`sun_315_61_ui_640.png`、`sun_zenith_ui_640.png`、`sun_below_horizon_ui_640.png`。
- 分離対照: `point_only_wrong_sun_board_OFF_ui_640.png`、`point_only_own_board_OFF_ui_640.png`、`point_only_225_ui_640.png`、`point_OFF_ui_640.png`。機械比較はUIの表示値に左右されないworld画像から行った。
- 動画 `orbit_controls_4s.mp4`: 48枚/12fps/4秒。決まった角度を各サンプルへセットするため自動更新は停止して採取し、UIの周回位置が進む提示動画。実時間FPS/性能測定ではない。元は `frames/orbit_000_ui_640.png`〜047。FFmpegでnearest3倍してH.264 CRF16/yuv420pにしたため、PNGとの色/画素完全一致は保証しない。0/12/24/36フレームの復号接触シート `video_decode_contact.png` も目視。
- ソース・PNG・MP4・主要結果のSHAは `source-manifest.json`。動画化/復号はCPU libx264で、GPU資源返却後に実施。

## 未検証・残課題・文書担当へ

- NOT_RUN: nativeウィンドウ/初期フォーカスの実測、物理キーボード/マウス経路、全方向/全位置、長時間のちらつき/性能、複雑な多数ライト。画像は実GPU viewport読取りで、native表示検証ではない。
- 影板yawは輪郭を見せる近似であり身体の厚みの復元ではない。硬影でも残るサンプリングを完全二値とは呼ばない。表示sprite受光、美術調整、光の物理単位/夜の環境光設計は対象外。
- 親・独立担当の限定確認とユーザーの操作/見た目判断を残す。通常ゲーム統合、正式解像度変更、Unity移行、P2再開は行っていない。
