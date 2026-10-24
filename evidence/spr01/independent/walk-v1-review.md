# SPR-01 walk-v1 独立検証（静止全コマ・GIF復号）

- 日付: 2026-10-20。実取得HEAD: `151a53f20255489ef08481e2a353258cd8ac559c`。共有ツリー `C:/godot/greenvader`、対象フォルダは未追跡。既存差分を保持。
- 対象: `assets/concepts/spr01/walk-v1/`。仕様根拠はtasks/SPR_01.mdの現在の歩行試作受入条件と親依頼。4コマ/8fps/振幅は親の試作初期値であり、ユーザーの確定採用ではない。
- 環境/方法: Windows PowerShell・bundled Python/Pillow。実PNG16枚・グリッド・sheet・manifest・GIFを独立プログラムで1回検査（exit 0）。author_grids.py/export.py・制作記録を読み、制作スクリプトは実行していない。制作self-checkのPASSは独立結果の代用にしていない。原寸PNGとの対応を照合済みの全16コマcontact-sheetをview_imageで1回目視。

| 条件 | 結果 | 独立実結果 |
|---|---|---|
| 16枚の寸法・RGBA・α・パレット・枠切れ | PASS | 全24×36 RGBA、α集合{0,255}。前/左右は不透明8色、背面は6色、既存palette内。全非透明bboxに四辺の余白がある。 |
| F0と採用v2・16版の保持 | PASS | 各方向F0は対応するv2 PNGとbyte一致。v2の4hashも既存の採用値と一致。16版hashは `f188d843f64c3d2c54f1442deff625ddee920d6af14b59c64a8ec422976efffc` のまま。 |
| 編集グリッド・左右非反転 | PASS | 16txtは各36行×24文字、実PNG全画素と一致。各位相でleftの左右対応画素とrightは不一致。author_grids.pyは方向別のv2グリッドから展開し、反転生成は使っていない。 |
| 両目1×2・背面顔なし | PASS | 前/左右の全12コマで目色は二列、各列が連続2画素。背面4コマは目/口の色なし。 |
| sheet・manifest・固定接地原点 | PASS | sheetは96×144 RGBA。行DOWN/LEFT/RIGHT/UP、列F0〜F3、全矩形がPNGと一致。manifestのfile/rect/hash/bbox/anchor(12,34)が一致。8fps・loop=true・周期500ms。全方向の可視下端はy34/34/32/33で、浮き2px/1pxのコマを接地原点へ戻していない。 |
| 4倍contact-sheet | PASS | 516×680。全16コマの各4×4セルが元PNG色または背景RGBと完全一致、不一致0。 |
| GIF復号・倍率・色・タイミング | PASS | GIFは656×400、4コマ・無限loop。復号時間120/130/120/130ms、合計500ms・平均8fps。4方向×4コマの6倍/2倍全セルが元PNGと一致、不一致0。全復号色は素材色＋背景/地面印色のみで、ditherや新しい補間色なし。各間隔が厳密125msという意味ではない。 |
| 跳ね段階・葉の曲げ/遅れ・脚なし足・二枚葉 | PASS | 全方向で白い本体上端がy15→16→13→14となり、沈み/浮き/降下の段階が読める。接地/準備は足が地面を保つ。F2の葉先は体ほど上がらず、F3で戻る形に変わり、体ごとの剛体移動だけには見えない。大小二枚葉を維持し、第三葉は見られない。足は本体底に直接付き、細い脚はない。左右の浮きコマでは足先が1画素行の小さな形になり、細部の読みやすさには限界がある。 |
| GIF連続再生の目視 | NOT_RUN | 復号した時間と画像の検査、および全コマ一覧の目視まで。実際の連続再生を見て滑らかさ/速度感を確認したことにはしない。 |
| 実ゲームの向き/横移動/後退・移動同期・照明/影 | NOT_RUN | Godot/import・組込み・ゲーム実行なし。雨夜/遮蔽や入力も未検証。 |
| 動きの最終美術採用・楽しさ | NOT_RUN | ユーザーが判断する。 |

計: **8 PASS / 0 FAIL / 3 NOT_RUN**。静止全コマとGIFファイルの技術確認として提示可能。連続再生の動きやゲーム内動作を確認済みとは扱わない。限定範囲で重大な不一致は見つからなかった。

## 実取得SHA256（対象固定）

| ファイル | SHA256 |
|---|---|
| down-0.png | `d12e39f3ba986f36d0b2a7a0a762518794eaa370d72de17096c804041c8d8d18` |
| down-1.png | `62782b714ff6ff105bf84503edb188bef87e472ead47aba8ea99f3a6ca63f146` |
| down-2.png | `cb1d6be7c4db8e456fd90ec8ba6a8d420a904779a7b96f692c6d554a165ed9e9` |
| down-3.png | `3af6423647ce4c8f85dff34f584656de57eb0eae98cafc565e9842499750833c` |
| left-0.png | `7b1e76b5b0b9367b83a08a6a16fd2d65e76d6636e1591412812995423328fb18` |
| left-1.png | `06015cf2a26236f835d0e06de04334247a2135524e9ff463a195750a3992350e` |
| left-2.png | `f13c66639a0bee463aae5a5ac6418d021a0aeeff539839ed5acd409ba5c49a87` |
| left-3.png | `39c95f09169880f6efd962ddd37cc8e88ccdfd2bafe1939e1c67f53c73a15f54` |
| right-0.png | `f0585d0e1455e75939e53488fb321df8640696b393818ba98e75b14a86025037` |
| right-1.png | `b710e324c9d1667ba857ab6816f85260a5a94fd101b60dc60b2e649485aea120` |
| right-2.png | `c992efeaf31121cc3ca14e30fdc91e47d2d1c215559daf0808e446455234029a` |
| right-3.png | `3fad36e58a7808d0e836faf24ab8b6a3578a2ce3ae5dbf31f4a64010d9f94f46` |
| up-0.png | `c7d9878df3626d281b469824fdcbc5b6c6c09f1a5d631226a15fbfe27833b750` |
| up-1.png | `85c0b9ef5e8dc5d358837015195c4cee7232bedb74a39470fa4d17dffcba5668` |
| up-2.png | `db6cf31730fc918e27c7ddb0cfedd70143e2cf2a751e3db8844d5b9538918130` |
| up-3.png | `06f18ff7731c9ee91cbb5139b9d75f6dacc7ea7701f0f7488dbb38ecb336f369` |
| sheet.png | `77357397cf258da39457ad66ec451522c75f3553f66f156852dd4669c3bb635c` |
| contact-sheet.png | `b7f154222f84530e07c49eccce62bbe60970ab214ace4f7ef1916f2cb8b4241b` |
| preview.gif | `6347ac500e40d498c9a95d625184b3febf5dc58c7a806299d3cc0023d37d003c` |
| manifest.json | `0b64b712e233303f75afa3834f29516a24200da8e01e68bf36bd47d13dd0cff3` |
| author_grids.py | `6c112c2ff6a5779cc0db8327be6f12481ab53592eb4e658fcd706ee95b949393` |
| export.py | `b62a128a9e4562ca9dcf778fd1c94ad3fbb90c877b0956500b14b8d49465b25e` |
| self-check.json | `c36f070937e5472b6134e0ef0526d5ef3e7c300734517fbe2e7dcaa3cc3ea913` |

編集は本報告のみ。素材/ゲーム・共有進捗文書を変更していない。Godot/import、OS入力/前面化/カーソル・外部操作、再委任、コミットなし。最終受入は親へ返す。
