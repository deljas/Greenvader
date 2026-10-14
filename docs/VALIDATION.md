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

### P0_VERIFYへ残した確認（当時の一覧。次節の結果で閉じた）

- `@oai/sky.press_key('2')` と `press_key('Escape')` では画面変化を観測できなかった。物理キーコード等を含む入力経路の原因は未切分。ゲーム側キーボード不具合とは確定しておらず、nativeキーボード操作PASSにもしていない。
- nativeのWASD連続・斜め移動、マウス照準と種／水の発射、Escポーズは未確認。
- 最小ウィンドウへのnative resize、複数サイズの外枠余白画素、移動中のにじみ、画面端カメラ、動的y-sort/局所透過、Forward+性能負荷は未確認。
- P0全技術条件の合格、Windows書き出し、P1以降の機能は未確認。

## P0_VERIFYの結果

更新日: 2026-10-14。対象 `138664a`。ゲームファイル（`scripts/`、`scenes/`、`project.godot`）は `32cf318` から差分なし。検証開始・終了時のSHA-256は一致（[source-start.json](../evidence/p0-verify/independent/source-start.json)、[source-end.json](../evidence/p0-verify/independent/source-end.json)）。判定は [checks.json](../evidence/p0-verify/independent/checks.json) の57件（PASS 54 / NOT_RUN 3 / FAIL 0）。再現は [run.sh](../evidence/p0-verify/independent/run.sh)。実行環境は Godot 4.7.2 stable、RTX 5070 Ti、Vulkan / Forward+、非headlessのGPUウィンドウ。独立検証の担当は別の呼出し文脈の検証者（親の報告によるモデル claude-sonnet-5-5）。

入力はすべてエンジン内の `Input.parse_input_event` による注入で行った。OS入力の送信とカーソル移動は行っていない（ユーザー指示により毎回の明示承認が必要。[AGENTS.md](../AGENTS.md)）。ただし、起動した検証用ウィンドウは通常の起動動作としてOSのフォーカスを得ていた（[残課題](BACKLOG.md)）。

| 区分 | 結果 | 限界 |
|---|---|---|
| V1 入力（1280×720） | WASD各方向と斜めは約96px/s（斜めは正規化、95.9993〜95.9999px/s）。左クリックで種、右クリックで水が出て照準方向へ飛ぶ。1/2/3キーと上部の天候ボタンで天候が切り替わる。Escで停止し、Escと再開ボタンで再開する。停止中は移動・発射・天候変更・既存弾の進行が止まる | マウス照準の注入は不可（NOT_RUN）。Godot 4.7.2 では照準が実OSカーソルの位置を読むため。実カーソル位置の読み取りで、照準方向の計算を5地点で確認（PASS）。弾速は仕様に値がなく判定していない |
| V2 表示 | 1280×720は k=2、余白0。1366×768は k=2、内容1280×720、余白は左右43・上下24。1920×1080は全画面（非排他）で k=3、余白0。いずれも期待値（[p0_layout_oracle.ps1](../tests/independent/p0_layout_oracle.ps1)）と一致。320×200などを要求しても実寸法は640×360を下回らない | 全画面は非排他のみ。排他モードは範囲外。窓の画面取得では下端の角12×12pxがDWM由来の非ゲーム画素になるため判定から除外した。PrintWindowでは出ない（同じ結果を確認） |
| V3 動的描画 | 移動中、斜め移動中、カメラ端の4方向、弾の飛行中、晴・雨・夜の場面、計138枚で、k×kブロックの非均一は0（にじみなし）。カメラは右960、上180、左320、下620の端に到達 | 判別性（主人公、イノシシ、種・水の仮弾）は目視による主観判断。晴・雨・夜のいずれでも判別できたが、雨と夜の種の仮弾は低コントラスト |
| 物理キーボード・マウス → OS → Godot | 自動検証はNOT_RUN | ユーザーの手動確認（下記）で補う。エンジン内注入は物理経路の証拠ではない |

### 手動確認（ユーザー、2026-10-14）

ユーザー自身が `run_game.bat` から起動し、次の6項目すべてが「問題なし」だった。

1. WASD・斜め移動
2. 実マウスで照準が回る
3. 左クリックで種、右クリックで水が飛ぶ
4. 1/2/3キーで天候が切り替わる
5. Escでポーズと再開、再開ボタン
6. ウィンドウを最小寸法より小さくできない

前回 `@oai/sky` で 2 / Escape キーが不応答だった件は、この手動確認によりゲーム側の不具合ではないと切り分けられた。sky側の入力経路の原因は未特定。

### 親の判断（Opus、2026-10-14）

- P0_VERIFYの合格条件をすべて満たしたと判断し、完了とする。
- P0（[開発計画](03_DEVELOPMENT_PLAN.md)の合格条件5項目）を技術受入とする。
- 範囲外として未検証のもの: 性能負荷、全画面の排他モード、Windows書き出し、P1以降。y-sortと局所透過の画面上の結果は、個別の検証記録がないため、ここでは完了として扱わない。
- これは最終商品アートの承認ではない。

## 初回のインポート権限エラー

独立P0_ART確認の初回は標準AppData / `user://` ログ書込み権限エラーが出た。`APPDATA` / `LOCALAPPDATA` を一時隔離profileへ向け、`--log-file` を指定した再実行でimportと独立回帰を完了。初回の環境権限エラーをゲームFAILとは扱わない。詳細はP0_ART独立報告を参照。
