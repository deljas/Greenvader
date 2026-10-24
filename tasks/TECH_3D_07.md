# TECH-3D-07 ツタと苔の軽量バリエーション

## 管理欄
- ID: TECH-3D-07
- 状態: 完了
- 担当ツール: なし
- 担当セッション: なし
- 更新日: 2026-10-16
- 予約中の編集範囲: なし
- 予約中の共有資源: なし
- 最終担当: codex-20261016-vegetation-variation

## 目的・対象・資料
- TECH-3D-06の共有未コミット成果を土台に、直線に揃うツタと同じ大きさの苔へ少数のバリエーションを追加する。ユーザーは検証段階の過度な作り込みは不要と明示。直線/蛇行する幹・曲がる枝、小/大の苔（およそ1×1、2×2の表面寸法）を混ぜる範囲に限定。
- 共有C:/godot/greenvader、HEAD99013702eaf36db72a64d60d284680fb834f13c5＋既存ART/TECH差分。AGENTS、tasks/README、TASK_TEMPLATE、docs/00〜04/STATUS/DECISIONS、TECH_3D_06を読む。

## 割当・禁止・依存
- TECH-3D-06完了が前提。親が設計/票/最終受入。Sol実装は上記scripts3件とself_variation*、evidence/.../self/。別Sol検証はindependent_variation*とevidence/.../independent/のみ。Lunaは上記docs/索引のみ。
- 共通plant_parts、建物geometry/defs/屋根、lab/UI、ひび、scene/bat、旧成果/証拠、通常ゲームとproject設定は変更しない。共有treeの他者編集を戻さず、再委任/commit/branch変更禁止。
- OS入力/前面化/カーソル操作禁止。GPUはHidden/unfocusableと内部信号/viewport取得のみ。他者プロセスを止めない。

## 合格条件と検証
1. 同じ葉/茎meshを使い、直線寄りと明瞭に曲がる幹が共存する。開始間隔、曲率/位相、枝の高さ/長さを少数の固定seedパラメータでずらし、等間隔の梯子に見える反復を軽減。新たな再帰分岐/自動迂回solverは作らない。
2. 経路をsetup時に固定し、成長率往復でも配置維持。親junction接続と親到達後の成長を維持。移動した幹も開口/端を検査、窓を横断して曲げない。既存屋根/通路/共有部品を保持。
3. 苔は小/大（およそ表面1×1、2×2）と必要なら細長の少数共通形を混在。中心/縦横比/模様位相を固定seedでずらす。同じマス内の円の繰返しを軽減し、大patchも曲面と開口に対応。既存独立ON/OFF・量操作を保持。建物材質へ焼き込まず、ひびは変えない。
4. 実GPUの代表A/C近景と苔単独で差を確認。0/50/100と往復・OFF対照は最低限、一度の短いrunでまとめる。自己の簡潔なraw経路/patch寸法とbefore/hashを保存。全ゲーム回帰/性能/動画/全方向はNOT_RUN、headless MultiMesh getterは使わない。
5. 独立は凍結ソース/差分・raw・既存GPU画像の限定確認。新規GPU再走や網羅試験不要。親が画像と差分を確認し、Lunaが短く記録して完了。最終美術評価はユーザー。

## 終了条件・引継ぎ
- 起動は既存[run_vegetation_lab.bat](../launchers/labs/run_vegetation_lab.bat)。UI追加なし。専用labのみで通常ゲーム/P2/正式960方針を変更しない。
- 2026-10-16 親取得。TECH-3D-06は完了。過度に磨かず、少数の形の混在が見えた時点で終了する。
- 2026-10-16 実装凍結、自己18 PASS / 0 FAIL、GPU1回exit0、Godotなし。source-manifest SHA256=42cf5c756ba0620574b676a6dc616962cb46aecd26cda226b1f0f0f0ef0de670。親は3件コードとA/C近景・苔単独を確認し、追加磨き込み不要と判断。独立へ引継ぎ。
- 2026-10-16 独立4 PASS / 0 FAIL / 3 NOT_RUN。各棟の代表主幹/枝・大小patchとGPU画像、代表nearest3・苔OFF一致を確認。独立hash集計は旧証拠参照KeyErrorでNOT_RUN（製品不具合ではない）。親は別途実Get-FileHashでソース4件と保全10件の一致を確認。親は専用labの軽量バリエーションとして限定技術受入。Lunaへ短い記録を依頼。
- 2026-10-16 Luna更新の5文書を親が確認。全子編集停止、Godot終了、担当予約を解除して完了。美術最終評価はユーザーへ残す。

## 結果・証拠・限界
- 直線/蛇行主幹・曲がる枝と、約1×1/2×2の苔を固定seedで混在。共通部品・独立操作・屋根・ひび・UIを保持。
- [自己報告](../evidence/vegetation-variation/self/report.md)、[独立報告](../evidence/vegetation-variation/independent/report.md)、[A近景](../evidence/vegetation-variation/self/A_closeup_ui_1920.png)、[C近景](../evidence/vegetation-variation/self/C_closeup_ui_1920.png)。
- 開口前で止まる簡易方式、苔サイズは表面上の公称寸法で表示領域は端/開口で切り取る。完全な自動巻付けや迂回ではない。native/物理入力、動画、全照明/全位置、性能、通常ゲーム回帰は未検証。
- 次は同[run_vegetation_lab.bat](../launchers/labs/run_vegetation_lab.bat)でユーザーが見た目を確認。追加磨き込みや通常ゲーム/P2自動再開は行わない。
