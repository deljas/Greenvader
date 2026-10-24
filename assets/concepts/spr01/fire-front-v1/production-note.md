# SPR-01 正面発射 v1

- 対象: 共有ツリーHEAD151a53f＋既存差分、2026-10-20。編集は本フォルダと `evidence/spr01/fire-front-v1/self/` のみ。ゲーム/runtime・共有資料・他方向・旧素材は変更なし。Godot/import・OS入力・前面化・再委任・commitなし。
- 原画: `four-directions-v2/grid-down.txt` と8色palette。idle.pngは採用down.pngとbyte一致、SHA256 `d12e39f3ba986f36d0b2a7a0a762518794eaa370d72de17096c804041c8d8d18`。
- 種専用4コマ: [33,50,50,67]ms、開始[0,33,83,133]、200msでidle。release33ms。寄せ→小葉が先に弾き→大葉が遅れて大きく反動→復帰。
- 水専用5コマ: [17,33,50,67,83]ms、開始[0,17,50,100,167]、250msでidle。release50ms。開く/小玉→離散的に大玉→押出し/体1px沈み→大葉が柔らかく下がる→復帰。小葉は先に戻る。
- 主人公は全9コマ24×36、anchor(12,34)、8色二値α・硬い面・輪郭線なし。両眼各1×2pxと普段の口を維持し、大小非対称の二枚葉。足は全コマ接地、胴offsetは種[0,0,0,0]・水[0,0,1,0,0]。idleを専用コマ数へ含めない。
- 分離: character9枚/formation9枚は各24×36、projectile2枚は各8×8・anchor(4,4)。文字グリッドとpaletteを分け、キャラPNGへ水色や弾を焼き込まない。形成FX/弾は落ち着いた青3色/種色3色を使用、こちらも二値α。種/水それぞれcharacter-sheetとformation-sheetを保存。
- socketは葉の間、通常(12,13)・水押出し時(12,14)。形成水玉は2×2→4×4、50msで形成層を空にして5×5の飛翔玉へ分離。比較だけの画面下向き0.35px/msを整数位置へ丸め、150msまで表示。ゲーム弾道・入力/連射・弾速の採用仕様ではない。
- 編集は `author_grids.py` →保存グリッド。書出/基本検査は `export.py`、HTML埋込みは `build_preview.py`。各原寸PNGとシート、時間/イベント/レイヤーのmanifest、全コマcontact-sheet.pngを保存。
- `comparison.gif`: t0同期・1200msループ、上段6倍実速/下段2倍で1/4速。GIFの10ms単位を踏まえ20ms以上の60サンプルで作成。種33msの発射はGIF上40ms、水50msは60msへ近似。元manifestの時間は変更なし。固定palette直接描画、dither/量子化なし。
- `comparison.html`: 全グリッド/色/正確時刻を埋込んだ自立canvas。実速/1/4速、再生停止、時刻スライダー、次の境界コマ、FX切替。整数矩形描画。時刻区分は正確なmsだが、物理画面への反映はブラウザー更新周期に依存する。
- 自己検査PASS（ほどほど1回）: 数/サイズ/RGBA/二値α/各palette/目/口/足/枠内、idle元hash、時間境界と33/50msイベント、分離、水玉の増大と分離、GIF60コマの復号RGB/時間。HTML埋込データ一致とJS構文を確認。全コマ一覧を1回目視。比較弾道では目を隠さず、口への連続重なりは種11ms・水14ms以下。結果は証拠self-check.json/html-check.json。
- NOT_RUN: HTML/GIF連続再生の目視、ブラウザー物理表示精度、ゲーム統合・実照明・操作感・最終美術採用。親の保全baselineは変更していない。

| 凍結対象 | SHA256 |
|---|---|
| seed-character-sheet.png | 89ce82cfa5fba9d44d91c05bfe175b4ec0fa8c21d78c2b1b86126dff59a7c552 |
| water-character-sheet.png | f088277cea2d608b1f9967d8bc171210b18715062fe2d7375493d925ec87f399 |
| manifest.json | 890d8db6876d9401729df05295400ccb0af6c5739dfb2760342b01771a013b9b |
| comparison.gif | 1f4e92824b934b4f90e1ad8273010299639e1846b89078760bc5d77407b94c16 |
| comparison.html | 87d6777fbd902d71f4c9e9aa793c2f4a155aab2b0a6299c043d8f3bd10acd8d9 |

全成果hashは証拠target-hashes.jsonへ。独立確認・ユーザーの動き評価へ渡し、ここで停止。
