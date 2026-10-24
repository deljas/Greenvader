# POC3-SOURCE: 履歴保存とゲーム起動入口の統一

## 管理欄

- ID: POC3-SOURCE
- 状態: 完了
- 担当ツール: なし
- 担当セッション: なし
- 更新日: 2026-10-24
- 予約中の編集範囲: なし
- 予約中の共有資源: なし
- 最終担当: codex / codex-20261024-poc3-implementation

## 実施時に具体化する範囲

- 目的: 承認済みの [ソース管理方針](../docs/SOURCE_MANAGEMENT.md) を実際の起動入口とGit履歴へ反映する。PoC3の実作業では最優先。
- 対象: C:/godot/greenvader。取得時のHEAD、全差分、未追跡・ignored素材、他担当予約、既存プロセスを確認する。共有ツリーを前提に他者の成果を破棄しない。
- 担当: 親が棚卸し結果・削除対象・commit/tagを管理。Solが必要な実装修正、別Solが限定検証、Lunaが確認済記録。開始前に編集範囲とGodot/import所有権を確定する。
- 順序: (1)現状の素材・コード・資料・試験等を分類し必要なものを意味のある単位でcommitして基準版を保存。(2)run_game.batが最新の遊べる版を起動するよう統一。(3)機能比較・検証で再利用するlabだけ残し、不要な入口は履歴に残っていることを確認後削除。(4)起動案内と現役の参照先を更新。
- 合格条件: 通常のゲーム起動batは一本。残したlabに具体的用途がある。削除対象はcommitから復元可能。保存データを削除・上書きしない。通常起動先と現在のゲーム版の対応を限定確認。旧版の既知問題や未検証を合格扱いしない。pushは実施しない。
- 安全・検証条件: OS入力送信・カーソル移動・前面化禁止。必要な入力確認はGodot内注入、描画は非前面化撮影。検証は限定的に行い未実施はNOT_RUN。利用者所有の実行中ゲームを停止しない。
- 対象外: ゲームルールの変更、素材の追加磨き込み、PoC番号によるゲーム一式複製、大量の旧証拠の一律削除。
- 記録先: ソース管理方針、launchers/README.md、docs/STATUS.md、必要な検証記録。本票に実際のcommit/tag、残す/削除するbat、試験結果を記録。
- 終了条件: 親が差分・限定検証・履歴からの保全を確認し、運用と実態を一致させて引き渡す。

## 引き継ぎ

- 2026-10-24: ユーザーの壁打ちで方針合意。実施は未着手。設計合意と整理完了を区別する。

## 今回の取得と編集境界

- 2026-10-24: ユーザーがPoC3自律実装と機能単位コミットを許可。HEAD 2069913、共有作業ツリー。既存PoC2/素材/証拠等の未コミット成果を棚卸しして保全後に入口整理。pushなし。
- CONTENT-01は別Claudeが案出し中。tasks/CONTENT_01.mdとdocs/CONTENT_CATALOG.mdおよび将来のcontent_pack一式は取得・編集・ステージしない。相手のGodot/import予約変化を実行前に確認する。
- 親は棚卸しと保全コミット、Solはまず読取調査のみ。削除可能な履歴が確認できるまでbatを削除しない。独立検証は別Sol。OS入力/前面化禁止。

- 履歴保全完了: 4f1a79b（既存素材・描画試作/証拠2361ファイル）、6429634（PoC2/主人公統合・資料/証拠578ファイル）。タグpoc2-before-poc3を6429634へ付与。今回の新しい動作検証ではなく既存成果のスナップショット。CONTENT-01、アプリ添付、生成キャッシュは除外しディスクに保持。
- 入口整理の承認範囲: project.godotのmain_sceneをscenes/poc2.tscnへ、run_game.batの現役コメント。旧通常入口launchers/run_poc.bat・run_poc2.bat、旧比較用labs/run_art_study.bat・run_quarter_view_lab.bat・run_render_study_3d.batの5本を削除。全て6429634の履歴から復元可能と確認。シーン/素材/コード/証拠は削除しない。
- Sol追加割当: tests/poc3/source/self_*.gdとevidence/poc3/source/self/。残すlabはtown/vine_compare/asset_showcase/greening_map/vegetation/light/sprite_shadowの7本。ユーザーsaveは読み取りhash照合のみ、試験で書かない。Godotは自己検証時のみSolが所有。CONTENT-01の予約変化を直前再確認する。

- 文書担当の追加編集範囲: README.md、docs/POC2_GUIDE.md、docs/POC_GUIDE.md、docs/ASSETS.md、docs/QUARTER_VIEW_TECH.md。現役入口をrun_gameへ統一し、過去の試作起動は履歴または既存シーン直接指定の案内へ修正する。過去の試験事実は書き換えない。

- 親の追加割当: .gitignoreへ自己検証の隔離runtime_profileだけを除外追加。生成キャッシュは削除せず保持し、試験結果/ログ/画像は履歴へ残す。

- 自己検証完了・実装凍結: HEAD 6429634 + self/implementation.diff、self/source_hashes.json。自己headless6 PASS、GPU初回9 PASS/2 FAIL（非フォーカスGUI注入問題）→probeのみ修正の追試11 PASS/0 FAIL。実ユーザーsave3件不変、Godot0件。親は実diffとtitle画像確認済み。実装Sol停止、独立Solへtests/poc3/source/independent_*.gd・evidence/poc3/source/independent/とGodot実行権を移管。文書更新は継続可、ゲーム対象変更不可。

- 親の限定受入: 独立reportは10 PASS/0 FAIL/6 NOT_RUN（起動smoke6観測はうち1項目）。13hash固定、5bat復元blob一致、実save3件不変。親は実差分・自己GPU title・独立証拠を確認して通常入口整理を受入。物理入力/OSbat起動/全lab/広い回帰は未検証。独立probe終了時の残存診断は未確定でreportへ記録、起動条件と区別。ゲーム全体の合格ではない。
- 両Solは編集停止・Godot0件。文書担当は確認済結果のみ追補。importが生成した既存map_orientation試験uid3件もリソース識別子として保全し、この整理コミットへ含める。保存/コード内容は変更しない。次はPOC3-SAVE-BASEで旧save隔離を先行し、VISIBILITYへ進む。

- 文書担当も編集停止。親が現役案内102リンクと追補結果を確認、資料・証拠を含め入口整理を機能単位でコミットする。全担当停止を確認し予約解除。
