# TECH-3D-01 実装・自己確認

- 対象版: HEAD `99013702eaf36db72a64d60d284680fb834f13c5` ＋既存ART/TECH差分＋専用3D試作の追加。Godot `4.7.2.stable.official.ed1daf0bf` / Vulkan Forward+ / NVIDIA GeForce RTX 5070 Ti。対象は `source-manifest.json`。実装凍結済み。
- 変更ファイル: `scripts/render_study_3d/{study,ruin_geometry}.gd`、`assets/render_study_3d/concrete.gdshader`、`scenes/render_study_3d.tscn`、`run_render_study_3d.bat`、`tests/render_study_3d/self_checks.gd` と `self_geometry_probe.gd`、本証拠フォルダ。通常ゲーム・project.godot・既存ART/TECH・文書・作業票は編集していない。
- 実装内容: 6×4.8の一階コンクリート廃墟。壁の実開口、壁厚のある窓の凹みと奥の暗い面、錆の閉じた扉と取手・庇・段差、屋根/パラペット/露出鉄筋、瓦礫、少量の独立した草パーツ。屋根本体は概ね平らなスラブで、欠けは角/輪郭/縁中心。屋根全体の大きな崩壊は作っていない。主人公・成長処理なし。
- 3D用材質: 自作spatial shaderでコンクリートの骨材・小さな汚れ/ひび/施工継目、舗装の0.86単位の正格子と細い目地/ひび、扉の青灰の塗装/錆を描く。写真や2Dドット絵を斜め面へ貼ったものではない。表面の固有の汚れと照明を分離し、地面の投影影や広域照明を材質へ焼き込んでいない。全ライト影は同じ3D形状に従う。
- 表示: 平行投影yaw45/pitch30、正方形の地面軸の傾きは画面上2:1、垂直辺は画面垂直。960×540の3D SubViewportから、nearestのTextureRectを持つ別1920×1080 SubViewportへGPU描画。TAA、MSAA、screen-space AA、DOF、glow、fog、SSAO、SSIL、SDFGIは使わない。輪郭線用passなし。元テクスチャの画素を斜め面で保持する主張はしない。最終出力格子の整数2倍を実証したもの。

## 実行した確認と結果

- 最終GPU: **15 PASS / 0 FAIL / 2 NOT_RUN**（`gpu-results.json`、`gpu.log`）。朝/昼/夕の各960画像、別GPU viewportからの1920画像は全画素が正確なnearest2倍と一致。
- 朝/昼/夕で太陽の方向/高度を変更。同じ材質・構図・環境光のまま、方向・長さの変わる地面影、壁の明暗、屋根上の縁の影を目視した。太陽位置は朝(8,4,-6)、昼(-5,10,6)、夕(-8,3.2,5)。既定は昼。
- 昼でshadow_enabledだけをOFFにした参照画像との差は **34,718画素**。実ライトの影が描画に寄与することを確認。影の焼込み画像ではない。
- 昼の短いカメラ並進を1回、5枚保存。先頭/末尾を目視し、窓・垂直辺・影に明らかな残像や全面にじみは認めなかった。サブピクセル位置で細い形/材質のサンプリングが変わるため、完全に静止した画素や全フレームでちらつきがないことは保証しない。連続動画・長時間評価は未実施。
- エンジン内の1キー注入で朝へ切替PASS。実物理入力は使用していない。UIの実native表示は未確認。
- 最終GPUプロセスPID17016は `Start-Process -WindowStyle Hidden -Wait -PassThru` で実行、**OS終了コード0**（`gpu-exit.txt`）、stderr空。全自己プロセス終了後、Godotプロセス0件を確認し実行/import資源を返却。画像は実GPU viewport読み取りであり、nativeウィンドウ撮影ではない。
- importは今回不要（画像素材なし、Shader/GDScript/meshを直接load）。既存成果のimport再走は行っていない。全ゲーム/P2回帰も行っていない。

## 修正前の失敗・再取得

- 初期headlessで、存在しないEnvironment enumを参照したparse errorを修正し、その設定行を削除した（環境光は明示色のみ）。続いて `_wall` の三項式から型付きArrayへ代入するruntime errorがあり、明示appendに修正。初期geometry項目のFAILは `logic-initial.log` / `logic-initial-results.json` に保持。修正後の限定headless確認は6 PASS / 0 FAIL（GPU等3 NOT_RUN）、`logic-final.log`、OS終了0。GPUでも同じgeometry項目PASS。
- 最初のsandbox内Hidden GPU起動PID33860はGodotヘッダ後に終了し、Vulkan初期化に到達せず。OS終了コードは取得できていない（NOT_CAPTURED）。同じHidden起動を承認レビュー付きで実行して実GPU描画に成功した。初期フォーカス不変の実測はしていない。
- 最初のGPU画像で屋根上面が過度に暗いことを発見。`self_geometry_probe.gd` で、組込みBoxMesh上面の三角cross/法線内積-1に対し、自作prismが+1で逆向きだった。上下面/側面の三角順序だけ2行修正し、最終probeで双方-1を確認（`geometry-probe.log` / `geometry-probe-final.log`）。形・材質・カメラ・時刻値は変えていない。
- 修正前GPU画像/ログ/結果と旧幾何ソース原文は `initial/` に保持。修正後に影響する時刻画像・影・カメラ連番のみ再取得した。最終画像は本フォルダ直下を使う。

## 起動と証拠

- ユーザーの手動起動: リポジトリ直下 `run_render_study_3d.bat`。1920×1080表示、1朝 / 2昼 / 3夕と画面ボタン。主人公なし。
- 無操作キャプチャ: `run_render_study_3d.bat --capture`。朝昼夕を `evidence/render-study-3d/self/manual-capture/` へ保存後、昼に戻り画面を開いたままにする。通常ゲームの起動入口とは別。
- 最終画像: `morning_960.png` / `noon_960.png` / `evening_960.png` と各 `_1920.png`。
- 実影の参照: `noon_shadow_disabled_reference_960.png`。
- 短い移動: `camera_noon_00_960.png`〜`camera_noon_04_960.png`。
- `source-manifest.json` に対象ソースとPNGのSHA-256。親は `baseline-existing.json` と既存成果を比較する。

GPU再現（ユーザー入力なし、通常は親がGodot資源を割当後に実行）:

```powershell
$env:APPDATA = 'C:/godot/greenvader/evidence/render-study-3d/self/profile'
$studyArgs = @('--path','C:/godot/greenvader','--display-driver','windows','--rendering-method','forward_plus','--rendering-driver','vulkan','--audio-driver','Dummy','--script','res://tests/render_study_3d/self_checks.gd','--log-file','C:/godot/greenvader/evidence/render-study-3d/self/gpu.log')
Start-Process C:/godot/Godot_v4.7.2-stable_win64_console.exe -ArgumentList $studyArgs -WindowStyle Hidden -Wait
```

## 未検証・残課題・文書担当へ

- NOT_RUN: 初期フォーカス不変の実測、nativeウィンドウへの実表示と日本語UI、実キーボード/マウス。OS入力送信・前面化API・カーソル移動・外部自動操作は行っていない。
- 画面全体は3Dの仮材質/少ない形状の試作で、ART-04のドット絵原稿とは印象が異なる。美術採用の判断はユーザーへ返す。静止PNGと5サンプルだけで画風/ちらつき/性能の最終合格にはしない。
- 材質微細ノイズの移動時のちらつき、全位置/他GPU/他解像度、影解像度や法線biasの最適化、複雑な建物/大量の草/性能は未検証。今回は本番用アセットの品質や性能を保証しない。
- 参照したART-04画像は構造の目視参考だけ。生成画像はGPU入力として使用せず、今回のmeshとshaderはリポジトリ内の自作コード。外部素材/ライセンス追加なし。
- 通常ゲーム統合、ゲームの3D化、Unity移行、素材量産、成長処理は実装していない。親による差分/画像確認と独立検証を残す。子の編集は本報告/manifest作成後に停止する。共有STATUS・企画資料は編集していない。
