# 検証記録

更新日: 2026-10-14。最終合否は親Astra（Codex）／主会話Opus（Claude）が判断する。テンプレートの静的確認と実モデル稼働を区別する。

## ENV-001 共用環境テンプレート

- 対象: 基準 `389fd69`、P0_ART保存コミット `32cf3187f5682d4081daf86875de97067b69e886`、その後のENV-001文書・設定差分。独立検証者は `evidence/env-001/independent/source-manifest.json` に確認対象を固定。
- 親確認: `claude --version` と `claude --help` の読み取り結果はClaude CLI `2.1.296`。インストールや認証設定を変更していない。
- 独立静的レビュー: [`report.md`](../evidence/env-001/independent/report.md)、[`checks.json`](../evidence/env-001/independent/checks.json)、対象固定 [`source-manifest.json`](../evidence/env-001/independent/source-manifest.json)、監査コード [`audit.py`](../evidence/env-001/independent/audit.py)。JSON/YAML形式、main Opus・4 agent構成、各タスク管理欄、参照リンク、旧資料パスの除去、P0_ART 10ファイルのhash保全を確認。51 PASS / 0 FAIL。
- AstraはClaude共用環境テンプレートの整備と静的確認を受け入れた。これはClaudeの実セッション起動・agent実行の合格ではない。

| 項目 | 結果 | 限界 |
|---|---|---|
| Main / agentモデル指定 | 静的PASS: main・designer Opus、implementer・verifierを別々のSonnet、documenter Haiku | Claude起動時にaliasが実際どのモデルへ解決するか、アカウント可用性は未確認 |
| JSON / YAML / agent定義 | 静的PASS: 51項目の独立監査で指定形式、異なる4 agent名、別実装・検証、文書担当の制約を確認 | Claudeの実ローダーによる読み込みと実効ツール制約は未確認 |
| 9タスク票・索引・リンク | 静的PASS: 管理欄、担当、予約、引継ぎとローカルリンクを監査 | Markdownは原子的な排他ロックではなく、実運用での競合回避は未検証 |
| 旧P0_ART実装の保全 | PASS: 独立監査が凍結対象10ゲームファイルのSHA-256一致を確認。P0_ARTは `32cf318` 保存後も内容不変 | hash確認はP0ゲーム機能全体の受入ではない |
| Claude CLI | 親確認: `--version` / `--help` で2.1.296 | 実Claude session、agent稼働、model API/authは未確認 |

初回ENV監査は静的検証のみで、Claude/Godot/APIを起動していない。独立報告は今回のテンプレート整備を静的範囲でPASS、実稼働はNOT_RUNとしている。ENV-001の最終管理欄と予約解除は親が処理する。

## P0_ARTの限定結果

P0_ARTは `32cf318` に保存済み。実装者報告は [`evidence/p0-art/self/report.md`](../evidence/p0-art/self/report.md)、独立報告は [`evidence/p0-art/independent/REPORT.md`](../evidence/p0-art/independent/REPORT.md)。自己回帰22 PASS / 0 FAIL、独立回帰35 PASS / 0 FAIL。S01種の暗色全周とS02ポーズ中の天候変更経路は各証拠の範囲で修正確認済み。

最終内部画像は[晴れ](../evidence/p0-art/self/sunny-1280.png)、[雨](../evidence/p0-art/self/rain-1280.png)、[夜](../evidence/p0-art/self/night-1280.png)。実装者と独立検証者は静止画像内で景観方向と主役・敵・仮弾を確認した。親はnativeの[晴天画面](../evidence/p0-art/native-sunny.png)を記録し、ボタン操作で晴雨夜を切替えて日本語UIを確認した。これは全native入力の確認ではない。

### P0_VERIFYへ残す確認

- `@oai/sky.press_key('2')` と `press_key('Escape')` では画面変化を観測できなかった。物理キーコード等を含む入力経路の原因は未切分。ゲーム側キーボード不具合とは確定しておらず、nativeキーボード操作PASSにもしていない。
- nativeのWASD連続・斜め移動、マウス照準と種／水の発射、Escポーズは未確認。
- 最小ウィンドウへのnative resize、複数サイズの外枠余白画素、移動中のにじみ、画面端カメラ、動的y-sort/局所透過、Forward+性能負荷は未確認。
- P0全技術条件の合格、Windows書き出し、P1以降の機能は未確認。

## 初回のインポート権限エラー

独立P0_ART確認の初回は標準AppData / `user://` ログ書込み権限エラーが出た。`APPDATA` / `LOCALAPPDATA` を一時隔離profileへ向け、`--log-file` を指定した再実行でimportと独立回帰を完了。初回の環境権限エラーをゲームFAILとは扱わない。詳細はP0_ART独立報告を参照。
