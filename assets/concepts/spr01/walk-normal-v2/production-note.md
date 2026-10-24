# 通常歩行v2：小さな沈みと皮の手振り

- 対象: 共有ツリーHEAD `151a53f20255489ef08481e2a353258cd8ac559c`＋既存差分、2026-10-20。
- 素材: 本フォルダの24×36・4方向×4コマ、既存8色/α0・255、sheet96×144（行down,left,right,up）、8fps・loop、anchor(12,34)。F0は採用静止v2とPNG byte一致。各方向独立、左右反転なし。
- 周期: 胴/顔のy offsetは[0,+1,0,+1]。F1/F3で1px沈み、下腹の最下部は接地足に合わせて清書。F2は中立。足2行は通常歩行v1の交互形を保持し、全コマy33に片足以上が接地する。両足が浮くコマ・脚/足首なし。
- 手: 小さな皮片を本体から分けて描き、F1で画面左-1/右+1px、F3で左+1/右-1px（胴に対する値）。下がる手は必要に応じて内へ1px収め、付け根が離れないよう清書。胴の沈みを含めた手の移動は0/2pxとなる。顔は両目1×2pxと小口、背面顔なし。
- 葉: 通常歩行v1で保持した相対的な遅れ/曲げ戻りを使い、胴の沈みぶんだけ根元も+1pxして短い白い頂部へ接続。二枚葉の位置・大小・方向は維持。
- 編集元は16グリッドとpalette、`author_grids.py`。書出/自己検査は`export.py`。PNG16枚、sheet、manifest、GIF、全コマ一覧を保存。`preview.gif` は6倍/2倍・120/130/120/130ms＝平均8fps、ゲーム用8fpsは等間隔。既存の「胴固定」検査を削除し、新周期・目/口座標・相対手変化・足接地の検査へ更新した。

## 自己確認とゲーム差替

- 素材検査PASS: 全16枚RGBA24×36・二値α・既存色内・切れなし・グリッド読戻し・シート整合・F0静止一致。上半身と目/口の0/1/0/1px周期、全可視目1×2px、背面顔なし、全コマの接地、手の指定相対座標を検査。全コマ一覧を1回目視。GIFは全4コマの復号RGBと時間を確認（連続再生の見た目は未確認）。
- runtime `assets/sprites/poc/player/walk-normal.png` は本sheetのbyteコピー。`manifest.json` のnormal出典だけをv2へ更新。idle/hop、通常v1、16案、既存import設定のSHA256不変を確認。`verify_runtime.py` と `evidence/spr01/walk-normal-v2/self/runtime-check.json` に根拠を保存。
- Godot 4.7.2のheadless importで通常PNG1枚を再import。初回Hiddenのbackground起動はシェル終了時に終了して実行証拠が出なかったため、headless importを同一shell内で完了まで実行。editor/user://設定保存の権限警告あり。再import自体は完了。
- 専用 `tests/poc/spr01/self_normal_v2.gd` をroot.unfocusable=true、Hidden、証拠フォルダの絶対logで起動。Vulkan Forward+ / NVIDIA GeForce RTX 5070 Ti、WindowsのGPU描画。
- GPU自己試験 **7 PASS / 0 FAIL**: 640通常モード、importされた全runtime画素とv2一致、通常4コマの同じ接地点、停止idle、エンジン内F6でhopへ切替、hop atlas、通常への復帰とidle。ゲーム内Input.parse_input_eventのみ。保存/全天候/影の全再試験なし。
- 証拠: `evidence/spr01/walk-normal-v2/self/` のnormal_0〜3.png、idle.png、hop.png、gpu-frames.png、results.json、gpu.log、import.log、runtime-check.json、target-hashes.json。GPU全画面1枚と4コマcrop一覧を目視した。crop一覧は同じ場所で位相だけ変えた撮影であり、実移動の録画ではない。
- 環境警告: user://のshader cache作成権限なし、キャッシュなしで描画した。試験の失敗はなし。エンジンimportにより専用試験のself_normal_v2.gd.uidが自動生成された。
- NOT_RUN: 物理OS入力・物理窓の画素、連続再生の操作感/最終美術評価、保存/全天候/全影/性能/配布。ゲームコードは変更なし、共有docs/ticketは更新なし。Godotは終了済み、OS入力・前面化・カーソル操作・再委任・コミットなし。

## 凍結SHA256

| 出力 | SHA256 |
|---|---|
| sheet.png / runtime walk-normal.png | 9505f78fa58e6e2afa957f25d51e79134bb60c4bdbb0fb486ec005481da38bfc |
| preview.gif | 99c50c7ad11623260797a4add446c9ef797885200252c9577eeb28c16392599d |
| contact-sheet.png | 1fca0afbe5314c7fa4740b1b817849828d697331a21141ad228d1b6bb53f7a46 |
| manifest.json（本フォルダ） | aebe4fd1cd48f98f3419464b448b357b79c04c325adec28255d2acd864e46eb6 |

各原寸PNGと固定対象はmanifest/self-checkと証拠target-hashesに記録。独立確認とユーザーのゲーム内採否へ渡し、今回の制作・差替を停止する。
