# SPR-01 4方向静止 v2（目のみ）

- 対象版: 共有ツリーHEAD `151a53f`。編集はこのv2フォルダのみ。v1・既存16案・正面原本は保持。
- 元: `../four-directions-v1/` のグリッド、palette、exportをコピー。方向の解釈と造形はv1の制作メモを参照。
- 変更: 0始まり(x,y)でLEFTの(4,25)をW→E、RIGHTの(19,25)をI→E。短い目の直下へ各1画素のみ追加。
- LEFTの目はx=4,9、RIGHTはx=14,19。両案とも各目はy=24,25の1×2px。ほかの画素変更なし。
- 出力: down/left/right/up.png（各RGBA24×36・二値α・共通足元12,34）、sheet.png、manifest.json、preview.png（8倍/2倍）。
- 検証: 同梱Python/Pillowでexportを1回実行。v1との画素比較で左右各1画素のみ、正面/背面は0画素差、両目1×2を確認。既存の寸法・α・palette・グリッド・シート・整数倍表示検査もPASS。結果と変更前後SHA256はself-check.json。previewを1回目視確認。
- PNG SHA256: LEFT変更前 `c7ef8dd3fe6ae79166293e45d302da6929f98ddabdd33b04f57b80feac8b5cc0` → 変更後 `7b1e76b5b0b9367b83a08a6a16fd2d65e76d6636e1591412812995423328fb18`。
- PNG SHA256: RIGHT変更前 `481f0f0fa446553fcd3b74953ee0b3e739e5560e2f3b3e424a152b24339c16f8` → 変更後 `f0585d0e1455e75939e53488fb321df8640696b393818ba98e75b14a86025037`。
- DOWN不変 `d12e39f3ba986f36d0b2a7a0a762518794eaa370d72de17096c804041c8d8d18`、UP不変 `c7d9878df3626d281b469824fdcbc5b6c6c09f1a5d631226a15fbfe27833b750`。
- NOT_RUN: ゲーム内表示・照明・移動・アニメーション。Godot/import、OS入力/前面化/カーソル移動、再委任、コミットなし。静止4方向のみで停止。
