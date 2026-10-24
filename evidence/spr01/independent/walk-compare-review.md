# SPR-01 通常歩行・跳ね歩きゲーム内比較 独立検証

- 日付: 2026-10-20。共有ツリー/実取得HEAD: `C:/godot/greenvader` / `151a53f20255489ef08481e2a353258cd8ac559c`。既存未コミット差分は保持。
- 凍結対象: 親指定target-hashes.jsonの実装8ファイル・import素材・自己試験、合計18件を実hashで開始前/終了後に照合し全一致。独立素材確認時の通常歩行全対象も終了時hash一致。詳細は `walk-compare-target-before.json` / `walk-compare-target-after.json` / `walk-compare-normal-after.json`。
- 環境: Windows、Godot 4.7.2 stable `ed1daf0bf`、Vulkan 1.4.341 / Forward+ / NVIDIA GeForce RTX 5070 Ti。GPUログに実レンダラーを記録。Pillowはbundled Pythonを使用。
- 仕様根拠: tasks/SPR_01.md冒頭の2026-10-20追加依頼と受入条件、TASK_TEMPLATE.md。実差分・実PNG/グリッド/manifest・描画結果を読み、自己試験のPASSは代用していない。

| 合格条件 | 結果 | 独立証拠/範囲 |
|---|---|---|
| 通常歩行24×36・4方向×4コマ・二値α・既存色/原本保全 | PASS | 先行 `walk-compare-assets.md/json` の5条件PASS、個別150照合PASS。v2/旧hop/16版の記録済み原本hashを保持。 |
| 胴/顔の非跳躍・交互足・葉揺れ・両眼1×2 | PASS | 通常16枚のy15〜31が採用v2と全画素一致、下端y34固定。F1左足/F3右足が接地。目の連続2画素、背面顔なし、二枚葉と脚なし足を一覧で目視。 |
| 起動・内部640固定・nearest整数倍設定 | PASS | 新規town起動、render_view=640×360、通常が初期値。旧index1を表示選択不可。rootの整数倍stretch設定、Sprite3D nearest確認。GPU画像はネイティブ640×360。 |
| 通常/跳ね切替で状態・速度・判定・足元が不変 | PASS | エンジン内F6入力でモード変更、保存対象状態/animation_time/render_foot不変。ボタンで復帰。同一開始点・0.125秒右移動が両モードで同じ変位(4.24292,-4.24292)。差分上も移動/判定コードを共有し、この変更は表示だけ。障害物全配置での衝突総当たりはしていない。 |
| マウス4方向・移動と向きの独立・反転なし | PASS | rootの座標変換を使ったInput.parse_input_eventで上右下左の位置を注入。受信座標と方向が一致。左向きのまま右へ歩くケースもPASS。32姿勢でflip_h=false。実OSカーソルは動かしていない。 |
| 8fps・停止frame0・採用静止画 | PASS | 実移動tick0.125秒でframe1。停止でframe0かつidle.png。pauseも時間/位置を止め静止画へ。GIFは4枚の復号画素と120/130/120/130msを別途確認。 |
| 表示/影のコマ・足元同期、1texel=1内部px | PASS | 通常/跳ね×4方向×4コマの32姿勢でtextureを原寸PNGと実画素比較。影と同texture/中心。投影24×36、固定anchor(12,34)と整数画素接地点を確認。normal_phase2/hop_phase2のGPU画像を目視。 |
| 自己受影除去・地面影・他の3D影の受光 | PASS | 影板visible=true/falseの顔領域RGB差0、全画面差61.886。専用shadow-only箱を建物相当の遮光fixtureとして置くと顔領域明度合計が113.271低下。day_card_on/off・external_mesh_shadow.pngを取得し目視。実マップ全建物の受影確認ではない。 |
| 専用受光light・夜と反射/遮蔽への接続 | PASS | 夜のsun/receiverのtransform・色・energy・visible一致、caster1/cull64と元sunの64除外を確認。水面/遮蔽の反射maskが64を含む。実差分で透過建物の影copyが専用lightからも対象となることを確認。夜/雨のGPU画像は取得・目視、実水面反射そのものの画素比較は未実施。 |
| 旧resolution_index=1セーブの640復元 | PASS | 専用res://証拠領域に正常な時計のtownを保存しmain.load_gameで復元。保存/読込成功、640×360、保存前後のゲーム状態一致。`save_followup.json`。通常セーブは使っていない。 |
| 小範囲回帰・操作表示 | PASS | pauseで状態不変、種/水0で発射不可。ボタンは内部幅640内へ収まり、実GPU controls画像でF6表示を確認。 |
| 物理入力・OS経由の実マウス/キー・物理窓の整数倍画素 | NOT_RUN | エンジン内部注入と設定/ネイティブ描画の確認まで。controls.pngも640×360のroot textureであり、1280×720物理窓のframebufferを撮影したものではない。 |
| 連続歩行/GIF再生の実視認・速度感 | NOT_RUN | 時間を制御したtick、32姿勢のデータ、2姿勢GPU画像と全コマ一覧まで。再生を見たと装わない。 |
| 全照明/夜雨/遮蔽/実水面反射・追加影map性能 | NOT_RUN | 夜雨1画像と専用影fixtureの限定確認。全環境・全建物や新lightによる性能変化は測定していない。 |
| 長時間回帰・全ゲーム・書き出し後動作 | NOT_RUN | 当該変更の主要受入だけ。配布ビルドは実行していない。 |
| 美術・楽しさ・通常/跳ねの最終採用 | NOT_RUN | ユーザーが判断する。 |

最終条件集計: **11 PASS / 0 FAIL / 5 NOT_RUN**。独立GPU主試験は初回19 PASS / 1 FAILだが、下記の試験設定不備であり、その1条件だけを正常fixtureで再取得してPASS。ゲーム実装/素材の修正はない。

## 試験設定不備と限定再確認

初回は夜撮影用にclock.elapsedだけ360へ進め、tick数0のままセーブ試験を続けてしまった。既存のvalidatorは「clock の tick と時間の不整合」で適切に拒否した。このFAILは `walk-compare-gpu/results.json` と初回セーブを保持し、製品不具合や合格への条件緩和として扱っていない。独立試験側に時計復元を追記し、全体を再走せず、`independent_save.gd` で正常な新規townの旧index1保存復元だけ1回再確認した。読込前後の保存対象状態も一致した。

最初の起動準備はuser://logパスとStart-Processの-Wait不足により条件実行前に終了。--log-fileを専用evidence絶対パスへ指定し-Waitで保持して主試験を1回実行した。shader cacheをuser://に作れない環境警告はあるが、Vulkan描画・画面取得・検査は完了した。

## 証拠と終了状態

- 独立試験: `tests/poc/spr01/independent_assets.py`、`independent_compare.gd`、`independent_save.gd`。
- 個別実結果・renderer: `walk-compare-gpu/results.json`、`walk-compare-gpu/save_followup.json`。主試験/狭域再試験のstdout/stderr/engine.logも同じ独立領域へ保存。
- GPU画像: `walk-compare-gpu/{normal_phase2,hop_phase2,day_card_on,day_card_off,external_mesh_shadow,night,controls}.png`。controlsの旧セーブエラー表示は上記の意図せず不正にした初回fixtureに由来し、正常な旧セーブの製品エラーを示さない。
- 素材の全hash: `walk-compare-assets.json`。統合対象18件の凍結hashとGPU証拠hash: `walk-compare-target-before.json` / `walk-compare-target-after.json`。ネイティブ640画像の2×2不一致数は物理窓2倍の検査には使えないため、後者で非受入データと明記。
- 全Godotプロセスが終了していることを確認。ユーザーの通常セーブは不使用。専用保存fixtureは証拠領域内に保持。
- 編集は指定の独立試験・検証証拠のみ。ゲーム/素材/共有進捗修正、OS入力/前面化/カーソル操作、再委任、コミットなし。Godot/import所有権を親へ返す。最終受入判断は親が行う。
