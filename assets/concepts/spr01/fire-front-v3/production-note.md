# 正面発射v3：半速・水の溜め・表情

- 対象: 共有HEAD151a53f＋既存差分、2026-10-20。新規fire-front-v3と専用self証拠のみ。v1/v2/runtime/game/docs/ticketは保全。Godot/import・OS入力・前面化・再委任・commitなし。
- 種はsource時間を厳密倍化。[66,100,100,134]ms、400msで復帰・release66ms。v2の胴/手先/非対称葉は顔以外そのまま。F0は内向き閉眼（各3画素のchevron）＋1画素すぼめ口、F1は通常の1×2px眼＋小さな2×2px開口、F2/3は普段の顔。
- 水は7コマ[80,100,100,120,100,120,180]ms、開始[0,80,180,280,400,500,620]・終了800ms。release400ms。v2 mapping[0,1,2,2,3,4,5]。追加F3は大玉を120ms保持し、体を-1px伸びから0pxへ少し戻し、葉/socket/形成玉も+1px追従。
- 水body dy=[0,0,-1,0,+1,+1,0]。足32/33は固定、下胴の接続を保つ。F2/3は閉眼＋すぼめ口、押出しF4は開眼＋開口、F5/6は普段。形成玉は2→4→6→6px（4/12/32/32不透明画素）、400msで形成層から飛翔玉へ分離。
- 目を閉じる指定コマでは1×2px眼を使わず、表情別に正確な目/口座標を検査。開眼・idleでは通常の1×2px眼を維持。旧目/口の下を原画のW/I面へ戻してから再描画し、余計な顔色の残りを許さない。
- キャラは24×36・元8色二値α・anchor(12,34)・輪郭線なし・二枚葉。キャラ11/形成11/飛翔2を別PNG/grid/paletteに分離。種sheet96×36、水sheet168×36。idleは採用版byte一致。
- 既存author/export/build_previewをv3へ再利用し、時間/枚数/表情metadata/検査/出力パスを更新。編集元、原寸PNG、各layer sheet、manifest、全コマ一覧、自立HTML/GIFを保存。UIの追加磨き込みはしていない。
- 飛翔画像はv2とbyte一致、比較用速度0.35px/msも維持。今回の半速はキャラクター動作時間の倍化であり、ゲーム弾速の変更ではない。
- GIFは20ms×200コマ＝4000ms。上段6倍実速、下段2倍で1/4速、水800msの復帰後idleまで収録。種releaseはGIF80msへ近似、水400msは一致。manifest/HTMLは正確な66/400ms。HTMLの物理反映はブラウザー更新周期に依存。
- 自己確認1回PASS: サイズ/二値α/palette/足接地/枠内、表情別座標/開眼1×2/描き残し、source時間倍化、種の顔以外の画素保持、飛翔画像保持、水三段成長＋保持/分離/下胴接続、HTML埋込/時刻境界/JS構文、GIF200コマの復号RGB/時間。全コマ一覧を1回目視。比較飛翔で目は隠れず、口への連続重なりは種14ms/水20msまで。
- 証拠: evidence/spr01/fire-front-v3/self/ のself-check.json、html-check.json、preview-script-check.js、target-hashes.json。NOT_RUN: HTML/GIF連続再生の目視、実速印象/美術採用、物理表示精度、ゲーム統合/弾速/範囲/連射/消費。親の保全baselineは未変更。

| 凍結対象 | SHA256 |
|---|---|
| seed-character-sheet.png | 818ab5505b26355cf97fab3e4ca4ff9cd64d5914b81a169bc613a81a0f98993a |
| water-character-sheet.png | e4c890a9b99d754688f465dd3509723abf3e50fe512e62bd74e0755dd8b97e13 |
| manifest.json | 3325c8c47f24178f88cd7ae7eec0437441060f03a0069aa99cfb5f2d1ee8b232 |
| comparison.gif | fa6665fc5a6a4f8d8e29fba60785dab89227d64d6ab5a5762e8b887bbfcc4905 |
| comparison.html | 20bd16e8f1bdd4d7d35c685cc92d0d35faae77c4a285bacc514342e0baed205d |

独立確認とユーザー評価へ渡し、凍結・停止する。
