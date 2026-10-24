# TECH-3D-01 640×360単発撮影

- 対象版: HEAD `9901370` 上の既存3D試作。同じ昼、カメラ、幾何、材質を維持。
- 変更: `tests/render_study_3d/self_capture_640.gd` と本証拠フォルダのみ。実行中の `render_view.size` だけ640×360へ設定し、既存1920×1080 viewportでnearest3倍にGPU描画。
- 1回撮影。Vulkan Forward+ / RTX5070Ti。元画像640×360、配布画像1920×1080。GPU配布画像が全画素で元画像の正確なnearest3倍に一致。保存成功、エラーなし、終了コード0（`capture.log`、`capture-results.json`、`process.json`）。
- 出力: `noon_640.png`、`noon_640_at_1920.png`。配布画像を目視し、同じ昼の廃墟・舗装・影の構図を確認。これはnativeウィンドウ撮影ではなく実GPU viewport取得。
- 既存3Dソース/材質/シーン/project.godotの5件は実行前後ハッシュ一致（`integrity.json`）。画像と撮影スクリプトのhashは `hashes.json`。
- Hidden起動、root.unfocusable=true。OS入力・カーソル移動・前面化なし。native表示/初期フォーカス/物理入力はNOT_RUN。追加import、回帰一式、美術追加は実施していない。
- 自己Godot終了・全Godotプロセス0件、実行資源返却。編集停止。本番解像度採用を変更する判断ではない。
