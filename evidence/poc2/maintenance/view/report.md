# POC2-06 view 保守・自己報告

基準HEAD `151a53f20255489ef08481e2a353258cd8ac559c` と共有未コミット差分。2026-10-22。実装変更は `scripts/poc2/poc2_main.gd` と `scripts/poc2/ui/poc2_ui.gd` のみ。他者の変更、第一弾、通常セーブ、仕様・バランス・美術を変更しない。beforeファイルと `main.patch` / `ui.patch` が今回差分。最終hashは `source-manifest.json`。

## 修正

1. タイトルから説明へ入っても、`save_game()` 自体がタイトル由来を拒否する。F5と直接保存呼出しの双方で、未プレイsessionが既存slotを上書きしない。
2. help action の多重openを無視し、戻り先を `help` へ上書きしない。
3. 説明中は設置補給popupを隠す。戻る際はtitle/pauseだけメニューを作り、placement_supplyは同じ既存popupを再表示する。入力した補給量と停止状態を維持し、二重設置を起こさない。
4. 今回のGPUで、従来の `ui.show_menu` の条件式Arrayを `Array[String]` へ直接代入すると実行時型エラーになることを発見。親承認の上、空の型付き配列を `assign()` する2行へ最小修正した。

## 検証

Godot 4.7.2、Vulkan Forward+、RTX5070Ti。`root.unfocusable=true`。入力は `Input.parse_input_event` のみ、画像はViewportから取得。OS入力、実カーソル操作、前面化なし。保存は `user://poc2_maintenance_view_20261022` 専用領域で、通常のPoC1/PoC2 slotは使用しない。require_escalatedの正規許可で実行。

- 初回限定GPU: `menu_boundaries.gd`。**10 PASS / 2 FAIL**。タイトル/タイトル説明F5および直接保存で専用既存slotのSHA256不変、説明再open保護、通常play/pause F5保存、補給popup説明往復と数量17の維持、戻って一度だけ設置（設置費30＋弾17）を確認した。
- 2 FAIL は上記4の従来型エラーによるtitle/pauseメニュー復帰。`checks.json` / `gpu.log` に原結果を保持し、上書きしていない。
- 型修正後、影響する経路だけ `menu_arrays.gd` で追試。**5 PASS / 0 FAIL**。`change_scene_to_packed(Main)` により実起動同様に `current_scene` として入り、タイトル状態と「新しく始める／続きから／操作説明」の3ボタンが生成されることを確認。実ボタンクリック・Escで説明からtitleへ戻り、実新規開始→pauseの5ボタン生成→実説明/閉じるクリックでpauseへ戻る。
- 初回2 FAILは後続の同条件PASSで解消。未解消FAILなし。関係のない回帰一式は再実行していない。

## 前回の見落としとの区別

初回PoC2のGPU試験ではテストとしてsceneをinstantiateし、`current_scene` でないため通常起動タイトルを通していなかった。その描画合格はゲーム画面・マップ等の確認であり、実起動タイトル生成を確認した証拠ではなかった。今回の実行時型エラーはその範囲の見落としで、今回初めて通常タイトル経路を含む限定確認を行った。

## 画像・証拠

- `01_supply_restored.png`: 説明を閉じ、補給量17を維持したpopupが一つだけ表示。目視確認済み。
- `02_after_single_placement.png`: 確定後に一体を設置。
- `03_title_restored.png`: 実起動経路のタイトル3ボタン。目視確認済み。
- `04_pause_restored.png`: 説明からpauseへ復帰。
- 初回: `gpu.log` / `checks.json`。
- 影響追試: `menu-arrays-gpu.log` / `menu-array-checks.json`。

## NOT_RUN・終了

物理キーボード/マウスからOSを通る経路、長時間試験、全ゲーム回帰、美術/楽しさの評価はNOT_RUN。初回PoC2の限定合格を全域へ拡張しない。全Godot実行は正常終了、最後の追試exit0。Godot/import権を親へ返却、source編集停止。最終受入は親と独立検証が判断する。
