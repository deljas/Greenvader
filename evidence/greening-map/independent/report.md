# TECH-3D-08 独立限定検証

2026-10-16 / HEAD `99013702eaf36db72a64d60d284680fb834f13c5`＋共有未コミット成果。Windows / Godot 4.7.2。対象manifest SHA256 `5a26c4bb1f73c28bcfeaffaa8890151b81c66bc3415511db0d8cb5c17e8b4f7e`。

**6 PASS / 0 FAIL / 3 NOT_RUN**。独立session実行は1回、内訳7 PASS / 0 FAIL。既存GPU証拠は独立目視し、自己結果と独立実行を区別した。

| 条件 | 結果 | 方法・証拠 |
|---|---|---|
| session_movement_collision | PASS | 独立実行: 1回のheadlessで四方向の閉路と、自己テストと異なる位置から建物東端5.7m・水東端-5.5m・外周9.1mの停止を確認。session-checks.json/headless.log |
| session_scatter_growth | PASS | 独立実行: 種1/水10消費、種は緑化未算入、pause中の歩行/散布、乾燥セル30秒発芽/61秒成熟、実自然伝播、資源ゼロ時不変、直接配列集計。1回7 PASS/0 FAIL、exit0・stderr空。 |
| raw_state_view_counts | PASS | 独立offline: raw5件をterrain target集合とstage配列から再集計。対象1422、緑化12→31→95、成熟12→12→49。非対象不変、表示stage集計、frame/flip/foot同期記録が一致。照明変更前後の成長状態も一致。offline-checks.json |
| input_path | PASS | 実コード+提出GPU証拠レビュー: mapの_input/_unhandled_inputから実sessionへ接続。640 viewport整数stretchによるwindow→logical変換を前提に、GPU testはwindow座標をInput.parse_input_eventへ注入。UI処理後/上下帯・建物AABB・射程/遮蔽判定あり。独立入力再注入ではない。 |
| gpu_visual_and_nearest | PASS | 提出実GPUの独立目視/offline: initial/grown74/sun135/behind UI1920を目視。地面成長、太陽変更に対応する受光/影、建物後方遮蔽を確認。initial_world640/1920は640×360/1920×1080で全画素nearest3一致。 |
| freeze_preservation_logs | PASS | 独立hash/ログ: 指定manifest digest一致、ソース8件・before103件・証拠39件すべて一致。最終self GPU/logicログにエラーなし、GPU exit0/stderr空。自己初回の移動許容/マウス注入失敗は保持済み。hash-checks.json |
| independent_gpu_replay | NOT_RUN | 未実施: 既存GPU証拠が足りるため新規GPU・入力再注入なし。headlessを描画証拠とはしない。 |
| native_physical_input | NOT_RUN | 未実施: BATのnative起動、初期フォーカス、物理キーボード/マウス経路は手動確認へ。OS入力/前面化/カーソル操作なし。 |
| broad_regression | NOT_RUN | 範囲外: 全方向/全位置/全解像度、性能/長時間、通常ゲーム/P2回帰、全地域100%、保存/敵/本番資源循環は未検証。 |

実際の新規session/ground_view/actor/map、scene/BAT、自己テストを読み、既存WorldState/GrowthSim/SpreadSim/PlayState/Landing/Walkerの接続を確認。表示側は実stage/growthを読む。地形の対象区分は見た目から独立しており、太陽方位は照明だけに作用する。

限界: 建物pickは保守的AABBで窓越し等を拒否する。キャラは無受光の仮sprite、光向き影板は体厚を持たない近似。乾燥成熟等は限定地点の確認で、全マップ100%到達の再実証ではない。美術最終承認は代行しない。

独立実行PID33764はexit0。実行後Godotなし。APPDATAは独立profileへ隔離、ゲームデータ/製品コード/docs/票は変更なし。追加GPU・再走なし。凍結照合は一度で完了し、編集停止・共有実行資源返却。最終受入は親判断。
