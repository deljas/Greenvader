# TECH-3D-04 太陽角度の操作と周回点光源

## 管理欄

- ID: TECH-3D-04
- 状態: 完了
- 担当ツール: なし
- 担当セッション: なし
- 更新日: 2026-10-16
- 予約中の編集範囲: なし
- 予約中の共有資源: なし（実装・独立検証の実行終了）
- 最終担当: codex-20261016-light-controls

## 目的・対象・依存

- ーーザーは既存Godot試作へ、任意に太陽光の仰角/方位角を変える機能と、建物周辺を回る点光源を追加するよう依頼した。
- 共有作業ツリーC:/godot/greenvader、基準HEAD99013702eaf36db72a64d60d284680fb834f13c5とART/TECH未コミット成果。tasks/README、TASK_TEMPLATE、docs/00〜04/STATUS/DECISIONS、TECH_3D_03を継承。独立歩行sprite試作は完了済み。

## 割当・仕様

- 親: 管理/判断。Sol実装: light_lab.gd、既存sprite_shadow_lab.gdの真上光安全化、専用scene/bat、self_light*、evidence/.../self/。別Sol検証: independent_light*とevidence/.../independent/のみ。Luna記録: 上記docs/索引。共有ツリーで他者編集を戻さない、再委任/commit/branch変更禁止。
- 新しい照明操作シーンとして既存歩行labを継承/利用。旧scene/bat挙動は維持。通常ゲーム/project.godot、study/geometry/material、過去証拠変更禁止。
- UI: 方位角0〜360度、仰角-90〜90度をスライダー＋数値入力で操作（角度定義を短く示す）。仰角<=0で太陽の直射OFFを明示。真上/真下でもlook_at/Basisの退化・NaNを起こさない。初期は従来昼方向。
- 影有効のOmniLight3Dを建物外周で自動周回。位置を示す小さな球は影を投げない。点光源ON/OFF、周回の再生/停止、停止中の周回位置調整、太陽ON/OFFを付ける。値や速度の低リスク初期値は実装者裁量。昼も効果を読める色/強さ、太陽OFFで点光源単独を確認可能。
- 歩行spriteは継続。光ごとの影板を用意し同じコマ/flip/footを同期。sun影板とpoint影板を別layerとshadow_caster_maskで分離して互いの光に余分な影を落とさない。各影板yawは該当光の水平向きへ向ける近似。原則表示spriteは従来unshaded（今回受光の新規美術設計はしない）。
- 640×360/nearest整数表示、輪郭線なし/硬い影を維持。UIが主要被写体を隠さず読めること。
- OS入力送信/前面化/カーソル移動禁止。自動GPUはroot.unfocusable=true＋hidden起動、実UI確認はGodot内Input.parse_input_eventまたはControlシグナル。物理経路は未確認とする。共有Godot資源を無断で競合させない。

## 合格条件・証拠・終了

1. 専用batで太陽角度をUIから変えられ、建物の陰影/投影影が変化。代表2方位/2仰角、仰角90/-90を有限値/エラーなしで確認（総当たり不要）。角度制御は連続任意値、プリセットだけにしない。
2. 点光源が建物の周囲を回り、照明/影が位置に応じて変化。ON/OFF・再生停止・停止中の位置操作を確認。少なくとも2地点とOFF参照を実GPU取得。
3. 複数ライトでも歩行コマが同期し、各light caster maskの分離を確認。少なくともpoint単独で不適切な太陽用影板をOFFにして画像が不変であること等を限定確認。
4. 代表PNG640→1920が全画素nearest3倍一致。UI付き実GPU画像、短い点光源周回動画または比較PNGを提示。動画は実時間性能と区別。
5. 自己確認後ソース/証拠凍結、独立検証は実差分と主要条件の1回に絞る。独立Godot再起動する場合は明示資源移譲後。全ゲーム回帰・全方向保証なし。
6. 親が画像/差分/結果を確認、文書更新・予約解除して終了。通常ゲーム統合/Unity移行/解像度正式変更/P2再開なし。

## 引き継ぎ

- 2026-10-16 親取得。専用操作シーンを追加する。
- 2026-10-16 実装凍結。自己15 PASS / 0 FAIL、GPUプロセス終了0・全Godot終了。source-manifest SHA256 `0d1665ac654b6adb36aa1212201a1f561afbf2484e3abc8e84cefbcf3673f521`。親は実装差分、UI2枚、動画復号コンタクトシートを目視。独立検証へ移譲する。
- 2026-10-16 独立6 PASS / 0 FAIL / 3 NOT_RUNを親が確認し、専用試作として限定受入。独立は静的確認と既存GPU画像の画素/JSON/hash検査で、新規GPU再実行ではない。77件凍結一致、既存8件保全＋許可された垂直光guardのみ。点光源単独で太陽用板OFFは差0画素、点用板OFFは616画素。UI/背景の代表4組は全画素nearest3倍一致。証拠: evidence/render-study-3d/light-controls/self/report.md、independent/report.md。
- native表示/物理入力、独立GPU再実行、全角度・実時間性能はNOT_RUN。UI1920はGPUroot640からCPU最近傍3倍の提示画像、背景1920は別GPU viewport。動画は48サンプル/12fps/4秒の提示で性能測定ではない。影は各光へ向く輪郭板の近似で、キャラ受光は未追加。実装・検証担当編集停止、Godot 0件・資源返却済み。Lunaへ承認済み事実の記録を委任。
- 2026-10-16 親が記録5文書を確認。専用lab/起動bat/UI画像/4秒動画を完成成果として提示し、予約解除。次はーーザーがrun_light_lab.batで照明表現を確認する。通常ゲーム統合・正式解像度変更・Unity移行・P2再開は行っていない。
