# TECH-QV-01 クォータービュー技術確認

## 管理欄

- ID: TECH-QV-01
- 状態: 完了
- 担当ツール: なし
- 担当セッション: なし
- 更新日: 2026-10-15
- 予約中の編集範囲: なし
- 予約中の共有資源: なし
- 最終担当: codex-20261015-quarter-view-01

## 親が記入する項目

- 作業IDと段階: TECH-QV-01。専用の小さい検証マップまで。P2以降を再開しない。
- 役割: 親が設計・最終判断、green_implementerが実装と自己検証、別green_verifierが独立検証、green_documenterが承認済み記録。子の再委任禁止。
- 目的: 本格的な素材制作の前に座標、寸法、分割、前後関係、足元衝突、遮蔽、入力、画素表示の条件を確認する。
- 対象: C:/godot/greenvader。全員共有ツリー、差分の再適用なし。
- 基準: HEAD 99013702eaf36db72a64d60d284680fb834f13c5。開始時の既存未コミット6文書とART-01/02/03素材・試作を保持。evidence/quarter-view/baseline-existing.json と baseline-existing.patch に開始状態を保存。他票の予約なし、Get-Processで既存Godotなし。
- 資料: AGENTS.md、TASK_TEMPLATE.md、tasks/README.md、ART_02.md、ART_03.md、docs/00〜04、STATUS.md、DECISIONS.md、assets/concepts/art02/daylight-v1.png、assets/concepts/art03/study-960x540-at-1080p.png。
- 制約: 960×540基準と1080pで正確な2倍。輪郭線なし。既存PixelArt.flowerの仮表示を流用。完成美術・画像生成・ライト・昼夜・通常マップ作り直しは対象外。地面の広域明暗を描かない。OS入力、カーソル移動、前面化は禁止。入力はエンジン内注入、GPU画面は前面化なしで取得。物理入力はNOT_RUN。他解像度方針は未決定。
- 編集割当: 実装者は専用scene/scripts、run_quarter_view_lab.bat、tests/quarter_view/self*、evidence/quarter-view/self/のみ。検証者はtests/quarter_view/independent*、evidence/quarter-view/independent/のみ。文書担当は上記docsとtasks/README.mdのみ。親は本票とevidence/quarter-view直下の基準・承認記録。
- 編集禁止: project.godot、通常ゲームのscripts/scenes/data、既存assets、既存testsと既存証拠。必要ならまず親へ報告。
- 選択する最小方式: 論理座標(u,v)と4単位のWorldState格子を保持し、専用表示変換 P(u,v)=(u-v,(u+v)/2)。逆変換 (x/2+y,y-x/2)。厳密な参考画像の投影推定ではなく2Dの2:1 dimetric試験。スプライト自体は回転/非整数拡縮しない。入力は画面方向で正規化した等速→逆変換→Walker衝突→投影。論理軸方向の物理速度が異なるトレードオフを明示。
- 描画の条件: 建物基底の投影と衝突を同じ論理footprintから生成。大きい建物を中心Y一点でソートしない。壁/屋根を深度に沿うパーツまたは画面列へ分割し、各列の前端足元Yで既存花とソートする最小実証。背面隠れは重なる上物の減光/透過で操作対象を見せる。屋根は衝突しない。
- 合格条件: (1)専用シーン動動、通常ファイル保全 (2)960×540で建物・前後左右通路・低障害物が視認可能 (3)前横後の順序と遮蔽対策 (4)足元境界で止まり周回可能 (5)画面入力方向と斜め等速 (6)カメラ込みマウス逆変換と格子マーカー (7)移動/カメラの整数画素・nearest (8)1080p出力の全画素が2×2ブロックで960原画と一致 (9)素材寸法・原点・分割単位と統合課題を記録。
- 検証方法: 条件ごと1回、主要回帰のみ1回。GPU実描画PNGとログ、ソースハッシュを保存。実描画不能ならNOT_RUNを隠さない。長時間試験・総当たりなし。通常ゲームの動動スモークと既存ファイルハッシュを確認。
- 自律判断: 専用マップの可逆的寸法・色・配置、最小テスト実装。投影方式や通常ゲーム変更が必要なら親へ返す。
- 終了条件: 専用マップの技術結果、動動方法、画面、素材制作条件、PASS/FAIL/NOT_RUNと限界の提示。美術品質承認・通常ゲーム統合完了とはしない。

## 引き継ぎ（親が更新）

- 2026-10-15: 既存差分と予約を確認し取得。実装開始前に上記条件を定義。
- 実装凍結: evidence/quarter-view/self/source-manifest.json の8ファイル。親が全ハッシュ一致、通常ゲーム127ファイル不変を確認。QuarterProjectionへ命名変更後の自己結果はlogic16 PASS、GPU24 PASS/0 FAIL/物理入力NOT_RUN。重複項目は合算しない。
- 親の画像確認: front/behind_faded/right_frontを確認。288×256の仮建物、足元通路、裏の透過を視認。実1080画像の全画素2倍一致は自己検証ログを確認。美術評価ではない。
- 実装担当は編集・Godot/importを停止、Godotプロセス0と報告。独立検証担当へ実行権を移譲。通常ゲームスモークは独立側1回のみ。
- 独立検証r1: 衝突・周回・左右82画素可視・遮蔽・入力等速・整数カメラ・実1080全画素2倍がPASS。マウス注入はget_mouse_positionへ位置が反映せずFAILを保持。screen(494,413)/camera(70,365)の直接逆写像は論理(550,466)でPASS。通常ゲーム別GPUスモーク1回PASS（640×360/1280×720、grid512、ERRORなし）。
- 限定修正へ: 検証者はGodot停止・実行権返却済み。親判断で専用labにMouseMotionイベント座標を保持させ、物理更新時にカメラ込み逆写像を行う。物理OSマウスを動かさず入力経路を検証するため。変更後はマウス関連のみ再取得、回帰一式の再走なし。
- r2凍結: self/source-manifest-r2.json。実装変更はlab.gdのマウス位置保持・イベント取得・カメラ更新後の再投影のみ。自己マウス限定3 PASS/0 FAIL、GPU再取得は独立側へ。実装者停止、Godot0、実行権を独立検証者へ移譲。
- 最終結果: 独立r2マウス限定GPU3 PASS/0 FAIL。注入座標→期待セル、マウス静止でcamera再投影、マーカー16画素を確認。r1の失敗ログを保持し、その他の条件は変更のないr1主要PASSを根拠に限定受入。全回帰再走はしていない。
- 親の最終判断: evidence/quarter-view/parent-acceptance.md。通常ゲーム127ファイルと既存未コミット非文書63ファイルは不変、r2 manifest9件一致（final-integrity.json）。通常ゲームスモークPASS。今回の実装による通常設定変更なし。
- NOT_RUN/限界: 物理入力、初期フォーカス比較、連続動画全位置、他解像度、複雑建物、量産性能、通常統合。HUDセル文字のみ1physics tick遅れ。美術品質を承認しない。
- 記録完了: LunaがQUARTER_VIEW_TECH、02_TECH_AND_ART、STATUS、DECISIONS、VALIDATION、ASSETS、tasks/READMEを更新。親が内容・以前のART記録保全・リンク確認結果・diff checkを受入。
- 終了: 実装者・独立検証者の停止、Godot0、文書担当編集終了を確認して予約解除。追加コミットなし。動動はrun_quarter_view_lab.bat、実1080は同bat --1080。次は記録した制作条件を用いた美術制作の判断であり、このチャットで通常統合やP2以降へ着手しない。
