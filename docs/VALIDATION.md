# 検証記録

更新日: 2026-10-23。最終合否は親Astra（Codex）／主会話Opus（Claude）が判断する。テンプレートの静的確認と実モデル稼働を区別する。

## POC2 第二弾

2026-10-21、親Astraは凍結ソースの限定技術受入を行い、ユーザー試遊へ引き渡した。これは楽しさ・テンポ・美術の評価や全体的な製品合否ではない。対象revisionは `151a53f20255489ef08481e2a353258cd8ac559c` と未コミット差分。第一弾の実装・保存は別領域に保ち、P6には進まない。

### 保全と独立結果

- 凍結した第二弾source16件は実行前後でSHA-256一致。第一弾baseline91件も実行前後で一致した（[freeze-before](../evidence/poc2/independent/freeze-before.json)、[freeze-after](../evidence/poc2/independent/freeze-after.json)）。
- 独立論理検証36項目は36 PASS / 0 FAIL（[結果](../evidence/poc2/independent/logic-results.json)、[ログ](../evidence/poc2/independent/logic.log)）。
- 追加境界検証では元の10項目がPASSし、敵fixtureを建物内へ置いた2件のFAILはfixture原因と確認。到達可能な敵配置による対象限定の追試5項目はPASS（[元結果](../evidence/poc2/independent/boundary-results.json)、[fixture診断](../evidence/poc2/independent/army-fixture-probe.log)、[限定追試](../evidence/poc2/independent/guard-affected-results.json)）。元のFAIL記録は保持し、解消理由を区別する。
- 独立GPU/Input確認は10項目中9 PASS、1項目はゲージ画像の画素読取FAIL。画像座標へウィンドウ倍率を重ねた計測側の誤りと特定し、GPU再実行はせず同一run画像の独立目視・画素差でHP/種/水のゲージを確認した（[元結果](../evidence/poc2/independent/map-gpu-results.json)、[画像確認](../evidence/poc2/independent/gauge-image-review.json)）。
- 独立最終レビューは有効な58項目をPASSとして集計（論理36、境界12、GPU/Input10）し、未解決の実装FAILはないと結論づけた（[独立最終レビュー](../evidence/poc2/independent/review.md)）。元のfixture/画素読取FAILは下記の限定追試・画像確認とともに記録保持しており、範囲を限定した技術確認として扱う。
- 独立検証者は [街区・UI・撤去・遮蔽カット・マップ拡大の画面](../evidence/poc2/view/)、自己試験とコードを確認。親も主要コードとUI画像をレビューした（[親レビュー](../evidence/poc2/integration/parent-review.md)）。

### 自己試験・確認範囲

実装者のシミュレーション試験は初回26 PASS / 2 FAILを保持し、その後の対象限定試験を7 PASS / 0 FAILと報告した（[自己報告](../evidence/poc2/self/simulation_report.md)、[初回結果](../evidence/poc2/self/simulation_results_initial.json)、[限定結果](../evidence/poc2/self/focused_results.json)）。3500ゲーム秒の自己試験1回で、孤立島とおたすけ植物の占有を含め100%へ到達した。独立検証者はその実行記録と実装コードを照合したが、独立での3500秒全走はNOT_RUNである。

### NOT_RUNとユーザー判断

- 物理キーボード・マウスからOSを通じた入力、ユーザーによる実操作確認。
- 序盤の楽しさ、補給待ちの体感、複数前線を任せる満足感、種収支・難易度の快適さ。
- 最終美術の承認、実速でのちらつきの主観評価、水面反射の磨き込み。
- 独立3500秒全走、全組合せ回帰、終盤最大密度の全域性能、配布用Windows build。
- 不正保存全形式のfuzz、全拠点規模の生産上限、敵相性と誘引・忌避の長期戦、退避と復帰の全組合せ。

天候は晴れ固定で、動植物は仮モデル。主人公の基本回復・HP・死亡後復帰など仕様未確定部分は実装初期値であり、ユーザー確定値ではない。詳しい操作は[POC2_GUIDE.md](POC2_GUIDE.md)を参照する。

## POC2-06 保守追補

2026-10-22、POC2-05の引渡し後に見つかった操作・自律動作境界の不具合を保守し、親Astraは限定技術受入しました。対象はHEAD `151a53f20255489ef08481e2a353258cd8ac559c` と共有未コミット差分です。実装変更は `scripts/poc2/simulation/plants.gd`、`scripts/poc2/simulation/persistence.gd`、`scripts/poc2/poc2_session.gd`、`scripts/poc2/poc2_main.gd`、`scripts/poc2/ui/poc2_ui.gd` の5ファイルに限定されています（[凍結manifest](../evidence/poc2/maintenance/freeze-manifest.json)、[実装差分](../evidence/poc2/maintenance/self/change.diff)、[画面/UI差分](../evidence/poc2/maintenance/view/)）。

### 確認結果

- backend自己試験は24 PASS / 0 FAIL。到達不能指示の維持と保存復元、新指示による復帰、部分補給・退避・帰路の復元、撃破同tickの保存復元を含む（[自己報告](../evidence/poc2/maintenance/self/report.md)、[結果](../evidence/poc2/maintenance/self/results.json)）。
- view自己試験は初回10 PASS / 2 FAIL。型付き配列によるtitle/pause menu復帰エラーを修正後、影響する通常起動経路を5 PASS / 0 FAILで追試しました。初回FAILは残し、未解消FAILとは扱いません（[自己報告](../evidence/poc2/maintenance/view/report.md)、[初回結果](../evidence/poc2/maintenance/view/checks.json)、[追試結果](../evidence/poc2/maintenance/view/menu-array-checks.json)）。
- 独立検証はlogic21 PASSとGPU/UI9 PASS、計30 PASS / 0 FAIL。到達不能と部分補給の保存復元、実combat撃破直後の保存、タイトル由来helpからのF5でslot不変、補給popup復帰、通常プレイF5を確認しました（[独立レビュー](../evidence/poc2/maintenance/independent/review.md)、[logic](../evidence/poc2/maintenance/independent/logic-results.json)、[GPU/UI](../evidence/poc2/maintenance/independent/view-results.json)）。
- 保守対象の第二弾manifest16件は実行前後で一致し、第一弾baseline91件も一致。全Godotプロセスは終了しています（[凍結manifest](../evidence/poc2/maintenance/freeze-manifest.json)、[実行前](../evidence/poc2/maintenance/independent/freeze-before.json)、[実行後](../evidence/poc2/maintenance/independent/freeze-after.json)）。

今回確認した主な修正は、到達不能な目的地で新しい指示まで待つこと、働く植物は敵から退避できること、部分補給で退避しても水・元の持ち場・補給意図を保つこと、撃破直後の保存が復元できること、タイトルからhelpを開いた状態のF5で既存slotを上書きしないこと、helpから補給popup/menuへ重複なく戻れること、title/pause menuの型エラー修正です。詳細条件は独立レビューと自己報告を参照してください。

### 限界と前回記録との関係

この追補はPOC2-05の58 PASSや原記録のfixture/画素計測FAILを置き換えません。今回は変更5ファイルの保守範囲を追加確認したものです。旧58項目の全再実行、3500ゲーム秒の再走、全状態・全敵経路・全破損保存の検証、全回帰、物理OS入力、配布build、最大密度の長時間性能、バランス・楽しさ・最終美術評価はNOT_RUNです。晴れ固定、仮モデル、水面反射磨き込み保留、おたすけ植物の仮スプライト維持も変わりません。

## POC2-07 マップのクォータービュー対応

2026-10-23、親Astraはユーザーが許可した地図の向き・操作改善を限定技術受入しました。対象はHEAD `151a53f20255489ef08481e2a353258cd8ac559c` と共有未コミット差分で、実行対象16 sourceを [`freeze-manifest.json`](../evidence/poc2/map_orientation/freeze-manifest.json) に固定しました。ランタイム変更は `scripts/poc2/ui/map_ui.gd` のみで、その最終SHA-256は `C55C323463F872F36C1956278872CBB0D1A163E55617668681319C73FF5074A6` です。

### 実装と確認結果

- 地面投影をゲームのyaw45°・仰角30°へ合わせ、全体マップの既存224×224枠内に横224×縦112の菱形、ミニマップに円形108枠を保ちました。地形は640×360の出力ピクセル中心から直接逆投影してサンプルし、既存画像を回転・補間しません。地形とアイコンは共通のスナップ中心を用い、UIアイコン・ゲージ・ボタンは正立します。2/4倍はカーソル下の地面を保持し、1倍へ戻すと全域を再表示します。地面円の活動範囲も同じ投影です。
- 自己確認は通常GPU確認13 PASS / fixture由来2 FAILを記録。移動指示fixtureが操作ボタンへ重なる問題と、水面セルを移動先にしたための正常な拒否を切り分け、通行可能かつボタン外のfixtureで限定追試3 PASS / 0 FAIL。最終セル境界の自己追試は2 PASS / 0 FAILです。初回ログは残し、fixture失敗を製品不具合へ数えません（[自己報告](../evidence/poc2/map_orientation/self/report.md)、[境界追試](../evidence/poc2/map_orientation/self/corner-report.md)）。
- 独立確認は初回18 PASS / 1 FAIL。実カメラとの方向比率、pixel中心の地形サンプルと逆変換、640×360描画、zoom anchor、通常移動、未知情報の非表示、時間停止、popup入力独占などを確認しました。FAILは世界端の見える植物アイコンを選べない境界不具合でした。アイコンhitを世界外クリック拒否より先に処理する局所修正後、影響追試5 PASS / 0 FAILで解消を確認。世界外の余白指示拒否も維持しています（[初回レビュー](../evidence/poc2/map_orientation/independent/review.md)、[限定追試](../evidence/poc2/map_orientation/independent/final-review.md)）。
- 初回の投影・地形・zoom等のPASSは最終修正後に再走していません。修正後追試前後で最新freeze16/16、第一弾baseline91/91のhash一致を確認しました。自己・独立ともエンジン内入力注入と前面化しないGPU画像を用いました。

### 未確認範囲

物理キーボード/マウス経路、書出し後の実行、全ゲーム回帰、長時間性能、ゲームの楽しさと最終美術評価はNOT_RUNです。今回の技術受入は地図の限定的な描画・入力確認を指し、第二弾全体の最終合否ではありません。

根拠: [凍結manifest](../evidence/poc2/map_orientation/freeze-manifest.json)、[自己報告](../evidence/poc2/map_orientation/self/report.md)、[自己の全体マップGPU画像](../evidence/poc2/map_orientation/self/full-explored.png)、[自己の移動中ミニマップGPU画像](../evidence/poc2/map_orientation/self/mini-moving.png)、[自己境界追試](../evidence/poc2/map_orientation/self/corner-report.md)、[独立初回](../evidence/poc2/map_orientation/independent/review.md)、[独立の全体マップ画像](../evidence/poc2/map_orientation/independent/full-revealed.png)、[独立境界修正画像](../evidence/poc2/map_orientation/independent/final-last-cell-selected.png)、[独立限定追試](../evidence/poc2/map_orientation/independent/final-review.md)。

## TECH-QV-01 クォータービュー専用試験

更新日: 2026-10-15。対象はHEAD `99013702eaf36db72a64d60d284680fb834f13c5` 上の専用シーン等。独立r1は[8件固定manifest](../evidence/quarter-view/self/source-manifest.json)を対象として13 PASS / 1 FAIL。マウス経路FAIL後、専用labの入力イベント位置保持を修正し、9件の[r2 manifest](../evidence/quarter-view/self/source-manifest-r2.json)へ固定した。r2はマウス関連3項目のみ再取得し3 PASS / 0 FAILで、幾何・投影・衝突・1080p再現や通常ゲームsmokeを再実行していない。通常ゲームの別プロセスGPU smokeは1回PASS。初回FAIL・診断結果は変更せず保持。結果を合算してPASS数を増やさない。

自己検証r1は[logic結果](../evidence/quarter-view/self/logic-results.json)16 PASS / 0 FAIL / 2 NOT_RUN、[GPU結果](../evidence/quarter-view/self/gpu-results.json)24 PASS / 0 FAIL / 1 NOT_RUN。logicの2 NOT_RUNはGPU未実施の項目と物理入力、GPUの1 NOT_RUNは物理入力。重複項目を合算しない。独立r1では衝突4面、近接周回、低障害物、画面方向等速、左右の花82画素、背面透過、整数camera、実native 2倍一致を確認。r1のマウス注入イベント経路FAILは既知screen位置からの逆変換PASSと分けて扱い、マウスのみr2で検証した。

| 条件 | 親が受け入れた結果 | 証拠・限界 |
|---|---|---|
| 専用960×540画面、前後左右の順序、遮蔽 | 独立r1 PASS、親確認 | [独立報告](../evidence/quarter-view/independent/report.md)、self/independentのGPU画像。単純な閉じた箱で確認 |
| 壁足元と衝突、通路周回、低障害物 | 独立r1 PASS | 4面停止位置、近接周回、障害物接触。通常ゲームへ移植した確認ではない |
| 画面方向・斜め等速 | 独立r1 PASS | Godot内Input.parse_input_event、画面上の速度。物理入力経路はNOT_RUN |
| マウス座標注入・カメラ再投影・地面マーカー | r1 FAIL後、r2の限定再検証3 PASS / 0 FAIL | [r1 report](../evidence/quarter-view/independent/report.md)のFAIL証拠を保持。[r2結果](../evidence/quarter-view/independent/mouse-r2-results.json)と[r2画面](../evidence/quarter-view/independent/r2_camera_reprojected_marker_960.png)。r2はマウス条件のみ |
| カメラ移動時の整数画素 | 独立r1 PASS（限定） | 斜めcameraの代表静止画で確認。動画・全位置網羅ではない |
| 1920×1080の実2倍表示 | 独立r1 PASS、親確認 | 全518,400個の2×2ブロックが原画一致、ブロック内不均一0 |
| 通常ゲームへの影響 | 別プロセスGPU smoke 1回 PASS | [結果](../evidence/quarter-view/independent/smoke-results.json)、[画面](../evidence/quarter-view/independent/normal_game_smoke_640.png)。通常設定640×360。通常ゲーム127ファイル不変 |
| 初期フォーカス不変の読取比較、物理入力 | NOT_RUN | OS入力送信・カーソル移動・前面化APIなし |
| 他解像度、複雑建築、性能、通常統合や全面回帰 | 対象外・NOT_RUN | 保存・戦闘等の通常ゲーム機能もこの試験では検証していない |

親は実装差分、画面、ログを確認し、専用技術確認と制作条件整理の範囲のみ限定受入した（[親の判断](../evidence/quarter-view/parent-acceptance.md)）。初期の地面マーカー層順は親レビューで自己検証前に修正。HUDセル文字列は1 physics tick遅れる既知制限だが、マーカーと座標は同tickで正しく、受入を阻害しない。r2で再確認した際の対象9件、通常ゲーム127件、既存非文書成果63件にhash不一致なし（[最終保全記録](../evidence/quarter-view/final-integrity.json)）。

技術方式・素材寸法・原点・分割条件は[専用技術記録](QUARTER_VIEW_TECH.md)。美術品質、完成素材、一般的な建築の成立、通常ゲーム統合の受入を示さない。

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

## ART-01 草地と広葉樹の比較試作

初回試作の履歴。対象はHEAD `99013702eaf36db72a64d60d284680fb834f13c5` 上の未コミット試作。親は比較試作とPNG提示の範囲を受け入れた。自己検証は[報告](../evidence/art01/self/report.md)・[checks](../evidence/art01/self/checks.json)で15 PASS / 0 FAIL / 2 NOT_RUN、独立検証は[報告](../evidence/art01/independent/report.md)・[checks](../evidence/art01/independent/checks.json)で8 PASS / 0 FAIL / 3 NOT_RUN。初回時点ではA/Bの選好は未決定だった。初回の[凍結manifest](../evidence/art01/self/source-manifest.json)と独立側の開始・終了記録では19ハッシュが一致した。最新r2は以下に記録。

専用シーン `scenes/art_study.tscn` と `run_art_study.bat` で、短草と背の高い房の密度A（129房）/B（280房）を比較する。短草・色・光・構図は同じ。独立検証では640×360のシーン画像と保存PNGの全バイト一致、2倍PNGの整数画素一致、エンジン内A/B切替、既存ゲームからの分離を確認した。これはCPU画素合成とheadless確認の結果で、実ウィンドウの描画証拠ではない。

| 項目 | 結果 | 限界 |
|---|---|---|
| 専用シーン、A/B比較、固定画素、既存ゲームとの分離 | 自己・独立の各証拠範囲でPASS | 通常ゲームへの統合、緑化や進行の変更は行っていない |
| 実画面、日本語UI、実際の整数拡大表示 | NOT_RUN | フォーカス回避を保証できずnativeウィンドウを起動していない。ユーザーが専用batで確認可能 |
| OS経由の物理入力 | NOT_RUN | OS入力・前面化・カーソル操作なし。エンジン内入力注入の結果は物理経路を示さない |
| Windows書き出し後の起動 | NOT_RUN | ART-01の対象外 |

初回の親受入は比較試作とPNG提示までで、実画面の技術受入や最終美術評価ではなかった。r2でのB選好と最新の受入は次節を参照。

### ART-01 r2 固定色の限定修正

対象は同じHEAD上の未コミットr2差分。自己の[報告](../evidence/art01/self/r2/report.md)・[checks](../evidence/art01/self/r2/checks.json)は15 PASS / 0 FAIL / 2 NOT_RUN。独立の[報告](../evidence/art01/independent/r2/report.md)・[checks](../evidence/art01/independent/r2/checks.json)は差分と画像の静的確認で3 PASS / 0 FAIL / 2 NOT_RUN。21件の対象ハッシュは[開始](../evidence/art01/independent/r2/source-start.json)・[終了](../evidence/art01/independent/r2/source-end.json)で一致した。独立側は追加実行せず、検査コードの参照画像・出力先をr2へ向ける変更のみである。

r2では草下地を `#466d46`、土下地を `#716c60` に固定し、広い位置依存の色むらを除いた。房の配置・形、木、局所的な葉先・根元の陰影は維持。親はコード差分と[更新B画像](../evidence/art01/self/r2/B_rich_2x.png)を確認し、この限定修正を受け入れた。ユーザーはB密度まで育つイメージを選好し、広域の地面明暗はマップへ描かず後の光表現にする方針を決めた。成長段階・時間、照明機能、通常ゲームへの統合は未実装。

| 項目 | 結果 | 限界 |
|---|---|---|
| 固定色、房・木・見本の維持 | 自己の短い確認でPASS。独立は差分・r2画像で確認しPASS | 独立側の房数を再集計していない。実画面の品質評価ではない |
| native画面、日本語UI、物理入力 | NOT_RUN | CPU合成PNGのみ。OS入力・前面化・カーソル操作なし |
| 成長・光表現、通常ゲーム統合 | 未実装・対象外 | r2は下地色の限定修正。Bを最終密度とする成長処理や照明は確認していない |

今後の見た目探索は画像の編集・生成から始め、画像案の修正・比較と採用後にピクセル調整・ゲーム反映を行う。r2修正はこの方針の伝達前に完了していた。

## TECH-3D-01 低解像度3Dと動的影の試作

対象はHEAD `99013702eaf36db72a64d60d284680fb834f13c5` 上の未コミット専用試作。自己の[報告](../evidence/render-study-3d/self/report.md)、[source manifest](../evidence/render-study-3d/self/source-manifest.json)、[GPU結果](../evidence/render-study-3d/self/gpu-results.json)は15 PASS / 0 FAIL / 2 NOT_RUN（Vulkan Forward+, RTX 5070 Ti）。独立の[報告](../evidence/render-study-3d/independent/report.md)・[checks](../evidence/render-study-3d/independent/checks.json)は8 PASS / 0 FAIL / 3 NOT_RUN。独立側はGodotを再実行せず、コード・GPUログ・画像を確認した。19件のmanifest hash一致、既存396件の保全、朝・昼・夕の960/1920画像3組で全画素が正確に2倍一致、影OFFとの差分34,718画素を再確認した。自己側ではカメラの短い5枚連番を保存した。

親は実装と朝・昼・夕の画像を確認し、屋根面の受光修正を含め技術試作を限定受入した。親の見た目所見は、影と地面格子は成立する一方、現材質は参考画像より低解像度3D模型の印象で、これだけでは方式全体の美術可否は決まらないというもの。ユーザーの最終美術判断は未取得。

| 項目 | 結果 | 限界 |
|---|---|---|
| 時間帯別の実DirectionalLight3D、960 GPU描画、1920別viewportの2倍画像 | 自己・独立の証拠範囲でPASS | 実窓のnative表示品質・初期フォーカスはNOT_RUN。保存画像での確認 |
| 影の寄与 | 影OFF画像との画素差34,718を独立再計数 | 見た目の最終評価ではない |
| カメラ連続性 | 短い5枚連番を保存 | 連続ちらつき、全カメラ移動時の画素安定性を保証しない |
| 物理入力、native起動・初期フォーカス | NOT_RUN | OS入力・前面化なし |
| 通常ゲーム統合、成長状態による植生、大量描画性能 | 未実装・未確認 | この試作の対象外。Unity移行も未決定 |

親の判断は低解像度3Dと動的影の専用技術比較としての限定受入であり、通常ゲームの変更・再開、最終美術承認、Unity移行の決定ではない。P2は保留を維持する。次はユーザーが朝・昼・夕の保存画像で画風を評価する。

## TECH-3D-02 硬影と色・階調補正の比較

対象はTECH-3D-01の昼シーンを使った専用撮影。自己報告は[`style/report.md`](../evidence/render-study-3d/style/report.md)、独立read-only確認は[`independent-report.json`](../evidence/render-study-3d/style/independent-report.json)で4 PASS / 0 FAIL / 2 NOT_RUN。独立側はGPUを再実行せず、A/B画像のnearest 3倍一致、共通フレームと補正順序、画像の見え、ログ・ハッシュを確認。今回の6凍結ファイルと既存5ファイルはhash一致し、通常ゲーム・既存シーンの変更なし。

A/Bは同じ640×360のGPU描画から各1920×1080へnearest 3倍。AはHARD影（blur 1、bias 0.1、normal bias 1）。BはAと同じGPUフレームを640×360で補正した後に拡大し、暖色明部・寒色暗部と、輝度20段を20%混合する弱い階調整理を加えた。これは20色制限ではない。初回HARD/blur 0で出た規則的な自己影縞はFAILとして画像・ログを保持し、親指示の影設定限定修正後に消えた。最終A/Bでは地面影の境界が明瞭になったことを静止画で確認した。

親はソースと最終画像を確認し技術比較として限定受入した。ユーザーは640試写に好感を示したが、A/Bの最終美術採用は未決定。native表示・初期フォーカス、物理入力、動的ちらつきはNOT_RUN。候補決定後に短い時間変化を確認する。通常ゲーム統合、960×540基準の変更、Unity移行、P2再開はしていない。

## TECH-3D-03 歩行スプライトと投影影の同期

対象はHEAD `99013702eaf36db72a64d60d284680fb834f13c5` 上の未コミット専用試作。自己の[報告](../evidence/render-study-3d/sprite-shadow/self/report.md)、[checks](../evidence/render-study-3d/sprite-shadow/self/checks.json)、[source manifest](../evidence/render-study-3d/sprite-shadow/self/source-manifest.json)は4 PASS / 0 FAIL。独立の[報告](../evidence/render-study-3d/sprite-shadow/independent/report.md)・[checks](../evidence/render-study-3d/sprite-shadow/independent/checks.json)は5 PASS / 0 FAIL / 3 NOT_RUN。独立側はGodotを再実行せず、コード・GPU証拠・画像・ログ・hashを確認した。manifest SHA-256 `0ecfe1f5bc432353f38f7292ed2b25ca3327c656b856f59fee14b5f0cb97be91`、凍結26件・既存6件のhash一致を確認。

独立scene/起動batでコード製32×48pxの輪郭線なし4コマfixtureを640×360でGPU描画し、代表1920×1080画像はnearest 3倍。表示板と影用板は同じstateからtexture/frame・flip・足元を同期する。表示spriteはunshaded。影板は垂直で太陽の水平方向へ向ける視認性の美術的近似で、身体の厚みは再現しない。HARD影A設定を使い、TECH-3D-02の色補正Bは適用していない。

自己記録ではfixed pose 0/2の影ON/OFF差が284/250画素、両shadow maskの差が114画素。歩行72サンプル、固定4、背面遮蔽1でログ計77件。4コマと反転36サンプルを含み、texture/flip/foot一致を自己記録。独立側はON/OFF PNGを再減算して284/250画素とmask間114画素差を確認し、72歩行ログの同期をコード・記録から確認した（生の左右足元座標は未記録で、独立再測定ではない）。代表画像の640→1920全画素3倍一致。4秒動画はPNG72枚を18fpsで並べた提示用映像で、実時間FPS測定ではなく、MP4圧縮は元PNGと区別する。後方建物による遮蔽は1例を確認。

初回の影板yawは視認性不足で、初回画像とログを`self/initial/`に保持。影板yawのみ改善し、親は修正版画像の輪郭と接地を確認した。親はソース、最終PNG、動画復号4フレームを確認し限定技術比較として受入。独立側も動画復号contact sheetを見たが連続全フレーム再生はしていない。native表示・初期フォーカス、物理入力、キャラ受光、全光方向、実時間FPS、長時間ちらつき・性能は未確認。通常ゲーム、960×540正式基準、Unity移行、P2の状態は変更していない。仮fixtureは完成主人公アートではなく、最終美術採用も未取得。

## TECH-3D-04 太陽角度と周回点光源

対象はHEAD `99013702eaf36db72a64d60d284680fb834f13c5`上の専用lab。自己の[報告](../evidence/render-study-3d/light-controls/self/report.md)は15 PASS / 0 FAIL、独立の[報告](../evidence/render-study-3d/light-controls/independent/report.md)・[checks](../evidence/render-study-3d/light-controls/independent/checks.json)は6 PASS / 0 FAIL / 3 NOT_RUN。独立側はGPUを再実行せずコード・提出画像・JSON・hashを確認。77件の凍結hash一致、既存8件不変と既存sprite影labの許可済み垂直光guard変更1件を確認した。

専用[`run_light_lab.bat`](../launchers/labs/run_light_lab.bat)で方位0〜360°、仰角−90〜90°を0.1°刻みのslider/SpinBoxから操作でき、仰角0°以下では太陽直射をOFFにする。太陽/点光源のON/OFF、周回の再生/停止、停止中の周回角度操作を備える。描画レイヤーはworldが1、太陽用板が2、点光源用板が3（ビット値は1/2/4）。caster maskは太陽3/点5で、共通の歩行状態から各影板を同期する。各光の水平方向へyawを合わせた美術的近似で、キャラ表示は引き続きunshaded。

独立確認では太陽135.7°/25.4°、315.2°/61.2°と仰角±90°を確認。点光源のみ45°/225°/OFFの代表画像も確認し、45対225は123,881画素、225対OFFは45,872画素が異なった。45°で太陽板をOFFにした差は0画素、点光源板OFFでは616画素の差を再確認。UI付きGPU root画像は640×360で、1920提示版は同じ画像をCPU nearest 3倍したもの。world単体の1920画像は別GPU viewport readbackで、640元画像のnearest 3倍と一致する。親はdefault/point45/sun135のUI画像と動画復号contact sheetを確認した。提示動画は48サンプルを12fps・4秒にまとめたもので、実時間FPS測定ではない。

親は限定技術受入。nativeウィンドウ/初期フォーカス、物理入力、全角度・光組合せ、実時間性能はNOT_RUN。全方向の正しさ、キャラ受光、長時間ちらつき、複雑な複数光も未検証。通常ゲーム、正式960×540基準、Unity移行、P2状態は変更していない。

## ART-05 緑化3段階コンセプト画像

対象は[greening-triptych-v1.png](../assets/concepts/art05/greening-triptych-v1.png)（2172×724px）と[生成所見](../evidence/art05/self/report.md)。組込みimage_genで既存の建物試作を参考に生成した一枚の横3面合成画像。親は露出した地面から草房・ツタ・葉群が増える構成と建物の識別要素を目視し、ユーザーは「イメージとしてはこれで十分」と方向確認を完了した。追加の美術調整は停止。独立目視は未実施。別v2生成callは停止指示前に完了したとの報告があるが、その出力はworkspace未保存・未採用。これは画像方向の確認で、厳密画素一致・素材分割・実GPU・ゲーム実装・最終美術承認ではない。Godot継続はユーザー了承、P2は保留。

## TECH-3D-05 共通植生部品の再利用試作

HEAD `99013702eaf36db72a64d60d284680fb834f13c5`上の専用未コミットlab。自己[報告](../evidence/vegetation-lab/self/report.md)14 PASS / 0 FAIL、独立[報告](../evidence/vegetation-lab/independent/report.md)・[checks](../evidence/vegetation-lab/independent/checks.json)6 PASS / 0 FAIL / 3 NOT_RUN。凍結32件一致・既存5件保全。親は主要ソースと0/50/100一覧、C成熟近景を確認し、専用技術試作として限定受入。

共通の草mesh2種・葉群・茎・材質をA低横長箱、B縦長箱、C円筒レンガ＋円錐金属屋根の3棟で共有。建物別の定義データと成長処理を分離し、候補はsetup時に固定、0〜100%で既存配置のtransformだけ更新する。UIはslider/数値と0/50/100 preset、一覧と個別近景。固定昼光、640×360 GPUからnearest3倍表示を用い、植生の受光と影も確認した。UI付き1920はGPU root640のCPU拡大、成熟world1920は別GPU出力。

独立側は5組の3倍画素一致を確認し、開口/通路とC曲面配置をソース・GPU画像で限定評価した。ただし自己除外判定は同一helperのため独立証明ではなく、MultiMesh getterのheadless値がGPU像と矛盾したため数値の実メッシュ位置計測はNOT_RUN（製品FAILではない）。開口x帯を保守的に除外し、surface chartと0.16 offsetで配置する近似で、完全な自動mesh巻付けではない。native表示・物理入力・全光方向・性能・通常ゲーム回帰は未検証。動画と自動成長/照明UIは省略。完成素材や最終美術承認、通常ゲームの成長時間・保存・緑化100%保証への統合ではない。次はユーザーが専用labで共有植生と成長表示を確認する。

## TECH-3D-06 枝ツタ・苔・ひび模様の専用試作

対象は[TECH-3D-06作業票](../tasks/TECH_3D_06.md)と既存vegetation labの限定差分。自己[報告](../evidence/vegetation-branches/self/report.md)は15 PASS / 0 FAIL、独立[報告](../evidence/vegetation-branches/independent/report.md)・[checks](../evidence/vegetation-branches/independent/checks.json)は6 PASS / 0 FAIL / 3 NOT_RUN。凍結74件と既存6件のhash一致を確認。独立側はGPUを再実行せず、raw出力経路・コード・画像・hashを確認した。親は差分、修正版A/C近景、ひび例、両報告を確認し、専用labの技術試作として限定受入した。

共通葉・茎を使う枝ツタはA/B/Cで10/8/94本、親接続gap 0。親到達後に伸びるが、窓や端で停止し自動迂回しない。Bは保守的な窓除外により実枝が+u方向だけ。surface配置定義を要し、任意meshの自動巻付けではない。苔は別面/node/materialでON/OFF・量0〜100を成長率と独立して操作し、ひびは低優先の模様ON/OFFだけで破壊しない。簡略化されていたA屋根を旧形状（欠けスラブ・立上り・鉄筋）へ戻し、旧geometry自体は変更なし。640×360 GPU像をnearest 3倍提示する専用labを継続。

独立のNOT_RUNはGPU再実行、native/物理入力、全表面の照明・性能・通常ゲーム回帰など。経路の接続・実距離はraw座標から独立再計算したが、全頂点の厳密な表面接触計測ではない。TECH-3D-05で判明したheadlessのMultiMesh読取制約を踏まえ、今回はその測定を再試行していない。親の限定受入は最終美術の承認ではない。次はユーザーが[`run_vegetation_lab.bat`](../launchers/labs/run_vegetation_lab.bat)で見た目を確認する。通常ゲーム、P2保留、正式960×540基準、Unity移行方針は変更していない。

## TECH-3D-07 ツタと苔の軽量バリエーション

自己[報告](../evidence/vegetation-variation/self/report.md)は18 PASS / 0 FAIL、独立[報告](../evidence/vegetation-variation/independent/report.md)は4 PASS / 0 FAIL / 3 NOT_RUN。独立hash集計は旧証拠キー参照エラーによりNOT_RUN（製品不良ではない）。親は3ソースを確認し、manifest対象のソース4件と保全10件を別途実hash照合したが、これを独立合格へ加算していない。GPU試作は1回、独立側のGPU再実行なし。

同じ葉・茎meshを維持し、固定seedで直線/蛇行する幹、曲がる枝、開始間隔・位相・高さ・長さを変化。草のRNGは不変。苔は約1×1/2×2相当の大小パッチと形状・中心・位相差を混ぜ、大パッチを細分割し開口でclipする。苔のON/OFFと量、屋根・UI・bat・ひびは維持。曲線も窓や端で止まり、自動迂回はしない。親はA/C近景と苔単独画像で差を確認し、ユーザーの「過度な作り込み不要」の意向に沿って追加調整不要とした。

native/物理入力、全方向、性能、通常ゲーム回帰などはNOT_RUN。親の限定受入は最終美術承認ではない。次はユーザーが同じ[`run_vegetation_lab.bat`](../launchers/labs/run_vegetation_lab.bat)で確認する。通常ゲーム、P2保留、正式960×540基準、Unity方針は変更なし。

## TECH-3D-08 小マップ歩行・地面緑化・太陽方角

専用[`run_greening_map.bat`](../launchers/labs/run_greening_map.bat)の[自己報告](../evidence/greening-map/self/report.md)はlogic 13 PASS / 0 FAIL、GPU初回継続5件＋最終11件から重複を除き16 PASS / 0 unresolved FAIL。初回logicの許容差FAIL、GPUテストの座標注入FAILは証拠を保持して修正済み。独立[報告](../evidence/greening-map/independent/report.md)は6 PASS / 0 FAIL / 3 NOT_RUN。独立headlessは1回7 checks。ソース8件・既存保全103件・証拠39件のhash一致を独立報告に記録。

48×40セル（0.4m/セル、19.2×16m）のA/B二棟・水辺・舗装・初期成熟域で、既存WorldState、Clock/Growth/Spread、PlayState/Landing、Walkerを専用sessionから再利用。WASD/矢印移動、左クリック種・右クリック水の3m直接散布（1押下1回）、種20/水100と既存水辺補給・試作用補給を備える。初期成長×4、×1、成長停止を切り替え、停止中も歩行・散布可。地面表示は実際のstage/growthを読む。太陽方位0〜360°は仰角52°固定で照明表示のみ変更し、成長日照ルールは変更しない。640×360 GPU像をnearest 3倍表示し、既存仮sprite/影同期を再利用。

親は主要コードと初期・成長後・太陽135°・建物裏の画像、独立報告を確認し、この小マップの歩行・緑化・方位操作の限定技術試作として受入。独立GPU再走、native物理入力、広範な回帰・性能・全方向などはNOT_RUN。建物へのツタ/苔成長連動、保存、敵、本番資源循環は範囲外。最終美術やゲーム全体完了ではない。次はユーザーが同じ[`run_greening_map.bat`](../launchers/labs/run_greening_map.bat)で実操作を確認する。通常ゲーム、P2、正式960×540、Unity方針は変更なし。

## TECH-3D-09 地形別の緑化表示と水面反射

対象は既存小マップの表示層。自己[報告](../evidence/terrain-water/self/report.md)はlogic13 PASS / 0 FAIL、GPU初回7 PASS / 1 FAIL後、反射のWorld3D共有を`find_world_3d()`に限定修正し反射のみ再取得。初回証拠は保持し、無影響の terrain/view 4件＋最終反射7件で有効11 PASS / 0未解消FAIL。独立[報告](../evidence/terrain-water/independent/report.md)は5 PASS / 0 FAIL / 3 NOT_RUN。source8・保全108・今回証拠101・旧TECH-3D-08証拠39件がhash一致。親は差分と最終比較・反射ON・太陽135°画像を確認し、限定技術受入した。

舗装id6は固定ひび経路と半scale草1束で、成長に応じひび長を表示。土は3束、sampling/variant RNG順、transformを保持。terrain/target/stage/growth/count/成長速度とsimulationは不変。最終比較画像は2×30セルを同成熟状態に設定した表示比較で、自然成長の達成証拠ではない。100%を視覚的に区別するUIは後で検討する（ユーザー明示）。

反射は320×180の同world平面cameraとnearest texture。地面/基壇と水自身を除外し、太陽方位の照明変更へ追随。通常池は反射線上に構造物が少ないためA棟手前に1.4×0.8mの表示専用水たまりを追加し、歩行可能で論理水域/地形/衝突変更なし。raw14件から状態と緑化counterを独立再集計し、反射前後state一致、実反射画素、nearest3全画素一致を確認。水面はflat planeで任意clip面や波/屈折なし。追加scene renderの性能コストは未測定。物理入力、全P2回帰、全方向/長期安定性などは未検証。通常ゲーム、P2、正式960×540基準は不変。親は限定技術受入したが、最終美術評価はユーザー確認待ち。次はユーザーが[`run_greening_map.bat`](../launchers/labs/run_greening_map.bat)で操作確認する。

## TECH-3D-10 壁際のスプライト欠け修正

自己[報告](../evidence/wall-clip/self/report.md): logic13 PASS / 0 FAIL、GPU18 PASS / 0 FAIL。製品差分は`actor.gd`の表示/影板姿勢と`session.gd`の専用HALF値のみ。修正前A/B右壁では不透明spriteが72/168・70/168画素だけ見え、camera正対板上部がXZ各軸0.436m壁側へ傾くことを画像・rawで確認。足元HALF=0.1mでは横幅/snapに対して不足。

修正後はyaw直立板に縦縮み補正1.1547をかけ、表示は16×24pxのまま、影板と物理高さ1.424m・足元・frame/flipを同期。HALFは2.8論理px（0.28m）。代表壁前とA角の固定位置GPU画像では168/168画素が可視、建物裏は0/168で遮蔽を維持。全4frame×flipの確認は内部姿勢・16×24投影・足元・texture/flip値であり、各姿勢の画素数を個別測定したものではない。初回の角サンプルは壁面を滑っており証明にならなかったため、初回証拠を保持して固定角確認へ置換。親はbefore/after A/B、固定角、反射画像とコードを確認した。

独立[報告](../evidence/wall-clip/independent/report.md)は5 PASS / 0 FAIL / 3 NOT_RUN。凍結7・保全114・証拠63件のhash一致を確認し、A/B壁・固定角・後方遮蔽・姿勢同期・反射・nearestを提出画像/raw/コードから確認。独立Godot再走はしていない。物理/native入力、性能・長時間、全位置/角度、通常ゲーム回帰はNOT_RUN。影板yawは従来の近似、仮spriteは完成アートではない。ユーザーは地形別表示を好意的に評価し、水面反射は問題なさそうと述べたが、最終美術の総合承認ではない。地形・成長・水面反射・通常ゲーム/P2/正式960×540基準は変更していない。次は既存[`run_greening_map.bat`](../launchers/labs/run_greening_map.bat)でユーザー確認。

## TECH-3D-11 局所壁面成長と水面受影

自己[報告](../evidence/wall-growth/self/report.md)はlogic17 PASS / GPU6 PASS。独立[報告](../evidence/wall-growth/independent/report.md)は6 PASS / 0 FAIL / 3 NOT_RUN、source7・保全117・証拠39件のSHA一致を確認。親は実差分、7 source hash、画像を確認し、専用小マップの限定技術試作として受入した。

検証対象はA/B棟の前・右壁に限る。足元は基壇外0.2mへ投影し、半径0.65m内の対象セル平均（未緑化を含む）を入力にする。0.5秒のゲームtickで入力1ならツタ90秒・コケ135秒、部分入力は速度低下、周辺の緑喪失は進捗保持で停止、pause中停止、太陽と無関係。内部緑化分母等は不変で、旧vegetation labの既定生成/成長も保つ。水はunshadedを外し、現太陽1灯の実shadow attenuationのみを反射色へ適用し、暗部を42%で下限処理する。

壁面GPU画像は前方に成熟地面を置いたfixtureであり、自然成長で成熟へ到達した実証ではない。水面上で影により暗化した画素は自己計測57px、独立計測42px。独立は池の内側へ取った別の領域を測っている。独立Godot再走・OS/native物理入力・保存・性能・全マップ/姿勢・通常ゲーム回帰・最終美術評価は未実施。屋根成長、汎用水物理、複数光源対応は今回の範囲外。ユーザーは引き続き既存[`run_greening_map.bat`](../launchers/labs/run_greening_map.bat)で見た目を確認する。

## TECH-3D-12 建物モデル・植生接続と仰角操作

自己[報告](../evidence/building-model/self/report.md)と[証拠一覧](../evidence/building-model/self/evidence-manifest.json)、独立[報告](../evidence/building-model/independent/report.md)を参照。対象はHEAD `99013702eaf36db72a64d60d284680fb834f13c5`上の共有未コミット差分。親は実装差分・代表GPU画像・source16件のhashを確認した。自己logicは初回12 PASS / 1 FAIL（最大被覆上限53.1%）を保持し、葉/苔密度等の限定調整後、影響logic10 PASS / 0 FAIL。既存default signature 3件は初回保存値との一致を確認し、調整後の再走とは数えない。一意logic結果は13 PASS / 未解消FAIL 0。GPUは限定1runで5 PASS / 0 FAIL。独立5 PASS / 0 FAIL / 3 NOT_RUN、source16・保全452・証拠44件のhash一致。親は両報告と差分・主要画像を確認し、専用小マップの限定技術受入とした。

新AはGodotで生成した82meshのGLBを通常importして小マップへ読込。単位m、足元矩形中心原点、主要壁6×4.8×2.8m、全mesh boundsは基壇内。窓枠/桟、開口、扉ひさし等の接続metadataを分離して持つ。植生は共通部品と専用surface/opening/eaves設定から派生し、窓枠沿い・一部窓横断を含む一方、扉/ひさしを避ける。成長は1まで継続し、葉scale0.52・葉4点ごと、苔span0.40で密度を調整。保守的表面上限はA前24.6%/右36.0%、B前24.3%/右28.7%で、葉bbox・全苔sheet・茎径を重複加算し、重なり等を差し引かない上限値である。実画素被覆率ではない。ひびは壁と舗装で独立し、壁線幅0.055m、舗装幅0.035→0.055m。壁の180pxは近景640、舗装104pxは通常640の画像差。仰角UIは既存2行目、5〜85°・既定52°で方位と独立、成長stateは不変。

旧A、session/actor/world/play/data、水面、既存建物定義/生成元は保全。自己integrityは保全452件一致。GLB exportと通常import、および小マップ読込は成功したが、import.logにはeditor safe-save ERROR 1件と既存P2 uid cache warning 6件がある。これをクリーンなimport logとは扱わない。生成されたimport sidecar 66件は記録・保全され、親判断により削除していない。独立はGodot再走・再import・GPU再実行・入力注入を行っていない。native/物理入力、保存、負荷、全角度/夜/多灯、任意モデル自動解析、窓なし面GPU、通常ゲーム回帰、最終美術評価はNOT_RUNまたは範囲外。独立画像差分11〜15%は影等を含む補助値で、被覆率として扱わない。通常ゲーム/P2/正式960×540基準の変更はない。

## TECH-3D-13 納品アセット展示マップ

親は実ソース、6カテゴリの最終GPU画像、硬影修正後の建物/樹木画像、独立報告を確認し、専用展示の限定範囲を受け入れた。自己検証は62 PASS / 0 FAIL / 4 NOT_RUN、独立検証は6 PASS / 0 FAIL / 4 NOT_RUN。6カテゴリ各4件、飛び飛びIDの計24件を元縮尺で配置し、地形は単純な床と受け面に限定。独立者はGodot/GPUを再実行せず、提出画像・実ソース・独立解析で確認した。

固定66ソースのhash、納品元からの57コピー（GLB24・metadata24・PNG9）、元GLB24件のbaseline、既存7件は一致した。証拠は[自己報告](../evidence/asset-showcase/self/report.md)と[独立報告](../evidence/asset-showcase/independent/report.md)。import/GPUログにはuser dataやshader cacheを書き込めないERRORが残るため、無エラー起動とは扱わない。物理入力、全角度/性能、納品536件すべて、反射・成長・衝突・主人公を含む通常ゲーム統合、ユーザーの最終美術評価はNOT_RUN。通常ゲーム統合と正式960×540基準の変更はない。

## TECH-3D-14 旧ツタと納品VINの比較

対象はHEAD `99013702eaf36db72a64d60d284680fb834f13c5`上の共有未コミット差分。[自己報告](../evidence/vine-compare/self/report.md)は40 PASS / 0 FAIL / 4 NOT_RUN。[独立報告](../evidence/vine-compare/independent/report.md)は7 PASS / 0 FAIL / 4 NOT_RUN。全ID読込smokeのraw記録は63件PASS / 0 FAILだが、VIN-007行は006の三角形統計だったため有効行から除外し、smokeとして有効なのは62件。VIN-007は自己の別個の初期読込・代表検査（800三角形）で補完され、独立者がその根拠を照合した。親は旧ツタ参照、選択IDの最終GPU画像、低い太陽の画像と独立報告を確認し、比較ツールの限定範囲を受け入れた。

左は既存`plant_parts.gd`と`growth_patch.gd`のmesh・材質・頂点色・枝成長を参照し、小マップ相当疎密を初期値として旧lab密度にも切替可能。右は指定外部フォルダからVIN metadata/GLBをruntime読込し、一覧・前後・ID入力・再読込を提供する。0〜100%の同期slider/presetがあり、0→100%まで全体で約16秒。再生ボタンは現在値から進行し、100%から再生した場合のみ0%に戻る。停止・先頭戻しがあり、ID切替後も成長率を維持する。100%では納品元mesh/材質へ戻る。中間はmetadataとmesh経路距離に基づき元三角形を順次表示する推定成長で、正式アニメ・経過時間・被覆率・通常ゲームの緑化連動を意味しない。元scaleを維持し、比較配置の中心だけを移動する。640×360 nearest整数倍表示、共通視野、太陽方位/仰角、簡易受け面の切替がある。初期camera.sizeは6.8、「18.5m」ボタンは小マップ相当の広視野を選択する。受け面は全ての複合形状を再現するものではない。

独立者はソース7件、既存baseline7件、元GLB/metadata126件のhash一致と元フォルダの`.import`不在を確認。代表5件は元GLBから解析した三角形数と100%表示が一致し、GPU7画像は640×360からnearest3倍の画素一致を確認した。初回`smoke.json`のVIN-007行は直前のVIN-006統計468を記録していたため、その統計を根拠から除外。自己の初期読込・代表検査におけるVIN-007（800三角形）と画像を独立者が照合し、全63 IDの確認を補完した。将来用selftestの該当1行を`select_id(number)`呼出しへ修正し、再凍結した。独立者は修正後の7ソース全hash一致を追加確認した。修正後の自己試験再走はNOT_RUN。ゲーム実装とGPU画像は不変。

物理入力、通常ゲーム緑化/保存への接続、全角度・性能、全IDの中間形状、ユーザーの最終美術評価はNOT_RUN。独立Godot/GPU再実行も行っていない。通常ゲームのコードや元納品データは変更していない。専用の[操作ガイド](VINE_COMPARE.md)と[自己報告](../evidence/vine-compare/self/report.md)・[独立報告](../evidence/vine-compare/independent/report.md)を参照。

## TECH-3D-15 納品モデルの小街区・歩行・昼夜試作

対象はHEAD `99013702eaf36db72a64d60d284680fb834f13c5`上の共有未コミット差分。[自己報告](../evidence/town-lab/self/report.md)では初回34 PASS / 2 FAILを履歴として保持し、修正影響を再確認した有効結果は38 PASS / 0未解消FAIL / 4 NOT_RUN。40件の観測から、初回の夜水受影・反射2件は後続結果に置換して重複加算しない。独立[報告](../evidence/town-lab/independent/report.md)は7 PASS / 0 FAIL / 4 NOT_RUN。親は実装コード、最終P1を含む朝昼夕夜・壁際・水面画像、独立報告を確認し、専用labの範囲を限定受入した。

約50×50m街区にBLD-007/019/038/046/079/091/123、PRP-001/005/012/017/034/041/075、TRE-001を元scaleで配置し、十字道路・脇道・空き地を設ける。建物7棟は実AABB接地Y=0、独立再集計で大きなAABB重複なし。旧人間fixtureの4frameを使い、WASD/矢印で画面基準歩行、Fで全景/追従、`+`/`−` UIでズーム、Rで開始地点へ戻る。仮想投影・衝突は屋外回遊用で、建物全内部・階段・全隅は保証しない。

640×360 nearest整数倍、正投影30°/45°、硬い影。時刻slider0〜24、朝7/昼12/夕17/夜22 preset、0.25/1/4倍の再生は初期約120秒周期。同時刻の状態を決定的に計算し、画面北を基準に6時頃東→正午南（最大仰角55°）→18時頃西へ太陽が進む。夜は太陽を無効にし、近似月光と暖色街灯4灯へ移る。水たまり4箇所は共有320×180反射を使い、昼の太陽・夜の局所灯による受影をMAX上限付きで近似する。水面は歩行可能。

初回の入力注入はfocus-out前に行われ最初のキーが消える問題、交差点板に覆われた水面受影0px、夜の点灯器具による自己影を検出して修正。影響箇所だけ再取得し、最終の昼受影差61px・夜受影差3625px・反射ON/OFF差1557pxを独立確認した。朝昼夕夜の最終全景と水面・壁際を画像で確認。fixed 106 source、既存baseline167件、納品元/コピー42件のhash一致。実import/runtime読込は成功したが、ログにはsandboxのuser設定/log/shader-cache書込不可ERRORが残るため、無エラー起動とは扱わない。

独立Godot/import/GPU再実行、物理OS入力、全角度/性能、通常ゲームの成長・保存・戦闘統合、季節/緯度を含む天文学的精度、ユーザーの最終美術評価はNOT_RUN。夜の水受影と主街灯の人影は近似で、全建物内外の衝突を保証しない。証拠は[自己報告](../evidence/town-lab/self/report.md)、[独立報告](../evidence/town-lab/independent/report.md)、[操作ガイド](TOWN_LAB.md)を参照。

## 3DクォータービューPoC（POC-01〜09）

- 体制（実モデル）: 実装・独立検証はClaude Sonnet 5.5（claude-sonnet-5-5、両者の実応答で報告）、親はClaude Opus、設計補助（green-designer）は未使用。文書はgreen-documenter（Haiku指定。本更新の実応答で claude-haiku-5-5）。独立検証は実装と別の呼出しで行った。承認済み事実は[approved_facts.md](../evidence/poc/09/approved_facts.md)。
- 対象版: HEAD `9901370`＋未コミット差分。PoC一式（`scripts/poc/`、`data/poc/`、`scenes/poc.tscn`、`tests/poc/`、`launchers/run_poc.bat`、`evidence/poc/`）は未コミット・未追跡で、コミットはしていない。
- 環境: Godot 4.7.2、Vulkan Forward+、RTX 5070 Ti（性能測定はこの1台のみ）。実OS入力・前面化・カーソル移動は使わず、入力はGodot内注入、GPU撮影は `root.unfocusable=true`。

### 各票の結果

- POC-01 3D共通基盤・座標と解像度切替: 自己logic 40 PASS / GPU 14 PASS / 0 FAIL。独立は切替・座標・定数・単一時計・描画の5条件 PASS / 0 FAIL。証拠 [evidence/poc/01/](../evidence/poc/01/)（独立は `independent/`）。
- POC-02 3Dアセット・配置・衝突: 自己logic 45 / POC-01回帰 40 / GPU 7 PASS、0 FAIL。独立は5条件 PASS / 0 FAIL、POC-01回帰 PASS。証拠 [evidence/poc/02/](../evidence/poc/02/)。
- POC-03 種まき・給水・資源循環: 自己logic 69 / POC-01回帰 40 / POC-02回帰 45 / GPU 8 PASS、旧P1 checks 6本の失敗0。独立は6条件 PASS / 0 FAIL（初回FAILは検証側のオラクル不備で、検証側修正により解消、実装変更なし）。証拠 [evidence/poc/03/](../evidence/poc/03/)。
- POC-04 敵・巣・地域安定・100％保証: 自己logic 48 / GPU 7 PASS、回帰 base 40 / assets 45 / play 69、旧p2_01〜05の失敗0。独立は7条件 PASS / 0 FAIL（49 checks）。100％は上限237.0s、安定後192.65sで1170/1170。栽培植物60セル占有でも安定後178.1sで到達。証拠 [evidence/poc/04/](../evidence/poc/04/)。
- POC-05 緑化表示・建物植生・昼夜と水面: 自己 environment logic 81 / combat 48 / base 40 / assets 45 / play 69 / GPU 21 PASS、0 FAIL。独立は単一時計・太陽方位・成長要因・緑化率と表示の分離・壁面植生・回帰 PASS。水面反射は鏡像が弱く、ON/OFFの差はあるが判定は不能（表示上の制約として受入）。証拠 [evidence/poc/05/](../evidence/poc/05/)。
- POC-06 プレイヤー遮蔽時の半透明化: 自己 occlusion logic 35→修正後37 / GPU 22 PASS、回帰 base 40 / assets 45 / play 69 / combat 48 / environment 81 PASS。独立は初回に潜在FAIL 1件（build後に別フレームでbindすると解放済み複製を参照）→差戻し→修正後、影響範囲のテスト `poc06_logic.gd` を実装担当と親がそれぞれ1回再実行し37 PASS / 0 FAIL。証拠 [evidence/poc/06/](../evidence/poc/06/)。
- POC-07 遊べる小街区マップ: 自己 map logic 49 / GPU 5 PASS、回帰 base 40 / assets 45 / play 69 / combat 48 / environment 81 / occlusion 37、0 FAIL。100％は上限869.0s、安定後796.5s。独立は規模構成・衝突（AABBずれ最大0.59m）・固定再生成・100％（無入力712sで9464/9464、再侵攻なし）・描画・回帰 PASS / 0 FAIL。独立担当はAPI利用上限で一度停止し、ユーザーの「再開」指示後に同じ担当を再開した。証拠 [evidence/poc/07/](../evidence/poc/07/)。
- POC-08 開始・保存復元・操作案内: 自己 save logic 58→修正後73（POC-09の差戻し後は76 PASS）/ ui_logic 28 / GPU 7 PASS、回帰7本 PASS。独立は往復・重複なし・時間・UI・入口・回帰 PASS。値改ざんの受理による部分FAIL（例: `far.job_zone=999` でSCRIPT ERROR、plant_id 250・moisture 255・敵HP 99999の受理）→差戻し→修正後、`poc08_core.gd` 42 PASS / 0 FAIL。証拠 [evidence/poc/08/](../evidence/poc/08/)。
- POC-09 統合確認・引渡し（親が技術受入）:
  - 統合（実装担当、通しプレイ）: 安定377.9s、以後無入力で安定後582.3s（上限869.0s）に9464/9464、完了後120s維持。主要回帰20項目 PASS（修正後）、代表GPU画面10 PASS。
  - 回帰一式9本（base 40 / assets 45 / play 69 / combat 48 / environment 81 / occlusion 37 / map 49 / save 76相当 / ui_logic 28）0 FAIL。
  - 独立（自前の歩行・射撃）: 安定560.7s、安定後の無入力794.0sで9464/9464（上限869.0sの91.4％）、自前再計算の対象集合と一致、孤立島16セル緑化、再侵攻0。種の増加は拾得・報酬のみ。保存再開（遠距離拡散の実行中、戦闘不能中×2）が一致、終了中の進行なし、表示設定と内部緑化率の分離、99％を100％と表示しないことを確認、起動経路の確認、0 FAIL。
  - 証拠: [evidence/poc/09/](../evidence/poc/09/)（`A_playthrough.json`・`A_playthrough.log`、`B_regress.json`・`B_regress.log`・`regression/`、`C_gpu.log`・`C_gpu_stats.txt`、`D_perf.json`・`D_perf.log`、`E_startup_headless.log`、代表画像、`independent/`）。

### 差戻し3件（いずれも修正後に影響範囲を再実行して合格）

1. POC-06: 解放済み複製参照（build後に別フレームでbind）。
2. POC-08: 値改ざんセーブの受理（範囲外値は拒否に統一、クランプしない）。
3. POC-09で見つかった不具合: 戦闘不能中の保存→読込で、安全地帯へ戻らず保存位置へ戻る（`poc_save.gd`。修正後 `poc_save.gd` 363505044e13、`save/logic.gd` 76 PASS、統合 regress 20 PASS、`poc08_core` 42 PASS）。POC-08の記録に追記。

### 性能（戦闘中、敵上限付近、10秒）

vsyncありの640/960とも平均約144fps（6.95ms）、最悪7.51ms / 13.19ms。vsyncなしは約458fps。16.7msを超えるフレームは0。画面内の敵は1匹程度で密度は限定的。60fps目標はこの1台で達成。低スペック機・他GPUは未確認。

### 100％の上限

上限は `far.completion_bound_seconds()`（FarSeedSim設定から事前算出）。上限を延長して合格にしたことはない。

### NOT_RUN（未確認）

物理キーボード・マウス（OS経由の入力）、run_poc.bat実起動の窓での実描画、実1920×1080窓・非整数窓（実際の窓リサイズイベント経路を含む）、実速度での長時間プレイ、低スペック機・他GPU、大規模負荷、Windows書き出し。楽しさ・テンポ・美術の評価はユーザー判断で、AIは代行していない。

### 証拠の注記

- 各票の `report.md` は `evidence/poc/01〜08/` にあり、`evidence/poc/09/` には `report.md` がない。POC-09の数値は承認済み事実と上記のログに基づく。
- 独立検証の `report.md` は `evidence/poc/01/independent/` にのみあり、POC-02〜09の独立結果はそれぞれの `independent/` 配下のログに基づく。
- 既知の限界と残課題は[残課題](BACKLOG.md)、操作と保存は[PoC操作書](POC_GUIDE.md)を参照。

## 作り込み段階（POL-01、HLP-01〜03、WTH-01〜03）

- 体制: 実装・独立検証はSonnet 5.5（承認済み事実の記載）、親はClaude Opus（claude-20261018-poc-opus）、文書はgreen-documenter（本更新の実応答で claude-haiku-5-5）。独立検証は実装と別の呼出しで行いました。
- 対象版: 基準ブランチ `poc/3d-quarter-view`（WTH-03の記録上の基準 `305a0d8`）＋各票のコミット。作り込み段階のコミットはローカルのみでpush未実施（承認済み事実）。記録上の識別子: 統合の不具合修正 `35820e4fb950`、保存再開の修正 `44d01d0b3fb6`・`55db403e91e9`。
- 環境: Godot 4.7.2、Vulkan Forward+、RTX 5070 Ti（性能はこの1台の1回測定）。実OS入力・前面化・カーソル移動は使わず、入力はGodot内注入、GPU撮影は `root.unfocusable=true`。

### 各票の結果

- POL-01 磨き込み（移動・建物・表示・テンポ）: 自己 polish logic 15 / tempo 3 / GPU 3 PASS、回帰一式 0 FAIL。旧速度前提の歩行ヘルパーは、合否条件を緩めず最後の一歩だけ縮める修正を承認（map `b02f07851757`、combat `d7feb52c7772`、各0 FAIL）。テンポは安定後100％が793s→345s、上限は869s→389s。独立: 全方向4.800m/s、薄壁456通りですり抜け0、建物4棟の回転（負scaleなし）、安定後343.0sで9463/9463（上限389.0s）、表示の分離・描画・回帰 0 FAIL。証拠 [evidence/poc-polish/01/independent/](../evidence/poc-polish/01/independent/)。所見: 夜の草地で足元円盤が断片的。
- HLP-01 おたすけたねと設置・移設・消滅: 自己 helpers logic 85 / ui 10 / GPU 10 PASS、回帰 0 FAIL。独立: 入手・設置と拒否・移設・消滅（実イノシシで前線の植物HP8→0、23.8sで消滅、安定地域は無傷）、不変条件（4体設置で安定後330.0s、上限389.0s内に9463/9463）、入力・描画・回帰 PASS / 0 FAIL。証拠 [evidence/helper/01/](../evidence/helper/01/)（独立は `independent/`）。旧独立テスト `poc08_core.gd` の「version_2拒否」ケースは版更新で意味が変わるため、書換えず記録。NOT_RUN: 独立側の独自GPU撮影、実プレイで前線に成熟地を作る経路、落下率の統計的検定。
- HLP-02 ガトリンガー・スプリンクラー・アーミー: 自己 work 71 / GPU 10 PASS、回帰 0 FAIL、3種設置で安定後315.0s（上限389.0s）。途中でAPI利用上限により担当が停止し、ユーザーの再開指示で同じ担当を再開。独立: ガトリンガー（在庫・発射・播種の収支一致、重複・無効対象0、在庫ゼロで停止）、スプリンクラー（水辺600sで無補給200回、水辺外は枯渇後に接近補給）、アーミー（実イノシシ47体撃破、半径外0、帰還、壁越し被弾0）、共通（保存往復、改ざん16種拒否、pause、3種設置で安定後310.0sに100％）、描画、回帰 0 FAIL。前線速度は参考値（新規緑化セル数の比で自然拡張の約1.95倍、窓により1.76〜1.95。独立の8×8島40sでは1.53倍）。証拠 [evidence/helper/02/](../evidence/helper/02/)、独立は `independent/`、修正は `fix/`。
- HLP-03 おたすけ植物の統合確認（前線）: 不具合修正として、地形適用後にSpreadSimを再同期（`4868334755a1`）し、壁押込みを拒否（独立: 579回で0）。統合ボットは合否条件を緩めずに行動だけ改善（regress 20 / play_through 15: 安定199.0s、安定後281.0sで100％、上限389.0s / helpers_front 19 PASS）。独立: 新規開始180sで806セル（起点同期）、自前の手順で安定339.2s、安定後269.0sで9463/9463（上限389.0s）、ダウン0、回帰 0 FAIL。10分前線（参考）: 補給往復は種の供給源1回・水辺外スプリンクラー1回、ガトリンガーの前線効果はイノシシ8頭の食害で約2200セル頭打ち。証拠 [evidence/helper/03/](../evidence/helper/03/)（独立は `independent/`）。
- WTH-01 天候（晴・曇・雨）と成長・表示: 自己 weather logic 48 / GPU 24 PASS、回帰 0 FAIL、天候ありで安定後293〜303.5s（上限389.0s）。独立: 時計由来の決定性（858点、刻み違いで一致、pause不変）、日光係数≥1.0、雨で成長促進、100％（雨の最中から安定後293.0s、曇りの夜から303.0s、上限389.0s）、保存（天候列一致、改ざん14種拒否）、表示（画面テクスチャ不使用・焼き込みなし、雨夜で主人公と敵が読める）、デバッグキーは既定無効、回帰 0 FAIL。親判断: 夜の敵の足元マーカーを追加。実装中に残った0バイトの `.git/index.lock` は、Gitプロセスなし・担当票なしを確認して親が削除（上書きされた証拠を戻した）。証拠 [evidence/weather/01/](../evidence/weather/01/)（独立は `independent/`）。NOT_RUN: 960の天候画像の独立撮影。
- WTH-02 見晴らし台と最低限の音: 自己 view logic 43 / GPU 10 PASS。独立: 展望（到達・近接・世界停止と復帰・入力と保存の拒否・パネル値一致・解像度）、音（外部音声ファイルなし、操作音の要求、失敗時・pause・展望中は無音、雨音、小鳥、Mで全無音）、分離（緑化対象9463不変、安定後300.0sで100％、上限389.0s）、描画、回帰13本 0 FAIL。自己の最後の見た目修正後の一部回帰は未再実行で、WTH-03の回帰一式で再確認。証拠 [evidence/weather/02/](../evidence/weather/02/)（独立は `independent/`）。
- WTH-03 統合確認と引渡し: 下記「最終通し」を参照。

### 差戻し・修正

- POL-01: 速度変更で失敗した map/combat テストの歩行ヘルパーを、最後の一歩だけ縮める修正（合否条件は不変）。
- HLP-03: SpreadSimの起点同期の不具合修正（承認済み）。統合ボットは行動のみ改善。
- WTH-03（独立検証）: ガトリンガー稼働中の保存再開で、poc_helpers.gd の `to_dict` がtimer等を小数4桁に丸め、読込後の次弾が1歩遅れて以後の狙いが分岐（決定性の崩れ）→HLP-02担当へ差戻し→`poc_helpers.gd`（`44d01d0b3fb6`）と`poc_save.gd`（`55db403e91e9`）で状態値を丸めず保存、timer下限を-WORK_STEPに。修正後、親と実装担当が `wth03_save.gd` を各1回再実行し22 PASS / 0 FAIL（親ログ [save_recheck_parent.log](../evidence/weather/03/independent/save_recheck_parent.log)、修正時ログ [evidence/helper/02/fix/](../evidence/helper/02/fix/)）。
- WTH-03（統合）: 展望中に左下の操作案内が残る不具合を `poc_main.gd` の2行で修正（`35820e4fb950`）。
- 運用注記: テストが上書きした `evidence/helper/03` の3件（WTH-03）と `evidence/helper/03` の2件（WTH-02）は親が戻した。

### 最終通し（WTH-03、統合担当・独立担当）

- 統合（実装担当、通しプレイ、ボット、早送り）: 15 PASS。手まき→栽培→おたすけたね入手→3種設置と1回移設→巣3破壊→安定228.1s→安定後262.5sで9463/9463（上限389.0s）。展望1回、音8種の要求、天候と昼夜は自然進行。
- 回帰一式18本: 0 FAIL。代表GPU画面: 7 PASS。
- 独立（別呼出し、自前の手順）: 安定339.7s→安定後258.5sで9463/9463（上限389.0s）。再侵攻なし、展望の停止と案内消去、終了中の進行なし、描画（画像5枚を目視）、回帰 PASS。保存再開の組合せは差戻し・修正後、22 PASS / 0 FAIL。
- 担当の停止: 作り込み中にAPI利用上限で担当が2回停止（HLP-02の実装、WTH-03の独立検証）。いずれもユーザーの再開指示で同じ担当を再開。
- 性能（戦闘・おたすけ植物・雨、1回測定）: vsyncありで平均約144fps、640の最悪15.05ms、960の最悪17.24msは1フレーム（統合担当の記録どおり、1回の測定）。低スペック機・他GPUは未確認。
- 上限: 100％の上限はいずれも `far.completion_bound_seconds()`（389.0s）。延長はしていない。
- 証拠: [evidence/weather/03/](../evidence/weather/03/)（`A_full_flow.json`・`A_full_flow.log`、`logs/E_summary.txt`、`D_perf.json`、`C_gpu_stats.txt`、代表画像、`independent/`）。承認済み事実は [approved_facts.md](../evidence/weather/03/approved_facts.md)。

### NOT_RUN（未確認）

物理キーボード・マウス（OS経由の入力）、実音の聴取、run_poc.batの実窓での描画、他機種の性能、楽しさ・テンポ・美術の評価（ユーザー判断。AIは代行していない）。

## SPR-01 通常歩行・跳ね歩きのゲーム内比較（2026-10-20）

- 対象: 共有ツリーHEAD `151a53f20255489ef08481e2a353258cd8ac559c` 上の凍結済みPoC差分。ユーザー依頼に沿って通常歩行素材を追加し、既存跳ね歩きとの比較を可能にした。基準となる静止画v2と16×24px素材は保持。
- 素材独立確認: 5 PASS / 0 FAIL / 2 NOT_RUN（[記録](../evidence/spr01/independent/walk-compare-assets.md)）。確認対象はPNG格子・二値alpha・パレット・足の交互動作等の素材範囲で、連続再生のゲーム内見え方を含まない。
- 親確認済みの実装担当自己確認: 操作16 PASS / 0 FAIL、配置1 PASS、影修正後8 PASS / 0 FAIL。生データは[操作結果](../evidence/spr01/walk-compare/self/results.json)、[配置ログ](../evidence/spr01/walk-compare/self/layout.log)、[影結果](../evidence/spr01/walk-compare/self/shadow_results.json)、[対象hash](../evidence/spr01/walk-compare/self/target-hashes.json)。GPU比較GIF・代表画像は[自己証拠フォルダ](../evidence/spr01/walk-compare/self/)に保存。
- GPU確認環境はRTX 5070 Ti / Vulkan。sandboxでは空の既存user:// cache/settingsに関する警告が出た。保存往復は隔離した証拠用領域で確認し、通常ユーザーのsaveは変更していない。
- 初回GPU確認で自己影が顔を隠す問題を修正し、表示板専用レイヤーと同期太陽光を使って自己受影を除去。地面への投影と建物からの受影を維持。半透明建物の影コピーと反射表示maskも調整し、影mapを1枚追加した。影修正後の自己確認は8 PASS / 0 FAIL。性能負荷は未測定。
- 独立GPU検証者の正式集計は11 PASS / 0 FAIL / 5 NOT_RUN（[独立報告](../evidence/spr01/independent/walk-compare-review.md)）。個別GPU主試験は20条件中19 PASS / 1 FAIL（[初回結果](../evidence/spr01/independent/walk-compare-gpu/results.json)）。FAILは夜撮影用にclock.elapsedのみを変更してtickと時間が不整合となった試験fixtureを、既存validatorが拒否したもの。製品側の不具合ではなく、初回結果は保持した。正常な時計状態の旧resolution_index=1セーブ往復だけを1回再確認し、保存成功・読込成功・state_equal=true・640×360復元でPASS（[再確認結果](../evidence/spr01/independent/walk-compare-gpu/save_followup.json)、[stdout](../evidence/spr01/independent/walk-compare-save.stdout.log)）。全体再走やゲーム修正はしていない。初回20条件と再確認を加算して集計を増やさず、正式集計11/0/5を用いる。
- 独立担当はGPU画像を目視確認し、実装8ファイル/import素材/自己試験の18対象hashと通常歩行素材hashの開始前後一致を確認。証拠画像は[独立GPU結果](../evidence/spr01/independent/walk-compare-gpu/)にある。初回の不正時計によるvalidator拒否は[独立ログ](../evidence/spr01/independent/walk-compare-save.stdout.log)にも記録。
- 未確認: 実時間の連続再生の視覚・操作感、通常歩行と跳ね歩きのユーザー選択、物理OS入力、通常ユーザーのuser://保存経路、物理窓の整数倍画素、全照明・実水面反射・影map追加の性能、長時間回帰・書き出し後動作、他GPU・低性能機。楽しさと最終美術はユーザー判断。

### 通常歩行v2の更新（2026-10-20）

- ユーザーは体や手の固定で歩行感が弱いと述べ、跳ねない範囲で動きを増やし、1px上下も許容すると依頼。親の試作初期値は胴・顔の下方向変位 `[0,+1,0,+1]px`、皮状の手の胴に対する左右交互±1px、足は接地、葉の相対揺れを維持するもの。
- 新素材[`walk-normal-v2`](../assets/concepts/spr01/walk-normal-v2/preview.gif)と、runtime素材manifestの出典差替えを記録。24×36px・4方向4コマ・8fps・anchor(12,34)、二値alpha、目1×2px、非反転。静止画v2、旧通常v1、跳ね歩き、16×24px案は保全。ゲームコード、速度、当たり判定、照明、保存、F6操作は無変更。
- 親がcontact sheetとGPUの通常歩行画像を目視。自己GPU確認7 PASS / 0 FAIL（[結果](../evidence/spr01/walk-normal-v2/self/results.json)）: 通常時640×360、import後画素一致、4コマ同一接地、停止時採用idle、F6で既存hopへ切替、hop選択保持、通常へ復帰。NOT_RUN: 物理OS入力、連続再生の手触り/美術選択、保存・全天候・広範囲の影回帰。
- 通常歩行v2の独立素材/提示画像確認は7 PASS / 0 FAIL / 3 NOT_RUN（[報告](../evidence/spr01/walk-normal-v2/independent/review.md)）。独立Pythonで224個別画素照合PASS、凍結72件hash一致。contact sheetと制作者取得GPU画像6枚を目視し、独立GPU再実行はなし。自己GPU7 PASSは別の確認範囲で、独立集計へ加算していない。
- NOT_RUN（当該試験時点）: 連続再生の見た目・操作感、物理入力、保存・全天候・広範囲の影回帰。前節のv1独立11 PASS / 0 FAIL / 5 NOT_RUNはv2の検証結果に含めない。

### ユーザー採用（2026-10-20）

ユーザーは通常歩行v2を「歩きの方がよかったです。こちらを採用しましょう」と選択しました。これは素材・提示画像を見たユーザーのデザイン判断であり、新たな試験結果ではありません。前節の試験時点で「最終歩行選択 NOT_RUN」とした記録は当時の状態を指します。通常歩行v2が現在の採用案です。採用仕上げでF6/右上切替を除去した限定確認は、次節に記録します。

### 採用歩行の固定と比較操作除去（2026-10-20）

- 採用済み通常歩行v2へ通常mode 0を固定し、F6、右上比較ボタン、比較案内を除去。
- 実装担当Solの自己GPU確認4 PASS / 0 FAIL（[結果](../evidence/spr01/walk-adopt/self/results.json)）。確認対象は通常歩行、F6無作用、比較ボタン/案内の不在、停止時の採用idle。
- 別Solの独立差分/提供GPU画像レビュー4 PASS / 0 FAIL / 2 NOT_RUN（[報告](../evidence/spr01/walk-adopt/independent/review.md)）。対象差分/画像hashを確認し、walking/idleの提供GPU画像を目視。独立GPU再実行なし。通常PNGは採用v2原本と一致し、actor/PNG等の保全11 hashと変更対象hashが一致。
- NOT_RUN: 独立GPU再実行、物理OS入力、広い回帰。これはユーザーの採用決定を検証へ置き換えるものではなく、採用済みの素材・表示を比較専用UIなしで維持する変更の限定確認。

## SPR-01 正面の種・水発射アニメ試作（2026-10-20）

- 対象: 共有ツリーHEAD `151a53f20255489ef08481e2a353258cd8ac559c` と既存差分を基準にした、`assets/concepts/spr01/fire-front-v1/` の静的・時刻指定比較試作。ゲーム/runtimeには未組込み。
- 制作担当の記録: [制作記録](../assets/concepts/spr01/fire-front-v1/production-note.md)、[素材自己検査](../evidence/spr01/fire-front-v1/self/self-check.json)、[HTML検査](../evidence/spr01/fire-front-v1/self/html-check.json)。原寸・寸法・alpha/palette・顔・足・idle保持・イベント時刻・レイヤー分離・GIF復号・HTML埋込一致等の自己確認を記録し、全コマ一覧を1回目視。親もcontact sheetを確認し、重大な崩れは見ていない。
- 表示時間: manifest上の発射時刻は種33ms、水50ms。GIFは20msサンプルのため40/60msに近似される。HTMLの時間区分は正確なmsだが、物理画面上の反映はブラウザー更新周期に依存する。
- NOT_RUN: ブラウザー/GIF連続再生の目視、物理表示時刻の精度、ゲーム統合、ゲーム内照明、操作感、最終美術評価。今回了承された試作の動き・コマ長・発射時刻は制作条件であり、ゲームには未実装。飛翔表現の弾道・速度・色細部は比較用で未決定。
- 独立確認は7 PASS / 0 FAIL / 3 NOT_RUN（[報告](../evidence/spr01/fire-front-v1/independent/review.md)、[結果JSON](../evidence/spr01/fire-front-v1/independent/results.json)）。独立に241個別照合を実施し、元137件と凍結成果59件のhash一致を確認。全コマ目視で種/水の静止コマ、時間、分離、GIF復号に重大な問題は見つからず、親は比較提示の限定技術受入。NOT_RUN: ブラウザー連続再生、実速の印象、ゲーム統合。ゲーム内実装やユーザーによる最終美術採用は示さない。

## SPR-01 発射v3のゲーム仮組込み（2026-10-20、4方向版へ更新前）

- 対象: 共有HEAD `151a53f20255489ef08481e2a353258cd8ac559c`＋既存差分のPoC。`scripts/poc/poc_main.gd`、`poc_actor.gd`、`poc_session.gd`、`play/poc_play_view.gd`、新規表示制御とruntime素材copyを変更。起動入口は通常PoCの[run_poc.bat](../launchers/run_poc.bat)。旧ゲーム入口/解像度640×360/移動/速度/当たり判定/保存形式は維持。
- 表示/動作: 通常静止/歩行は既採用4方向、発射中のみ正面v3を全照準方向へ共用。入力直後にpose 0を表示。種は400msで66ms時点、水は800msで400ms時点に弾を生成し、通常種/水の資源減算と発射音を一度だけ実行。栽培種は既存費用ルールを保ち、発射時に種を予約して利用可能数から差し引き、弾の着地成功時に袋seedsを消費。形成FX/飛翔画像を分離し、頭の葉間から表示。実際のaimはマウス地面クリックの方向、姿だけ正面共通。移動は継続可。
- 入力/セッション: aim点と選択中の種を入力時に固定、弾の発射originは発射時点のplayer位置。溜め中の追加入力は拒否し、タイマーを再開始しない。発射後の戻りは次入力で中断可。資源不足/弾上限/無効地点では開始せず、発射時も再確認。失敗時は消費/弾なしで通常表示へ戻る。pause/menu/viewpointでtimer停止、load/newgame/death時に未発射を破棄。pendingは保存せず、既存`session.fire`即時APIは維持。栽培種の発射時予約/着地時消費も従来ルールを保持。
- 自己確認: logic16 PASS（[結果](../evidence/spr01/fire-integration/self/logic-results.json)）、実GPU1回11 PASS（[結果](../evidence/spr01/fire-integration/self/gpu-results.json)）。実装メモ（[implementation-note.md](../evidence/spr01/fire-integration/self/implementation-note.md)）、凍結68ファイルの[対象hash](../evidence/spr01/fire-integration/self/target-hashes.json)、保全128件hash一致（[preserved-check.json](../evidence/spr01/fire-integration/self/preserved-check.json)）。親はコード差分と水の実画面を確認し、重大な崩れなし。GPUで水の400ms発射時、projectile native 8×8の初期投影とsocketが (320,180) で一致、音1回、種の粒FX、移動継続/4方向共用/歩行復帰を確認。menu/viewpoint停止・load/newgame/death中断を含む。
- 画面証拠: [GPU contact sheet](../evidence/spr01/fire-integration/self/fire-game-contact6x.png)と[位相比較GIF](../evidence/spr01/fire-integration/self/fire-game-crop6x.gif)はGPUの各時点撮影画像をnearest6倍で比較したもの。実マウス操作の連続録画ではない。時刻別画像とログは同じself evidenceフォルダ内。
- 独立確認: [正式レビュー](../evidence/spr01/fire-integration/independent/review.md)のR1は23 PASS / 2 FAIL。R1の2 FAILは栽培種の袋seedsが発射時に減るという独立テスト側期待値誤り。既存仕様は発射時に種を予約しavailableを減らし、弾が着地して配置成功した時点で袋から消費する。該当2条件だけを狭く再確認したR2は2 PASS / 0 FAIL（[selection-followup.json](../evidence/spr01/fire-integration/independent/selection-followup.json)）。全GPU試験は再走せず、初回FAILを残したまま別結果として記録。製品修正なし、未解決FAILなし。
- 独立側は凍結68/68・保全128/128 hash一致を確認し、実GPU画像を目視。Godot内入力注入のみで、親もコード差分・原寸GPU/cropを確認し、全方向の正面共用を仮組込みとして限定技術受入。
- NOT_RUN: 物理入力、連続再生の印象/操作感、最終美術採用、旧 `main.click_fire` 即時入力前提の全回帰（未改造・未実行）、全天候・性能・書出し。今回の専用試験はpending action契約と主要描画/中断条件に限定。ゲームの水範囲・弾速・消費量等は変更しておらず、試遊用仮組込みはゲームバランスや最終美術採用ではない。

### 正面発射アニメv2（2026-10-20、比較試作）

- 対象: 共有HEAD `151a53f20255489ef08481e2a353258cd8ac559c`＋既存差分上の`assets/concepts/spr01/fire-front-v2/`。正面だけの試作で、ゲーム/runtimeは変更なし。v1・既存採用素材も変更なし。
- 変更点: 種はユーザー指示の発射時胴/顔/手1px下げ、手先追加1px下げ、足固定、葉の相対形維持を反映。4コマ・200ms・発射33msは維持。水は膨張を長くする比較方向に沿い、親の初期値で6コマ・400ms・発射150ms、2→4→6px形成と胴/顔変位 `[0,0,-1,+1,+1,0]px` を作成。数値・水の造形は最終採用仕様ではない。
- 制作担当自己確認: [素材検査](../evidence/spr01/fire-front-v2/self/self-check.json)、[HTML検査](../evidence/spr01/fire-front-v2/self/html-check.json)、[hash](../evidence/spr01/fire-front-v2/self/target-hashes.json)。寸法・alpha/palette・顔/足・葉・水の伸長/接続・イベント・HTML/GIF一致などを1回確認し、全コマ一覧を目視。親もcontact sheetを見て重大な崩れは確認していない。
- 表示時刻: GIFは20ms刻み100コマ・2秒ループ。種releaseはGIF上40ms、水は160msに近似。manifest/HTMLは33ms/150msを保持。
- 独立確認は7 PASS / 0 FAIL / 3 NOT_RUN（[報告](../evidence/spr01/fire-front-v2/independent/review.md)、[結果JSON](../evidence/spr01/fire-front-v2/independent/results.json)）。275個別照合を実施し、元138件と凍結成果63件のhash一致を確認。種の胴/手先の反動、水の3段膨張・150ms分離・400ms復帰、足の接続を確認。親は全コマと証拠を確認し、比較試作として限定受入。
- NOT_RUN: ブラウザー連続再生、実速の印象、ゲーム統合/水のゲーム内範囲・消費・連射・弾道、最終美術評価。水のゲーム内範囲は後日検討。

### 正面発射アニメv3（2026-10-20、比較試作）

- 対象: 共有HEAD `151a53f20255489ef08481e2a353258cd8ac559c`＋既存差分上の`assets/concepts/spr01/fire-front-v3/`。正面だけの比較素材で、ゲーム/runtimeとv1/v2素材は変更なし。
- ユーザー依頼: 種の速度を半分にし、水も遅くして溜め感と表情変化を加える。種はv2の動きを維持し、 `[66,100,100,134]ms`・400ms・発射66msへ厳密に倍化。閉眼コマでは明示依頼による縦2px開眼例外、通常開眼/idleは維持。
- 水は親の比較用初期値7コマ `[80,100,100,120,100,120,180]ms`・800ms・発射400ms。2→4→6px膨張後に6px大玉を120ms保持、胴変位 `[0,0,-1,0,1,1,0]px`、足固定。水の数値/姿勢はユーザー最終採用ではない。飛翔弾はv2と同じ画像/速度で、ゲームの水範囲などは今回変更なし。
- 制作担当の自己確認は[素材検査](../evidence/spr01/fire-front-v3/self/self-check.json)、[HTML検査](../evidence/spr01/fire-front-v3/self/html-check.json)、[凍結hash一覧](../evidence/spr01/fire-front-v3/self/target-hashes.json)、[制作メモ](../assets/concepts/spr01/fire-front-v3/production-note.md)。寸法/色/alpha、表情別の目口座標、開眼1×2px、種の顔以外のv2画素と時間倍化、水の膨張/保持/分離/接続、HTML時刻/GIF全200コマの復号を1回確認し、全コマ一覧を1回目視。
- 表示: GIFは20ms刻み・4000msループ、seed releaseは80ms、水は400msに近似。manifest/HTMLは正確な66/400msを保持。
- 独立確認は7 PASS / 0 FAIL / 3 NOT_RUN（[報告](../evidence/spr01/fire-front-v3/independent/review.md)、[結果JSON](../evidence/spr01/fire-front-v3/independent/results.json)）。355個別照合を実施し、旧201件と凍結67件のhash一致を確認。種の時間倍化と顔以外のv2保持、水の長い保持/400ms分離、表情変化、足接続を確認。親は全コマと証拠を確認し、比較試作として限定受入。
- NOT_RUN: ブラウザー連続再生/実速の印象、物理表示精度、ゲーム統合/水の範囲・消費・連射・弾道、最終美術採用。

## SPR-01 発射4方向v1のゲーム仮組込み（2026-10-20）

- 対象: 共有HEAD `151a53f20255489ef08481e2a353258cd8ac559c`＋既存差分。正面v3共用の旧仮組込みを、4方向行を持つ`assets/sprites/poc/player/fire-directions-v1/`へ更新。runtime 99ファイルを概念素材からbyte copyし、`source-copy.json`へ記録。旧正面仮組込み時の結果は直前節に履歴として残す。
- 承認済み素材条件: 24×36px/anchor(12,34)、down/left/right/up。種4コマ `[66,100,100,134]ms`/400ms/66ms発射で全コマ通常眼。水7コマ `[80,100,100,120,100,120,180]ms`/800ms/400ms発射。水の正面キャラクター7枚・形成FX7枚・飛翔画像はv3とbyte一致。左右は反転せず、背面は顔なし。socketは左(11,14)、他(12,14)。
- 実装メモ: [game-self実装報告](../evidence/spr01/fire-directions/game-self/implementation-note.md)、[runtime対象hash](../evidence/spr01/fire-directions/game-self/target-hashes.json)、[runtime copy一覧](../evidence/spr01/fire-directions/game-self/source-copy.json)、[保全確認](../evidence/spr01/fire-directions/game-self/preserved-check.json)。実装側は通常向きと発射中のマウス向きを連動。socketは投影上の弾表示に使い、論理発射起点・aim target・速度・範囲・衝突・保存への変更なし。ゲーム起動入口は[`run_poc.bat`](../launchers/run_poc.bat)。
- 素材担当自己確認: [self-check](../evidence/spr01/fire-directions/asset-self/self-check.json)で44キャラクター/44形成FXコマ、正面水のbyte一致、正面種の6画素（目周辺のみ）の変更、左右非反転を記録。[preserved-check](../evidence/spr01/fire-directions/asset-self/preserved-check.json)では保全204件一致。素材担当はGodot import・描画を実行していない。
- ゲーム実装担当の自己確認: 専用logic **16 PASS / 0 FAIL**（[結果](../evidence/spr01/fire-directions/game-self/logic-results.json)）。実GPU **26 PASS / 0 FAIL**（[結果](../evidence/spr01/fire-directions/game-self/gpu-results.json)）。left/right/up×種/水の開始向き、atlas/formation/影/足元/整数格子、socketと飛翔表示・logical origin、通常歩行復帰などを確認。左の射出口(319,180)、右/上(320,180)を画像上で確認。GPU位相比較は[contact sheet](../evidence/spr01/fire-directions/game-self/game-directions-contact4x.png)、[GIF](../evidence/spr01/fire-directions/game-self/game-directions-phase4x.gif)。
- 実装担当記録ではGodot 4.7.2 / Vulkan Forward+、RTX 5070 Ti、hidden起動を使用し、OS入力/前面化/カーソル操作なし。import完了・終了コード0、script parse/runtime errorなし。
- 独立確認: [レビュー](../evidence/spr01/fire-directions/independent/review.md)は集約12 PASS / 0 FAIL / 4 NOT_RUN。内訳の独立照合はart192 PASS、専用logic+GPU16 PASS、凍結/import audit3 PASSで、単純合算した件数ではありません。runtime/code206/206、source203/203、旧保全204/204、runtime copy99件の一致を確認。実際の4方向の表示と差分をレビューし、製品修正を要するFAILはありませんでした。
- 親はレビュー、実差分、素材contact sheet、自己および独立GPU画像を確認し、種の通常眼と発射4方向の制作/ゲーム組込みを限定技術受入。これはユーザーによる新方向の最終美術評価や実速の操作感の判断を代行しません。
- NOT_RUN: 物理入力/物理ウィンドウ画素、実速の操作感・ユーザー最終美術評価、全照明/全天候・性能・書出し・全回帰、保存復元・栽培種の再試験。水範囲調整は後日。前回の保存・栽培種確認を今回の再実行として数えていません。
