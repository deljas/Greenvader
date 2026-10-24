# SPR-01 正面発射試作v1 独立検証

- 2026-10-20、共有HEAD `151a53f20255489ef08481e2a353258cd8ac559c`。tasks/SPR_01.md冒頭の仕様を期待値とし、実PNG/grid/manifest/HTML/制作スクリプトを確認。独立 `verify.py` をbundled Python/Pillowで1回実行、**241個別PASS / 0 FAIL**。全コマcontact-sheetを1回目視。
- 対象は正面だけの新規試作。自己検査のPASSは代用せず、実画素・データと復号GIFを照合した。

| 条件 | 結果 | 実確認 |
|---|---|---|
| 原寸・画素・顔・足元・体 | PASS | キャラ9枚は24×36 RGBA・既存8色内・二値α、grid/PNG/シート/hash一致。両眼は採用正面の1×2画素を維持。体/顔は水releaseコマだけ1px沈み、ほかは固定。足のy32/33は採用静止と全画素一致、下端y34・anchor(12,34)。idleは採用正面とbyte一致。 |
| 種/水の時間と発射イベント | PASS | 種4枚33/50/50/67ms、計200ms・release33ms。水5枚17/33/50/67/83ms、計250ms・release50ms。manifestと埋込HTMLデータの開始/終了境界も一致。idleは専用コマ数に含まない。 |
| キャラ/形成FX/飛翔弾の分離 | PASS | キャラ色とFX色のpalette/grid/PNGが独立。形成9枚は24×36、弾2枚は8×8の別PNG。キャラへ水色/弾色の焼込みなし。水形成は小から大へ増え、50ms以降の形成層は透明となり弾層へ分離。 |
| 葉の非対称と種/水の違い | PASS | 全コマ一覧で二枚葉、暗い全周線のない硬い色面と脚なし足を維持。種は寄せて弾き大葉が後から反動、水は開いて玉を膨らませ押出し、その後大葉が下がる差が読める。水後半では小葉が先に同じ戻り形となり大葉が変化を続ける。これは静止コマの読取で、実速の印象評価ではない。 |
| HTMLの正確な時刻区分・静的構造 | PASS | comparison.htmlの埋込データが原稿データ/manifestと一致。start<=t<endで位相を選びrelease時刻で弾を描く。整数矩形・補間OFF・pixelated指定。ブラウザー更新周期が物理表示を制限する旨も記載。コードの静的確認まで。 |
| GIF復号・時間・近似の明記 | PASS | 60コマを復号、各20ms・計1200ms・無限loop。原寸PNGを独立に合成した期待パネルと、実速6倍/1/4速2倍の全復号パネルが一致。GIF形式の10ms単位を踏まえた20msサンプルで、releaseは種40ms/水60msへ近似と記録され、manifest/HTMLの33ms/50msは変更していない。 |
| 元137件の保全・最終対象の固定 | PASS | preserved-before.jsonの137件を実hash比較し全一致。制作者の最終target-hashes全件も実hash一致。成果全体のSHA256はresults.jsonへ保存。ゲーム/runtime/既存素材を変更していない。 |
| HTML/GIF連続再生・ブラウザー実行 | NOT_RUN | 静的コード/データ、GIF復号時間/画素、全コマ一覧まで。ブラウザーで再生や操作を確認したことにはしない。 |
| 実速の人の印象・操作感・最終美術採用 | NOT_RUN | ユーザーが判断する。特に数十msの鋭さ/柔らかさは静止コマだけで最終評価しない。 |
| ゲーム統合・実照明・弾道/入力/連射 | NOT_RUN | Godot/importを実行せず、ゲーム未統合。比較用の下向き弾道はゲーム仕様として承認したことにならない。 |

**7 PASS / 0 FAIL / 3 NOT_RUN**。正面発射のコマ・時間・レイヤーを比較提示する限定範囲で問題は見つからなかった。ゲーム/アート全体の受入ではない。

証拠: `results.json` に個別結果・全成果SHA256・最終凍結一致、`verify.py` に独立確認手順。目視元は `assets/concepts/spr01/fire-front-v1/contact-sheet.png`。主要hash: manifest `890d8db6876d9401729df05295400ccb0af6c5739dfb2760342b01771a013b9b`、HTML `87d6777fbd902d71f4c9e9aa793c2f4a155aab2b0a6299c043d8f3bd10acd8d9`、GIF `1f4e92824b934b4f90e1ad8273010299639e1846b89078760bc5d77407b94c16`。

編集は本independentフォルダのみ。ゲーム/assets/docs/ticket修正、Godot/import、OS入力/前面化/カーソル操作、再委任、commitなし。最終受入を親へ返して終了する。
