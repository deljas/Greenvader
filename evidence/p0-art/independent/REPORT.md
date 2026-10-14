# P0-ART 独立検証報告

2026-10-14。対象: 基準HEAD `389fd697554400bbf5c2ac6e3e27ba1ca870bf89` と凍結P0-ART差分。仕様根拠: `tasks/P0_ART.md`、資料01/02/03、前回S01/S02。実装者の報告や自己22PASSを独立試験の証拠として代用していない。

## 対象・環境・実行

- Windows、PowerShell、Godot `4.7.2.stable.official.ed1daf0bf`。独立実行はheadless、ログ上のrenderer識別はforward_plus。GPU描画を独立して起動したとは扱わない。
- `git diff 389fd69` の既存ゲーム差分を読み、新規 `landscape_art.gd` と `landscape_prop.gd` も全行読んだ。共有docsの他者変更は戻していない。
- 独立開始時の9ゲームファイルは `source-start.json`。終了時の凍結manifest10件（自己テストを含む）は `source-end.json`。凍結manifestと全10件一致、開始時に取得したゲームファイル9件も終了時まで変化なし。
- 最初の実行は標準user://ログへの書込エラー、標準AppDataでのeditor importにも権限エラーが出た。ゲームの回帰失敗と区別し、初回ログ `checks.log` と `import.log` を残した。
- 再試験ではAPPDATA/LOCALAPPDATAをこの証拠ディレクトリ内の一時 `profile/roaming` / `profile/local` へ分離し、`--log-file`も指定。個人の設定・セーブを読み書きする必要がない環境でimportとテストを再実行。終了後に環境変数を復元し、生成した隔離profileのみ削除した。ログは保持している。
- エラーなしの独立import: `import-isolated.log` / `import-engine-isolated.log`、終了コード0。
- 本物の `scenes/main.tscn` を使った独立回帰: `checks-isolated.log` / `godot-runtime.log`、**35 PASS / 0 FAIL**、終了コード0。試験コードは `tests/independent/p0_art_checks.gd`。
- 実行終了後、親へGodot所有権を返却済み。旧ユーザーwindowや親のnative画面を操作していない。P1〜P5試験は行っていない。

再現時のコマンド（APPDATA/LOCALAPPDATAの上記隔離を行った子プロセス環境）:

```powershell
& C:/godot/Godot_v4.7.2-stable_win64_console.exe --headless --editor --path C:/godot/greenvader --log-file C:/godot/greenvader/evidence/p0-art/independent/import-engine-isolated.log --quit
& C:/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path C:/godot/greenvader --log-file C:/godot/greenvader/evidence/p0-art/independent/godot-runtime.log --script res://tests/independent/p0_art_checks.gd
```

## 合格条件ごとの結果

| 作業票条件 | 結果と確認できた範囲 | 未検証の範囲 |
|---|---|---|
| 1 内部640×360・整数拡大・Nearest・花16px・輪郭／ぼかし | **PASS（設定・ロジック・静止画像）**。本物sceneで640×360、viewport/keep/integer、最小寸法640×360、花texture16×16、Nearest。実ソースは整数ラスタ、元スプライトの任意回転・非整数拡大・全画面blurなし。晴雨夜の640×360 PNGで鮮明な画素と面の陰影を確認 | **NOT_RUN**: 最終版nativeの3サイズ実余白／倍率、native最小化、移動中の画素厚み。コード上の設定を実画面PASSにしていない |
| 2 樹冠・陰・苔岩・曲がる水辺・廃墟・開けた道・重なり | **PASS（最終PNG目視、静的）**。初期構図のまとまった樹冠、地面影、明暗の岩面、曲がる川、蔦付き二面の廃墟、中央から上へ続く道を確認。微細な点だけを増やした画面ではない。上下の樹木と岸の岩に静止時の前後関係が見える | **NOT_RUN**: 移動で前後関係が切り替わるGPU描画 |
| 3 晴雨夜の主役・敵・仮弾判別 | **PASS（同じ初期構図のPNG目視）**。花は中央の花色と形、2体の敵は横長の胴体と脚、種は黄系、水は水色として各3条件で識別できる。夜は花の周囲に別発光、原スプライトは鮮明 | **NOT_RUN**: 全マップ位置・密集背景での視認性、native連続操作、動いている弾の追いやすさ |
| 4 背景装飾と緑化データを区別、後続仕様維持 | **PASS（静的）**。今回の背景と地形はpresentation専用で、緑化対象集合・植物成長・地域状態の新しいデータやルールを定めていない。ゲーム変更は景観、UI、S01/S02に限られる | 後続ゲーム仕様の実行試験は今回範囲外 |
| 5 S01/S02の修正と回帰 | **PASS**。S01は実行中に作った種の原寸ラスタを保存して目視と画素値を確認。S02は本物sceneのEscイベントと本物の雨button callbackで実動作を確認。詳細は下記 | **NOT_RUN**: nativeマウスによる実ボタンクリック |
| 6 import・起動・検証と最終画像 | **PASS（独立headless import・本物scene起動・35回帰）**。最終ソースhashとself manifest一致。最終晴雨夜PNGの目視を実施。5つの最終画像は実装担当が取得した内部viewport PNGであり、実装担当取得と独立閲覧を区別 | **NOT_RUN（独立取得）**: 3解像度のGPU画像を本担当自身では再取得していない。既存PNGにはnative外枠・余白が含まれない |
| 7 独立検証と親画像確認を区別 | **PASS（独立作業）**。本報告でheadless実動作、静的、PNG目視、native未検証を分離。親の画像／native確認は親の記録へ委ねる | **NOT_RUN（本担当）**: 親の受入判断、人間の最終美術／楽しさ承認 |

## S01: 種の全周暗色

**PASS（runtimeラスタと目視）**。`seed-source.png` はゲーム自身の `PixelArt.seed().get_image()` から保存した6×4 PNG。透明以外の画素を読み出した結果:

```text
transparent transparent FFE5A0 FFE5A0 transparent transparent
transparent FFE5A0 FFE5A0 FFE5A0 DCAB72 transparent
transparent FFE5A0 FFE5A0 DCAB72 DCAB72 transparent
transparent transparent DCAB72 DCAB72 transparent transparent
```

明色が上部と左側シルエットに達し、暗い色は右下の面に寄っている。前回の「暗色が明色中心を全周囲む」構造が解消した。実装の色判定式をテストの合格オラクルへコピーしていない。種以外も含む最終晴雨夜PNGを閲覧し、外周を暗線で囲む追加outlineや全面ぼかしは確認されなかった。この小素材の技術修正はユーザーの美術承認と同一ではない。

## S02: ポーズ中の雨ボタン

**PASS（本物sceneの入力・signal callbackを実行）**。

1. production input callbackを通して寿命中の仮弾を作る。
2. Escの押下／解放を `Input.parse_input_event` に入れ、SceneTree.pausedがtrueになることを確認。
3. 本物の上部雨buttonのpressed signalを強制発火する（ボタンdisabledを越えてcallback自体も試す）。同時に移動入力を入れ、pause中の0.20秒を待つ。
4. conditionとweather.conditionはsunny、weather.elapsedは `0.25552833333333` のまま。主人公はsimulation/displayとも `(480,368)`。仮弾はposition `(466.3685,359.6224)`、age `0.1`、表示 `(466,360)`、countも変化なし。
5. Escで再開後、同じ雨button signalでconditionとweatherがrainへ変わる。elapsedは再進行し、観測した増分約0.060301秒で停止時間0.20秒の一括加算はない。

固定値を期待値にした試験ではなく、停止前後の不変性と再開後の変化を観測した。証拠は `checks-isolated.log`。nativeのキー／マウスを操作した試験ではない。

## 移動、カメラ、局所透過

- **PASS（固定時間のロジック）**: 本物playerに8方向を各60回×1/60秒で入力し、距離同士を比較。観測距離は約95.9991〜96.0006px、方向による増速なし。速度定数や正規化式を期待距離の式へ写していない。
- **PASS（表示状態）**: 小数simulationを保持しながら、各ステップでplayer表示が整数、camera位置が同じplayer表示になることを確認。**NOT_RUN（描画）**: 実画面の更新順や移動中のにじみ。
- **PASS（局所透過ロジック）**: 本物propの背後で重なる位置、前側、横に離れた位置を順に試す。背後でalpha約0.42、透過は1propのみ。前側と離隔時はalpha1.0へ戻る。playerとsceneryが同じy_sort親にあることも確認。
- **NOT_RUN（描画）**: 重なり移動中のGPU上のy-sort実順序、透過後の花の読め方。このロジック試験を動的描画合格へ昇格させない。

## 結論と未確認

独立実行の回帰FAILはなし。初回のログ／editor権限エラーは隔離した環境で解消し、ゲーム不具合として報告していない。今回の変更に対するS01/S02回帰と静止景観確認は上記範囲でPASS。

最終版nativeの連続移動・照準・斜め移動・画面端・余白の実画素・最小寸法操作・ボタン操作、全域の視認性、GPU動的y-sort／透過／にじみはNOT_RUN。書き出し、性能負荷、P1〜P5は今回対象外。本報告はP0全受入の合格判定でも商品アート承認でもない。

本担当が編集したのは独立テストと独立証拠のみ。importが生成したcache／PNG importメタデータは明示された実行の派生物で、ゲームソースは変更していない。コミット・ブランチ操作・再委任・共有進捗更新なし。最終受入は親が判断する。
