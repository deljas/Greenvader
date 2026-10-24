# SPR-01 ゲーム内歩行比較: 実装者の自己確認

対象: HEAD `151a53f20255489ef08481e2a353258cd8ac559c` と共有作業ツリーの未コミット変更。最終対象ファイルのSHA256は `target-hashes.json`。実装者は共有docs・票・concept原本を変更していない。

## 実装した範囲

- 本体を採用済み24×36の球根へ差し替え。正面/左/右/背面は別絵で、反転なし。足元(12,34)を整数画面座標へ合わせ、カード中心は足元から16px上。nearest・二値alpha・原寸atlas領域、1texel=1内部px。
- `assets/sprites/poc/player/` はconcept成果のPNGをバイト一致でコピーしたimport可能な接続先。圧縮lossless、mipmapなし、3D自動圧縮なし、alpha border加工なし。
- 通常歩行が初期値。右上「歩行」ボタン/F6で既存跳ね歩きへ切替。ゲーム状態、移動速度、当たり判定、アニメ位相、接地点を変更しない。実移動時8fps、停止時は採用済み静止v2のframe0。表示設定はsaveに増やさない。
- マウスの画面位置を保持して顔中心（足元から約10px上）への4方向を選ぶ。左右の移動入力で向きを変更しない。顔の2px範囲では直前の向きを保持。
- 内部640×360固定、nearest整数倍窓表示。F2/960ボタンは整理。旧saveのresolution_index1を受理し、表示は640へ復元する。既存enemy/helperの640用サイズとゲームロジックは維持。
- 交差するdisplay板/影板により顔へ縦境界の自己影が生じたため、親承認の限定修正を追加。display専用layer64と同期するreceiver DirectionalLightを1つ使用し、receiverのcast maskは3D layer1のみ。元太陽の受光対象から64を除外し、既存layer8影板は地面へ投影する。追加lightはLIGHT_ONLYで空へ二重に寄与しない。昼夜/天候で元lightの色・energy・transform・影パラメータ・visibleを同期する。
- 半透明建物のSHADOWS_ONLYコピーは8|1にし、3D受影を維持。shadow_onlyのままなので色の描画は増えない。水反射とocclusionの反射base maskにも64を追加。代償はプレイヤー受影用のDirectionalLight/影マップが1組増えること。全角度性能の測定は未実施。

## 確認と証拠

- Godot 4.7.2 / Vulkan Forward+ / NVIDIA RTX 5070 Ti。root.unfocusable=true、OS入力送信・カーソル操作・前面化なし。Input.parse_input_eventでF6とマウス位置を注入した。
- `self_compare.gd` / `gpu.log` / `results.json`: **16 PASS / 0 FAIL**。通常初期値、640固定、実移動8fps、F6とボタン切替時のゲーム状態不変、マウス4方向、移動方向から独立、停止静止、全32姿勢の表示/影同期と反転なし、24×36投影と整数足元、pause、旧960 save復元、種/水ゼロ拒否。これは自己影修正前の操作系確認で、修正後に同一全項目は再走していない。
- `--layout-only` / `layout.log`: **1 PASS / 0 FAIL**。ラベル設定後の右上ボタン再配置を修正して640内に収まるGPU画像を取得。自己影修正後も `game_controls.png` を再取得。
- `self_shadow.gd` / `shadow.log` / `shadow_results.json`: 最終自己影修正版で **8 PASS / 0 FAIL**。light mask、昼同期、影板ON/完全非表示時の顔差0.0、地面影の差54.93、他3D箱の影による顔差77.11、夜雨22.4時の同期（両light energy0.096）、元light非表示同期、反射mask。顔差はopaqueの顔領域12×9で測定。3D箱はSHADOWS_ONLYの検証fixtureなので、カメラ前の色板による暗化ではない。
- `normal_0..3.png` / `hop_0..3.png`: 修正後の実GPU画面640×360、同位置/同向き/同接地点の連続コマ。`gpu-comparison.gif`: 左通常/右跳ね、ラベル24px分を上に追加、元ゲーム画素は640×360のまま左右連結（ゲームの実移動録画ではなく、同じ場所でアニメ位相だけを進めた比較）。GIF時間は120/130/120/130ms。
- `normal_1_crop6x.png`: 最終GPU画像のnearest6倍crop。`source_normal_down_1_crop6x.png` は参照用原寸素材の6倍表示。制作者目視でbody/葉/2px眼が表示され、自己影の縦境界がなくなったことを確認。
- `self_shadow_fixed.png` / `card_off.png` / `building_shadow_received.png` とcrop: 自己影除外と他3D受影の画像証拠。`night_rain.png`: 夜雨の1条件。

## 試験修正・環境の注意

- 最初の入力注入はcontent座標をそのまま窓イベントへ入れたため、rootの整数scaleで再変換されて方向チェックが失敗した。root.get_final_transform()で窓座標へ変換して修正した。実入力実装の座標変換を条件に合わせて緩和したものではない。
- sandbox実行下のGodotはuser://を解決できず、既存logger/shader cacheの書込み警告、editor import終了時のeditor settings空パス警告を出す。PNG importと実GPU描画は完了。save試験は予約内 `self/save-sandbox/` を独立保存先として実施し、使用したsaveだけを試験終了時に削除した。通常user://保存の物理環境経路は未検証。
- 自己影比較の初回はcast_shadow=OFFにして影板を色板として表示してしまい、顔差が残った。板をvisible=falseで完全に外す正しい対照へ修正して差0.0を確認。診断画像は `diagnose_*` に残る。
- 初回比較試験終了時の既存session参照はObjectDB警告を出したため、試験側はsession.close後に終了するよう修正。最終影対象試験は当該終了警告なし。

未検証: 物理キーボード/マウスからOSを経る経路、ユーザーの美術採用判断、全昼夜/全天候/全角度性能、フルplay-through。通常入口の旧2D `run_game.bat` は未変更。比較対象は `launchers/run_poc.bat` の3D PoC。

コードは凍結し、Godot実行中なし。Godot/import所有権は親経由で独立検証へ移譲。
