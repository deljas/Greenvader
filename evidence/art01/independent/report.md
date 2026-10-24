# ART-01 独立検証

対象は HEAD `99013702eaf36db72a64d60d284680fb834f13c5` 上の未コミット試作。Windows 10.0.26200.0 / PowerShell 7.6.5 / Godot `4.7.2.stable.official.ed1daf0bf`、共有作業ツリー。実環境情報は `source-start.json`、Godot版と隔離データ先は `runtime-checks.json` を正本とする。

実装者の合格報告を代用せず、AGENTS.md、tasks/README.md、ART_01.md、docs/00〜04、STATUS、DECISIONS、P0_ART、追加実装全ファイル、既存の描画設定と参照素材を読んだ。A/Bの2倍PNG、AB_field_2x.png、AB_detail_4x.pngを view_image で確認した。独立テストを1回実行した。結果は **8 PASS / 0 FAIL / 3 NOT_RUN**。実画面・日本語UIと物理入力は未検証なので、作業票全体の最終受入は親へ返す。

| 確認条件 | 結果 | 確認できた事実・証拠 |
|---|---|---|
| 専用シーンの起動とエンジン内切替 | PASS | headlessでインスタンス化し、A/Bキー注入とBボタンsignalが選択を切替。終了コード0、stderr空。`headless.log`、`runtime-checks.json`。 |
| PNGの由来と整数画素 | PASS | 実行シーンの640×360画像と保存PNGが全バイト一致。1280×720 PNGの全画素が元画素の正確な2倍。CPU合成の証拠に限定。 |
| A/B同条件と密度差 | PASS | 5,537画素に差、草比較領域外の差0。コードではrich引数の影響は背の高い房の選別だけで、短草・色・光・構図は同じ。PNGではBに房が増え、同じ広い疎密と荒地境界を維持。 |
| 既存見本の寸法と配置 | PASS | 花16×16、拾える種4×4、敵32×18を既存素材と照合。A/B内の花・種3個・敵の不透明画素がすべて既存素材の同じ画素と一致。木は新規64×84、拡縮なし。 |
| 固定模様・キャッシュ・Node数 | PASS | 位置ベースの決定的描画に乱数や毎フレーム生成がない。入力とidle後も元の2テクスチャを保持。子孫Nodeは7で増加なし。将来の4px表示への位置関数分離は静的確認のみ、状態統合済みとはしない。 |
| 内部解像度・Nearestと通常ゲームの分離 | PASS | 640×360、viewport stretch、integer、keepを既存設定から継承し、比較シーンがNearestを明示。project.godotと既存ゲーム実装にtracked差分なし。新規シーンはWorldState/保存/通常mainを起動せず、既存進行へ書き込む経路なし。専用batのGodot実行ファイル存在を確認。 |
| PNG上の房・明暗・視認性 | PASS | 短草の連続面と広い色むら、背の高い草の分かれた葉先・暗い基部を確認。木は左上の明部・右下の大きな陰と重なる房を持つ。暗色による全周の縁取りは見られない。両案の花・黄/桃の小さな種・茶色の敵は識別可能。木の葉の細部の完成度や参考5枚への美術的な到達度・採用好みは承認しない。 |
| 対象版の固定 | PASS | 8ソース/uid、5依存、6PNGの計19ハッシュが開始/終了で不変、かつ実装凍結manifestと一致。HEAD不変。`source-start.json`、`source-end.json`。 |
| native描画・日本語UI・実際の整数表示 | NOT_RUN | フォーカスを奪わない起動を保証できず、親の指示に従いnativeウィンドウを起動しなかった。CPU PNGはスクリーンショットではなく、文字を含まない。 |
| OS経由の物理キー/マウス操作 | NOT_RUN | OS入力、前面化、カーソル移動は実施していない。エンジン内入力とsignal確認は物理経路を証明しない。 |
| Windows書き出し後の起動 | NOT_RUN | ART-01の範囲外。書き出し・配布ビルドの検証は実施していない。 |

`checks.json` は上表の機械可読版。5件の実行チェックに3件の静的/画像確認を加えた集計であり、実装者の15件を再計上していない。FAILは見つからなかったため、不具合再現票はない。

検証用APPDATAは `evidence/art01/independent/profile/` に分離（既存gitignore対象）。既存セーブは触っていない。Godot headlessを Start-Process -WindowStyle Hidden で1回起動し、全終了済み。実装ファイル・設定・素材・共有進捗文書は編集していない。親から伝達された既存P2の未追跡uid6件も触っていない。

再現: PowerShellでAPPDATAを上記隔離profileに設定し、Godotへ `--headless --path C:/godot/greenvader --script res://tests/art01/independent_check.gd --log-file C:/godot/greenvader/evidence/art01/independent/headless.log` を渡す。ユーザーによるnative確認は `run_art_study.bat` から起動し、日本語UI、A/Bボタン、A/Bキー、1280×720以上の画素表示を確認する。

最終受入・A/Bの採用・美術評価は親とユーザーが判断する。
