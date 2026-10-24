# SPR-01 正面発射v2 独立検証

- 2026-10-20、共有HEAD `151a53f20255489ef08481e2a353258cd8ac559c`。tasks/SPR_01.md最新節と親指定条件を期待値として確認。
- 前回の独立手順を流用・更新し、v2差分を追加した `verify.py` をbundled Python/Pillowで1回実行。**275個別PASS / 0 FAIL**。実PNG/grid/manifest/HTML、制作スクリプトを読み、自己検査結果は代用していない。contact-sheetをview_imageで1回目視。

| 条件 | 結果 | 実確認 |
|---|---|---|
| 原寸/色/α・目・レイヤー | PASS | キャラ10枚は24×36 RGBA・既存8色内・二値α、grid/PNG/sheet/manifestが実画素/hashで一致。両眼1×2と口は指定dyで維持。形成FX10枚・飛翔弾2枚は別palette/PNG/grid。idleは採用正面とbyte一致。 |
| 種のタイミング・体/手先・葉/socket追従 | PASS | 4枚33/50/50/67ms・release33msを維持。F1の胴/顔/手はv1から1px下、最外手先x1/x22は元y27→y29で計2px下、y28は透明。葉の色付き画素集合は体相対でv1と完全一致、socketも(12,14)へ追従。他3コマのキャラはv1と一致。 |
| 水の三段膨張・時刻と分離 | PASS | 6枚40/60/50/60/80/110ms、計400ms・release150ms。形成bboxは2×2→4×4→6×6、非透明数4→12→32、150ms以降の形成層は空。飛翔弾は別画像へ分離。 |
| 水の伸び/沈み・接地/接続 | PASS | 胴/顔は0/0/-1/+1/+1/0px。足y32/33は元静止と全画素一致。伸びコマのy31は元の下胴を保持し、全10キャラが8近傍で一つにつながる。身体を浮かせるジャンプや孤立した足/手/葉はない。anchor(12,34)を維持。 |
| GIFとHTMLの時間・画素整合 | PASS | GIF100コマ×20ms＝2000ms・無限loop。原寸PNGから独立に合成した実速6倍/下段2倍4倍slowの全パネルが復号画像と一致。下段で400ms境界とその後idleまで入る。GIFreleaseは40/160msの近似、manifest/HTMLは33/150ms。HTML埋込データ・start<=t<end・発射条件・補間OFF・cycle2000msを静的確認。 |
| 全コマの外観 | PASS | 種の寄せ/弾き/反動、水の膨張保持/押出し/大葉の戻りを一覧で比較できる。非対称の二枚葉、脚なしの短い足、硬い色面を維持し、目立つ破綻・第三葉・暗い全周線は見られない。実速の印象評価は含めない。 |
| 旧138件保全・凍結対象固定 | PASS | preserved-before.jsonの138件を実hash照合し全一致。最終target-hashes全件も一致。ゲーム/旧v1/採用素材を変更していない。全成果SHA256はresults.jsonに保存。 |
| ブラウザー実行・HTML/GIF連続再生 | NOT_RUN | 静的HTML/データ・GIF復号とコマ目視まで。物理更新周期や再生UI操作は実行していない。 |
| 実速の印象・操作感・美術採用 | NOT_RUN | ユーザーが判断する。水の数値や形状は親の比較用初期値。 |
| ゲーム統合/水範囲/消費/連射/弾道/物理入力 | NOT_RUN | Godot/importやOS入力を行っていない。比較用飛翔はゲーム挙動として受け入れていない。 |

**7 PASS / 0 FAIL / 3 NOT_RUN**。正面v2の比較試作として問題は見つからなかった。ゲーム統合や最終美術の合格ではない。

証拠は本フォルダの `results.json`（275個別結果、全成果SHA256、最終凍結一致）と `verify.py`。目視元は `assets/concepts/spr01/fire-front-v2/contact-sheet.png`。

主要SHA256: manifest `66659a8d8834b41fd7d58d056e6a651121a87c3c2197dc0d7dfea34633d1058a`、HTML `7d4785fc5a31390c9a767cf3ec2a77f98d687a9a0bb0580d2412a910644722d8`、GIF `ccac6deb8e120bdd86658ec59969af9b849173a5733f66bb6bb9b932d607ad3b`。

編集は指定independentフォルダのみ。assets/ゲーム/docs/票の変更、再委任、commit、Godot/import、OS入力/前面化/カーソル操作なし。最終受入を親へ返して終了。
