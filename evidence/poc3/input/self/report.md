# POC3-INPUT 自己確認

- 対象: `9d54a6d1795065e6e642fe01543b2c8d2a1f27ee` + INPUT未コミット差分。最終ゲーム6ファイル/試験3本とuidのSHA-256は `freeze.json`。共有treeの他担当差分は保持。stage/commitなし。
- 実装: `input_latch.gd` 新規、`poc2_main.gd`、`poc2_session.gd`、`simulation/persistence.gd`、`ui/poc2_ui.gd`、`ui/map_ui.gd`。クリック開始時に通常/設置/スキルを固定。通常保持中Shiftは停止し解放まで再開不可。Shiftスキル後の通常化なし。モード変更/UI押下を保持しない。
- 操作: Shift左右スキル、E一覧、Tab/ミニマップ/閉じるボタン、Esc取消優先、Q/R/M/N旧割当解除。右クリックのマップ取消はGUI消費前に処理。メニューに音量/ミュート、pauseメニューを画面内に配置。説明を更新。
- 幅: `sow_width` 初期1、1/3/5/7の端停止選択と保存。既存PoC3欠落は1、存在する不正値は採用せずsession不変。実際の範囲播種/消費/プレビューは後続AREA-SEED。現HUD/説明も選択のみと区別。

## 実行結果

| 実行 | 結果 | 証拠 |
|---|---|---|
| headless import | exit 0 | import.log |
| 初回logic | 14 PASS / 1 FAIL、exit 1 | logic_results.json、logic.log、context.json |
| 保存限定追試 | 5 PASS / 0 FAIL、exit 0 | save_followup.json、save_followup.log |
| GPUエンジン内入力/撮影 | 26 PASS / 0 FAIL、exit 0 | input_results.json、input.log、followup_context.json |

初回保存往復FAILはJSON数値がfloatになるためint候補配列で不一致になったもの。数値型を先に検証してfloat候補1/3/5/7と比較し、intへ正規化するよう修正。保存往復と不正2/3.5/文字列/bool拒否・失敗不変だけ追試。初回結果を上書きせず残した。初回FAILを追試PASSへ合算しない。初回はGPUを実行せず、追試後にGPUを1回実行。

GPU入力はGodot内部 `root.push_input` のみ。通常左保持、左右通常保持途中Shift、解放後の再クリック、Shift左のShift先解放、Shift右のマウス先解放、設置右取消とShift解除、Esc優先、モード別ホイール、map停止/取消/閉じる、一覧登録/UI保持解除、旧キー無効、音量、F5保存を代表確認。マップのpopupを表示した状態でButton上の右クリック取消と戦闘漏れなしを確認。

`menu.png` / `help.png` / `map.png` は最小化を維持した640×360 SubViewport描画。目視で説明と閉じるボタンが読め、音量付きpauseメニューが画面内に収まる。画面内rect検証もPASS。map地形は実際に探索した領域のみで、全面既知fixtureではない。

## 保存・実行環境と停止

CONTENT-01が隔離sandboxのみを使用する予約を起動直前に確認。各起動前Godot0件。APPDATA/LOCALAPPDATAを本証拠内 `profile/` へ隔離（生成キャッシュはGit除外）。実ユーザーのPoC/PoC2既存3ファイルは読取hashのみで前後一致。初回contextと最終freezeに記録。

起動前の一時 `override.cfg` はno_focus=true/mode=1、内容は `startup_override.cfg`。GPU開始/終了ともroot.unfocusableとMODE_MINIMIZEDを確認。通常窓への復元、前面化、OS入力、カーソル操作なし。try/finallyで一時overrideを削除、最終Godot0件。ソース/試験を凍結し追加実行を停止。

## NOT_RUN / 残課題

物理キーボード/マウスからOSを経由する経路、通常窓・全サイズ・全照明、全体回帰、音の実聴、mapのおたすけ命令の広い回帰は未確認。AREA-SEED実効果は未実装。独立検証と最終合否は親へ返す。この自己結果はPoC3全体の受入を意味しない。
