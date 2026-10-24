# TECH-3D-02 硬い影と色・階調補正の比較

## 管理欄

- ID: TECH-3D-02
- 状態: 完了
- 担当ツール: なし
- 担当セッション: なし
- 更新日: 2026-10-15
- 予約中の編集範囲: なし
- 予約中の共有資源: なし（実装者のGPU撮影終了）
- 最終担当: codex-20261015-shadow-grade

## 目的・対象・資料

- ユーザーは同じ640×360構図で「硬い影のみ」「硬い影＋控えめな色・階調補正」を比較する提案に同意。まず静止画で方向を絞る。動作時のちらつき確認は採用候補決定後。
- C:/godot/greenvaderの共有作業ツリー。基準HEAD 99013702eaf36db72a64d60d284680fb834f13c5、既存ART/TECH未コミット成果を保持。他者の変更を戻さない。
- 資料: AGENTS.md、tasks/README.md、TECH_3D_01.md、docs/00〜04・STATUS・DECISIONS。元画像evidence/render-study-3d/640/noon_640_at_1920.png。
- 依存: TECH-3D-01の同一昼3Dシーンと640撮影が完了済み。

## 割当・制約

- 親: 仕様・作業票・受入。Sol実装: self_capture_style.gd、style_grade.gdshader、evidence/render-study-3d/style/。別Sol検証: read-only、必要な報告のみstyle/independent-report.json。Luna記録: 親承認後にdocs/STATUS・DECISIONS・VALIDATIONとtasks/READMEを短く更新。
- 既存study.gd、ruin_geometry.gd、concrete.gdshader、通常ゲーム、project.godot、過去証拠は変更禁止。追加の撮影用コードで既存シーンを実行時設定する。必要な追加ファイルは親へ連絡。
- 建物・素材・カメラ・昼の太陽方向/色/強さを共通にし、Aは影の硬さのみ変更。BはAに色調/階調補正だけ追加。輪郭線、ディザ、全面ぼかし、AA、光の焼込みなし。素材の粒度調整は今回は行わない。
- 補正は640×360で完結してからnearest3倍1920×1080。GPUで実際に描画し画像生成や事後の画像加工で代用しない。
- OS入力送信・前面化・カーソル移動禁止。root.unfocusable=true、Start-Process -WindowStyle Hidden。既存Godotを終了しない。native表示/初期フォーカスは未実測ならNOT_RUN。
- 再委任・コミット・ブランチ切替禁止。試験はほどほど、同じ条件の繰り返しや回帰一式なし。

## 合格条件・証拠・終了

1. 640×360でA（硬い影）/B（同じ影＋控えめな暖色明部/寒色暗部と階調整理）の実GPU PNG、各1920×1080を保存する。
2. 影の設定/実装を確認し、元画像より境界が明瞭になっていることを実画像で確認。残る補間を完全二値化と誤称しない。設定だけで不足なら親へ返す。
3. カメラ/形/素材/照明条件がA/Bで共通、Bの補正が拡大前、両画像が全画素nearest3倍一致。A/Bが実際に異なり、画像やログに描画エラーがない。
4. 既存ソースを保全、実装と画像ハッシュを凍結して別Solが限定read-only確認。親が見た目を確認して提示。美術の最終採用はユーザー判断。
5. 記録更新とGPU終了、予約解除で終了。通常ゲーム統合、解像度採用変更、Unity移行、P2再開なし。

## 引き継ぎ

- 2026-10-15 親が取得。追加2画像の制作のみ承認済み。
- 初回HARD/blur0で全面に自己影縞が発生し、親・実装者とも視覚FAIL。initial/へ保存。HARD維持、blur1/bias0.1/normal_bias1へ実行時調整し再撮影、親が縞解消と硬い境界を確認。実装者ソース凍結・Godot停止、独立read-only確認へ。Bは輝度20段を20%混ぜる弱い補正で、20色制限ではない。
- 最終版はstyle/source-manifest.jsonに2ソース/4PNGを凍結。自己GPU撮影終了0、独立read-only 4 PASS / 0 FAIL / 2 NOT_RUN、凍結6件/既存5件hash一致。親もコード・最終画像・報告を確認し、比較試作として受入。画像はA_hard_shadow_1920.png、B_hard_shadow_grade_1920.png。native/物理入力と時間変化は未検証、美術採用はユーザー判断。
- LunaのSTATUS/DECISIONS/VALIDATION/索引更新を親が確認。全子編集終了、Godot停止済み、予約解除。ゲーム統合/解像度採用変更/P2再開はなし。
