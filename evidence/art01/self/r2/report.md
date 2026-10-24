# ART-01 r2 自己報告

- 対象版: HEAD `99013702eaf36db72a64d60d284680fb834f13c5` 上の未コミットART-01 r2。プログラム凍結済み。Godot 4.7.2 stable / Windows。
- 変更ファイル: `scripts/art_study/study_raster.gd`、`tests/art01/self_check.gd`、`evidence/art01/self/r2/` のみ。
- 実装内容: 草下地の座標wave色むらを除去して `#466d46` 固定へ。土下地の区画色むらも除去して `#716c60` 固定へ。草の房の位置・数（A129/B280）・形、短い葉の細部を生成する処理、樹木・既存見本は変更していない。検証のOUTPUTだけr2へ変更。Bへ育つ方針の成長処理や新しい照明処理は今回実装しない。
- 実行した検証と結果: 既存の短いself_checkを1回のみ実行し **15 PASS / 0 FAIL / 2 NOT_RUN**。エンジン内A/B入力、キャッシュ、固定画素再現、素材サイズ、同一構図とPNG出力がPASS。実行エラーなし・終了コード0。import追加・全ゲーム回帰なし。限定差分を `changes.patch` へ保存。自己プロセス終了後 `Get-Process Godot*` は0件、実行資源解放済み。
- 証拠: `self-check.log`、`checks.json`、`source-manifest.json`、`changes.patch`、変更前の原文 `before/*.gd.txt`。新 `A_restrained_2x.png` / `B_rich_2x.png`、`AB_detail_4x.png`（左A/右B）、`AB_field_2x.png` と640×360原寸PNG。旧self証拠は保持。
- 未検証事項: 実ウィンドウ・日本語UI描画・物理入力は引き続きNOT_RUN。新PNGは同じコードによるCPU画素合成で、実画面の撮影ではない。OS入力送信・カーソル移動・前面化は行っていない。
- 残課題/文書担当へ: ユーザーは最終的にB密度へ育つ方針を採用。地面に直接描く広域の明暗差を却下し、後の光表現で扱う。房や木自体の小さな葉先・根元・素材陰影は維持。成長段階/時間・ゲーム統合・照明実装は今回の対象外。共有文書は子から更新していない。r2の独立確認と親の判定を待つ。

実行コマンド（PowerShell、1回実行済み）:

```powershell
$env:APPDATA = 'C:/godot/greenvader/evidence/art01/self/r2/profile'
& C:/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path C:/godot/greenvader --script res://tests/art01/self_check.gd --log-file C:/godot/greenvader/evidence/art01/self/r2/self-check.log
```
