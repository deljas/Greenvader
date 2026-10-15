# 検証記録

更新日: 2026-10-15。最終合否は親Astra（Codex）／主会話Opus（Claude）が判断する。テンプレートの静的確認と実モデル稼働を区別する。

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

## P1の結果

更新日: 2026-10-15。P1（[段階票](../tasks/P1.md)）の子票P1-01〜P1-06は、親（Opus）の完了記録（2026-10-15）で完了。実装の自己試験は green-implementer、独立検証は別呼出しの green-verifier（いずれも親の報告によるモデル claude-sonnet-5-5）。最終合否は親が判断する。本節は親の完了記録の転記で、文書担当は追加の検証を行っていない。

### 子票ごとの結果

| 子票 | 実装の自己試験 | 独立検証 | 証拠 |
|---|---|---|---|
| P1-01 格子と地域データ | headless 92 PASS / 0 FAIL（P0既存 22/35 PASS） | 48 PASS / 0 FAIL。開始・終了のハッシュ一致 | `evidence/p1/p1-01/`、`independent/checks.json` |
| P1-02 種・水の資源と着弾 | headless 130 PASS / 0 FAIL | 77件: PASS 75 / NOT_RUN 2（GPU窓の注入照準、物理入力）/ FAIL 0 | `evidence/p1/p1-02/`、`independent/checks.json` |
| P1-03 成長サイクルと種生産 | 106 PASS（回帰: p1_02 130、p1_01 92、P0 22/35） | 199 PASS / 0 FAIL。ハッシュ一致 | `evidence/p1/p1-03/`、`independent/checks.json` |
| P1-04 自然拡張 | 85 PASS（回帰 FAIL 0） | 56件: PASS 55 / FAIL 1（`gpu.pixel_oracle`、下記の扱い参照） | `evidence/p1/p1-04/`、`independent/checks.json`、`checks_gpu_offline.json` |
| P1-05 にんじん・キウイとHP | 181 PASS（回帰 FAIL 0） | 1回目 127件: PASS 125 / FAIL 2（F1は製品の不具合で修正、F2は検証側の閾値ミス）。再検証r2でF1はPASS、ハッシュ一致、回帰 FAIL 0。r2の件数は完了記録に記載なし | `evidence/p1/p1-05/`、`independent/checks.json`、`checks_r2.json`、`r2/` |
| P1-06 統合検証と調整 | 95 PASS（回帰 FAIL 0） | 173件を統合: PASS 170 / FAIL 3（下記の扱い参照）。ハッシュ一致 | `evidence/p1/p1-06/`、`independent/checks.json` |

### 検証側のFAILと扱い（親の判断）

- P1-04 `gpu.pixel_oracle`: P0の景観が試験領域を覆ったため、検証側の設計不備と判断。headlessで同じ世界を再構築して撮影画像と照合し、8,193タイルで不一致0（`checks_gpu_offline.json`）。実装者の `p1_04_gpu.gd` もFAIL 0。製品の不具合ではないとして親が受け入れた。
- P1-05 F1: 保存の読込で未成熟の足場を受け入れていた。製品の不具合として実装者へ戻し、修正後にr2でPASS。
- P1-05 F2: 検証側の閾値ミス。オフラインで再評価してPASS。
- P1-06 FAIL 3件（`checks.json` の `fail_ids`）: `gpu.edge.water_beyond`、`gpu.fruit.readable_shore`、`gpu.stress_frame`。完了記録では「いずれも検証側の判定基準の問題（GPU窓のプローブ位置、自前の閾値、フレーム時間モニタの不具合）」と分類している。対応は、`gpu.edge.water_beyond` がプローブ位置の誤り（目視では岸で正しく停止）、`gpu.fruit.readable_shore` が検証者の自前のコントラスト閾値1.8を岸の砂で2色が下回ったもの（濃い赤は3.38。描画は仕様どおり正確）、`gpu.stress_frame` がフレーム時間モニタの不具合で固定値を返したもの（GPU込みのフレーム時間はNOT_RUNとし、P5-03で測る）。親が独立検証者の報告に基づいて判断した。
- 親の判断: 完了記録は、P1の合格条件、歩行、地図、安全地帯の実、テンポの再現、性能をすべてPASSと記す。親はこれを根拠にP1を完了とした。

### P1合格条件の統合結果（P1-06の独立検証）

P1-06の完了記録は合格条件を「7項目」とし、すべてPASSとする。P1の段階票（[P1](../tasks/P1.md)）の箇条書きは6項目のため、対応は次の表に示す。「7項目」は[開発計画](03_DEVELOPMENT_PLAN.md)のP1合格条件（7項目。ポーズ中に資源・成長が進まないことを含む）を指す。段階票の6項目に、ポーズの条件を加えたものとして扱う。

| P1の合格条件 | 主な検証ID（`checks.json`） | 結果 |
|---|---|---|
| 種の着弾→発芽→成熟→種生産がつながる | `chain.stages_in_order`、`chain.fruit_appears`、`chain.collect`、`chain.refire` | PASS |
| 水やりで成長が速まり、水ゼロでも成長する | `water.dry_grows`、`water.faster` | PASS |
| 種ゼロ・水ゼロから回復して開拓を再開できる | `recover.seeds_zero`〜`recover.refire`、`recover.water_zero`〜`recover.water_shallows` | PASS |
| 成熟領域から自然に広がり、にんじんの促進とキウイの回復を確認できる | `spread.carrot.*`、`spread.control.*`、`kiwi.fruit`、`kiwi.heals` | PASS（にんじんの全体効果は小さい。下記の持ち越し） |
| 対象外へ発射しても不正な増加が起きない | `invalid.*`（`invalid.no_change`、`invalid.greened` など） | PASS |
| ポーズ中に資源・成長が進まない | `pause.frozen`、`pause.no_banked_time` | PASS |

P1-06の統合結果: 173件中、PASS 170、FAIL 3（上記）。歩行、地図、安全地帯の実、テンポの再現、性能の項目はPASS。

### 試験用ボットと測定値（P1-06）

- 開拓（ボット(a)）: 24.5〜29.9分で100%。一地域クリアの目安（30〜60分）との比較は、P2の敵と人のプレイで再確認する。
- 自然拡張のみ: 上限 51.5%。
- 前線速度: 約2.6タイル/分（P1-06の記録）。P1-04の記録では4.0タイル/分。
- 地図: 対象 244,759。開始点から歩いて届く対象 244,202、届かない対象 557（島8か所）。足で通るには浅瀬の渡りが必要な東岸は 118,520（python検算）。
- 性能（CPU、GPU窓の結果ではない）: 実プレイ相当（3分）の最大 1.7ms。ストレス時で最大 9.7〜13.4ms。P1-04の記録では、最悪条件のCPUは約11.7ms、実GPU込みは約14.7msと推定。

### 未検証事項

- 物理入力: ホイール・Tabでの植物切替、クリックでのにんじん・キウイの植え付け、水・建物で止まる歩行、浅瀬の渡り。自動検証はエンジン内注入のみで、物理経路の証拠ではない。ユーザーの手動確認はSTATUSの「ユーザー確認待ち」に積んだ。
- 実窓での照準の注入マウス（P1-02のNOT_RUN）。
- GPU込みの最重フレーム: 実測はCPUのみ。GPU込みの計測はP5-03で行う。
- 楽しさ・見た目の評価: AIは代行していない。ユーザーの感想は非同期で受け付ける。
