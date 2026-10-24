# TECH-3D-09 独立限定検証

2026-10-16 / HEAD `99013702eaf36db72a64d60d284680fb834f13c5`＋共有未コミット成果。指定source-manifest SHA256 `9ba09266b55c830b8def6b308fc9fb4a1aaafec1b794efbed231d6f11ca9ad3a`。Windows。提出GPUはGodot4.7.2/Vulkan Forward+/RTX5070Ti。

**5 PASS / 0 FAIL / 3 NOT_RUN**。作業票、実差分と製品4ファイル、before原文、raw、最終GPU PNGを確認。Godot再実行なし。

| 条件 | 結果 | 方法・根拠 |
|---|---|---|
| terrain_display | PASS | 実before/afterとGPU目視: 舗装id6は共有ひび経路上の小さな1房、土は従来3房。種/芽/成熟PNGを確認し成熟でも舗装面が広く残る。固定seedの土サンプル生成順と非舗装transformを維持。refreshに乱数再配置なし。 |
| state_rate_preservation | PASS | 実コード・raw独立集計/自己証拠レビュー: raw14件の対象1422・緑化/成熟counterをterrain/stageから再集計し一致。30セルずつの土/舗装が同stage/growth、反射ON/OFF・fixture・太陽135前後のsnapshotの全ゲーム値も一致。表示コードはstateを読むのみ。自己refresh不変/logic13PASSは証拠レビューであり独立再実行ではない。 |
| real_reflection | PASS | 実コード・提出GPU目視/offline: 共有World3Dの320×180鏡像camera、cull_mask1、床/基壇layer2・水layer4除外を確認。通常水たまりにAの扉/壁が映り太陽変更へ追随。影なし赤箱の池内部ROI(153,172)-(181,190)で251pxが赤系に変化。自己投影式を再利用せず画像の内部矩形から比較。 |
| pixel_nearest | PASS | GPU PNG独立比較・実コード: normal_reflection_ON_world640/1920は640×360/1920×1080、全RGBA画素nearest3一致。反射textureはfilter_nearest、AA/TAAなし。 |
| freeze_and_preservation | PASS | 独立SHA256と実ログ: 指定manifest digest・source8件一致。before110件のうち許可済み編集2件を分け、保全108件すべて一致。今回証拠101件と旧TECH08証拠39件も一致。最終reflection/final exit0・stderr空、実ログにエラーなし。初回反射FAILの証拠は保持。 |
| independent_engine_run | NOT_RUN | 未実施: 表示変更は実ソース・raw・提出GPUで足りるためGodot/再描画/新テストなし。RNGやMultiMeshの独立runtime再計測なし。 |
| native_physical_input | NOT_RUN | 未実施: native起動/フォーカス/物理入力。OS入力送信・前面化・カーソル操作なし。 |
| broad_performance_regression | NOT_RUN | 範囲外: 追加反射の性能コスト、長時間/全方位/全地形形状/全game回帰、全世代の旧PNG網羅照合、美術最終評価。 |

詳細数値は `offline-checks.json`、凍結/保全照合は `hash-checks.json`。保全照合は一度だけ実施。before-manifestは変更前110件を含むため、予定したground_view/mapの2件差分は保全失敗に数えていない。

限界: 成熟比較は試験が土/舗装へ同じ状態を直接設定した表示比較で、自然成長プレイ実証ではない。既存池は反射対象が少なくほぼ背景。通常画面の構造物反射は承認された表示専用の歩ける水たまり（1.4×0.8m）で確認した。水面y0.006は草根y0.008より下、論理地形/衝突/資源は変更しない。平面固定・床/基壇全除外で任意水中形状のclipはない。反射は追加1scene描画、性能未測定。

製品/docs/票/旧証拠は編集せず独立証拠だけ保存。新プロセスは起動しておらず、編集停止・共有資源返却。受入と美術最終判断は親/ユーザーへ返す。
