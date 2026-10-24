# SPR-01 4方向静止案 v1 独立検証

- 日付: 2026-10-19（依頼の日付）。対象HEAD実取得: `151a53f20255489ef08481e2a353258cd8ac559c`。共有ツリー `C:/godot/greenvader`、対象は未追跡、既存差分を保持。
- 根拠: tasks/SPR_01.mdの今回受入条件、既読TASK_TEMPLATE.md、親依頼。主役24×36、内部640×360、4方向静止のみ。旧16版と正面採用版の保持を含む。
- 方法/環境: Windows PowerShell・bundled Python/Pillow。実PNG・方向別文字グリッド・palette・manifest・export.py・self-check・制作記録を読み、独立読取プログラムを1回実行（exit 0）。self-checkのPASSは根拠の代用にしていない。各方向PNGと一致検査済みのpreviewをview_imageで1回目視。制作スクリプトは実行していない。

| 条件 | 結果 | 独立実結果 |
|---|---|---|
| 寸法・RGBA・二値α・有限パレット | PASS | 4枚とも24×36 RGBA、α集合{0,255}。正面/左右は不透明8色、背面は顔色を使わず6色。全画素が既存paletteに属する。 |
| 正面・既存16版を保持 | PASS | down.pngはfront-pixel-v1/front-24x36.pngとbyte一致、SHA256も採用版と一致。front-16x24.pngのhashも既存凍結値と一致。 |
| 独立グリッド・単純左右反転なし | PASS | 4txtは各36行×24文字、実PNG全画素と一致。leftを左右対応座標で比較してもrightと一致しない。export.pyは方向別グリッドから直接作画し、反転座標は等値検出だけに使用。 |
| 共通足元・sheet/manifest一致 | PASS | sheetは96×36 RGBA、4個のrectが個別PNGとbyte一致。manifestの順DOWN/LEFT/RIGHT/UP、rect、ファイル、各1frame/loop=false、anchor(12,34)が一致。全方向の非透明下端は境界y34、最下画素y33、画像端の切れなし。 |
| previewのnearest相当8倍/2倍 | PASS | 864×480のpreview。4方向×2倍率の全セルを原寸PNGと比較し、矩形内全画素が対応RGBまたは背景RGBに一致。不一致セル0。 |
| 左右の前寄り斜め向き・背面 | PASS | 左右は両目を残しつつ進行側へ寄せ、近遠の目の大きさ、手足の重なり、横腹/底面の輪郭も異なる。正面の顔をずらしただけには見えず、前面も見える左右向きとして読める。背面には目/口がない。 |
| 大小二枚葉・個体としての整合 | PASS | 正面の大葉=画面左、背面=画面右。LEFTは大葉が上右へ細長く、RIGHTは上左へ広く見える。各方向とも二枚で、独立した第三葉は見られない。「本人右の大葉が少し後方へ傾く」という仮の立体解釈なら矛盾なく読め、重大な葉の取り違えは認めなかった。奥行きの一意な証明は含まない。 |
| 白クリーム球根・皮の手・脚なし足・輪郭線なし | PASS | 手は小さな皮片、足は底面へ直接つながり細い脚/足首区間を作らない。色面で形を表し、暗い全周線はない。プレビューの灰枠は素材外。 |
| 正確な3D葉形状・角度・回転中の連続性 | NOT_RUN | 2D静止案だけでは一意に確定できない。制作記録の葉の後方傾斜は仮解釈で、ユーザーの追加承認として扱わない。左右の近遠表現は2倍では小さい。 |
| ゲーム表示・照明/影/雨夜遮蔽・移動/歩行/葉揺れ | NOT_RUN | Godot/importや組込み・実行をしていない。静止4枚の確認だけ。 |
| 最終美術採用 | NOT_RUN | ユーザーが判断する。 |

計: **8 PASS / 0 FAIL / 3 NOT_RUN**。4方向の静止試作として提示可能。重大な造形不一致は見つからなかった。葉の奥行き解釈と小さい近遠表現の限界を添え、ゲーム内での回転や動作の受入には使わない。

## 実取得 SHA256

対象フォルダ: `assets/concepts/spr01/four-directions-v1/`。

| ファイル | SHA256 |
|---|---|
| down.png | `d12e39f3ba986f36d0b2a7a0a762518794eaa370d72de17096c804041c8d8d18` |
| left.png | `c7ef8dd3fe6ae79166293e45d302da6929f98ddabdd33b04f57b80feac8b5cc0` |
| right.png | `481f0f0fa446553fcd3b74953ee0b3e739e5560e2f3b3e424a152b24339c16f8` |
| up.png | `c7d9878df3626d281b469824fdcbc5b6c6c09f1a5d631226a15fbfe27833b750` |
| sheet.png | `bba6721f391dc8a3155c191f0b497c818a158598e1dcdc4edb3552563cfb4a06` |
| preview.png | `e68d0cb96ed10fea292b9141564354072b42f8a20610780bdc7c3c0f859b5562` |
| manifest.json | `1d2faab9ae07a005012dff64dbe435d7844667620cabdca214e59ca12079f854` |
| grid-down.txt | `77b1bd90e06792705a3220e32bf52214c6ce8f8a791c93e748d0b3c8cf109f7d` |
| grid-left.txt | `d24f8289c04fe86621e68431a13c19c24412bcf4f4d76a34852b27fe0ce2fce4` |
| grid-right.txt | `b754f9dd6b8dc0b862e797ecba5aedc1d20f61d887062bec977b0358b83a73a0` |
| grid-up.txt | `6e26124b7e097dbac87326fa99306c8d138cbe2cef24ae47571976cbf0754b48` |
| palette.json | `4db114ef49f7bffe260bb463708e6dea67ace10bf2de92f98da40c5becce4e70` |
| export.py | `7d42a940c2d4ebb70c5c14624988178a709342e14b9ebdd9551ee0809e293b1f` |
| self-check.json | `c38ce6380127f8453397187ef8a702fabf01cd7fd3ca7c66bb2bc6417b9cd901` |
| front-pixel-v1/front-16x24.png（保持対象） | `f188d843f64c3d2c54f1442deff625ddee920d6af14b59c64a8ec422976efffc` |

変更は本報告のみ。素材・ゲーム・共有進捗を編集していない。Godot/import、OS入力/前面化/カーソル・外部操作、再委任、コミットなし。最終受入は親へ返す。
