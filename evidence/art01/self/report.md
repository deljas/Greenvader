# ART-01 実装者自己報告

- 対象版: HEAD `99013702eaf36db72a64d60d284680fb834f13c5` 上の未コミット試作。Godot `4.7.2.stable.official.ed1daf0bf` / Windows。内容識別は `source-manifest.json`。親の指示で実装凍結済み。
- 変更ファイル: `scripts/art_study/study_raster.gd`、`scripts/art_study/art_study.gd`（各 `.uid`）、`scenes/art_study.tscn`、`run_art_study.bat`、`tests/art01/self_check.gd`（`.uid`）、本証拠フォルダ。共有票・企画・STATUSは編集していない。
- 実装: 専用シーンに短い草の全面と、背の高い房の群落を配置。A控えめ129房 / B豊か280房。同じ短草・パレット・光・構図で、BはAの全房を含む。草は3〜5本の細く曲がる葉とずれた基部。広葉樹1種64×84pxは左上の明部と右下の深い青緑影、大小の葉の房。既存の花16×16px、黄と桃の拾える種4×4px、イノシシ32×18pxと荒地境界を配置。位置の固定ハッシュと起動時2枚のキャッシュで描画し、草ごとのNode・毎フレーム再生成はない。将来4px状態マスの表示へ導入するための位置関数を分離し、今回は状態層へ接続していない。
- UI: 日本語のA/BボタンとA/B・1/2キー。1280×720初期/最小ウィンドウ、640×360内部、既存の整数viewport拡大を継承し、Nearestを明示。専用batは通常ゲームと別シーンを開く。

## 実行した検証と結果

- 15 PASS / 0 FAIL / 2 NOT_RUN: `checks.json` と `self-check.log`。シーン構築、素材サイズ、密度差、固定位置再現、同じ土と不透明樹冠の画素、エンジン内A/B入力注入、ボタンのsignal接続、切替後も2枚のキャッシュ、設定、PNG保存を確認。
- 初回の樹冠比較テストは矩形内の透過箇所の草まで比較したため1 FAIL。比較対象を樹冠の不透明画素へ修正した。草・木の形のまとめ修正後に影響結果を再取得し、最終は全15項目PASS。
- importは終了コード0、クラス登録完了。`import.log` にsandbox内の設定safe-save警告1件が残る。初回は通常APPDATAへの権限エラーがあり、証拠フォルダ内のAPPDATAへ切り替えた。画像素材の外部importは不要。警告を無かったことにはしていない。
- 最終専用シーンを `--headless --scene res://scenes/art_study.tscn --quit-after 2` で起動、終了コード0・エラーなし（`headless-scene.log`）。
- `git diff --exit-code HEAD -- project.godot scenes/main.tscn scripts/landscape_art.gd scripts/pixel_art.gd scripts/play/play_art.gd scripts/world/region_view.gd` は終了コード0。通常ゲームの既存ファイルの変更なし。
- OS入力送信、カーソル移動、前面化、外部操作ツールは実行していない。
- 自己検証の全プロセスは終了。資源解放時 `Get-Process Godot*` は0件。以後、実行/import資源は親と独立検証者へ引き渡した。

再現コマンド（リポジトリ直下PowerShell、実ウィンドウを開かない）:

```powershell
$env:APPDATA = 'C:/godot/greenvader/evidence/art01/self/profile'
& C:/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path C:/godot/greenvader --script res://tests/art01/self_check.gd --log-file C:/godot/greenvader/evidence/art01/self/self-check.log
```

## 証拠

- `A_restrained.png` / `B_rich.png`: 640×360コード製画素合成。
- `A_restrained_2x.png` / `B_rich_2x.png`: 同じ絵の最近傍2倍。
- `AB_field_2x.png`: 全地面、左A / 右B、最近傍2倍。
- `AB_detail_4x.png`: 同じ座標の木・花・種・敵、左A / 右B、最近傍4倍。
- 上記PNGは実ウィンドウのスクリーンショットではない。実行シーンが使用する同じ画像データであり、日本語UIはPNGに含めていない。
- `source-manifest.json`: ソース/依存とPNGのSHA-256、HEAD、凍結時の差分状態。

## 未検証事項・残課題・文書担当への情報

- NOT_RUN: 実ウィンドウの描画、日本語フォント・UI配置、ボタンの実マウス操作、物理キーボード入力、実際の2倍画素表示。Godotの `--help` に起動前no-focusオプションが無く、確実にフォーカスを回避する方法を確認できなかったため、nativeウィンドウを開かなかった。ユーザーが `run_art_study.bat` で確認できる。
- 親は修正後PNGの草の扇状と密度比較を今回の試作として受入可能と判断。木の葉の細部はさらに詰める余地があると明示してユーザーに提示する。最終美術・好み・ゲーム全体の受入合格ではない。A/B採用は未決定。
- 参考2枚は目視参照のみ。画像そのものを転用せず、全てリポジトリ内の画素描画コードで制作。既存花・種・敵は既存コード素材を再利用。画像生成サービスは利用していない。
- importが既存P2テスト6件の不足 `.uid` を生成した。親へ報告済み、割当外のため子は編集せず、親が最終整理する。旧 `runtime/` のエディタ設定も親が整理する。以後の環境退避先は既存ignore対象の `profile/`。
- 通常ゲームへの適用、成長・境界・緑化率の変更、追加美術修正は行っていない。共有文書への追記は文書担当に渡す。
