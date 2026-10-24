# SPR-01 4方向v2 目だけの独立確認

- 依頼日: 2026-10-19。対象HEAD実取得: `151a53f20255489ef08481e2a353258cd8ac559c`、共有 `C:/godot/greenvader`、既存差分保持。
- 方法: bundled Python/Pillowでv1/v2の実画素を1回比較（exit 0）、シートと8倍/2倍previewを全セル照合。previewを1回目視。制作self-checkは使用していない。今回の変更は本報告のみ。

| 条件 | 結果 | 実結果 |
|---|---|---|
| 指定した目の2画素だけを変更 | PASS | v1との差はleft(4,25)、right(19,25)のみ。どちらもE色(73,55,44,255)へ変更。両目が各1×2となり、目視でも確認。 |
| 正面/背面・その他画素を保持 | PASS | down/upの画素差0。左右も上記以外の差0。 |
| 24×36 RGBA・二値α | PASS | 4枚とも指定寸法/形式、α集合{0,255}。 |
| sheet・previewの対応 | PASS | 96×36シートの各矩形と各PNGが一致。864×480previewの8倍/2倍矩形セルが元画素と完全一致、不一致0。 |
| 元16版・v1画像/編集元保持 | PASS | 16版、v1の4方向PNG・sheet・preview・4グリッド・palette・export.py・manifest・self-checkは前回実取得hashと一致。v2 manifestもv1と同hash。制作記録noteについては下記留意。 |
| 実行時表示・照明/影・動作 | NOT_RUN | 今回は静止素材の目変更だけ。Godot/import・ゲーム実行なし。 |
| 最終美術採用 | NOT_RUN | ユーザーが判断する。 |

計: **5 PASS / 0 FAIL / 2 NOT_RUN**（目変更と静止成果物の範囲）。他の造形について回帰の再評価は行っていない。

留意: v1の`production-note.md`は前回の途中読取時hash `fff1b00ded213bd4acb1770399948322e3f777d0bb97fed84476973ea21d165e` から、今回 `d3007eee42d5ba0496e7e601d2ac9eaec4e1103c49bac4e717ecf86d2e6f2d54` に変わっている。画像/グリッド等には変化なし。今回の依頼は目変更のみのため記録文章の変更経緯は調査していない。「v1全ファイルが前回読取時点から不変」とは判定していない。

## 実取得SHA256

v2は `assets/concepts/spr01/four-directions-v2/`。

| 対象 | SHA256 |
|---|---|
| down.png | `d12e39f3ba986f36d0b2a7a0a762518794eaa370d72de17096c804041c8d8d18` |
| left.png | `7b1e76b5b0b9367b83a08a6a16fd2d65e76d6636e1591412812995423328fb18` |
| right.png | `f0585d0e1455e75939e53488fb321df8640696b393818ba98e75b14a86025037` |
| up.png | `c7d9878df3626d281b469824fdcbc5b6c6c09f1a5d631226a15fbfe27833b750` |
| sheet.png | `754a97bd44912a87bf2197ce74dfdca8cdf4b01a835f88c7b1ba99b1d8e029fe` |
| preview.png | `7be3121ef0b43beadbafe12a1b6b448d53d6c75e2a397862518a85a891e35687` |
| manifest.json | `1d2faab9ae07a005012dff64dbe435d7844667620cabdca214e59ca12079f854` |
| front-pixel-v1/front-16x24.png | `f188d843f64c3d2c54f1442deff625ddee920d6af14b59c64a8ec422976efffc` |

素材/ゲーム・共有進捗の編集、コミット、再委任、Godot/import、OS入力/前面化/カーソル操作なし。最終受入は親へ返す。
