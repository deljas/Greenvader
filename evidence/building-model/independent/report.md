# TECH-3D-12 独立限定検証

2026-10-16 / HEAD `99013702eaf36db72a64d60d284680fb834f13c5`＋共有未コミット成果。manifest SHA256 `65fe15418708b536994de0d2ef0a96924dd9db75a6472f65d08c0dc09dc5f0f4`。

**5 PASS / 0 FAIL / 3 NOT_RUN**。作業票/実差分、主要製品・生成元/接続metadata、raw/logと代表GPU5枚を確認。Godot再走なし。

| 条件 | 結果 | 方法・根拠 |
|---|---|---|
| model_asset_metadata | PASS | 実GLB/生成元/metadata/読込コード・GPU: GLB2.0/82mesh/83node。実POSITIONとscene変換から独立AABBを算出し記録値と一致、X±3.2/Z±2.8内。ひさし実meshはmetadata UV除外内。窓枠/扉/ひさし/欠損屋根を識別。export→通常scene import→PackedScene読込経路あり。 |
| sparse_growth_openings_coverage | PASS | 実コード/自己raw・代表GPU/別offline計測: 共通Resourceから窓枠沿い＋一部横断枝を生成、扉/ひさしは拡大除外。最大root1、葉0.52/4点ごと・苔span0.40で完成密度を調整。4面の素地分母を独立再計算し保守和24.6/36.0/24.3/28.7%と整合。葉実mesh bbox/茎径0.048/全苔sheetの加算根拠を確認。別の画像壁面差分11.4/15.5/15.3/11.6%は影等込みの補助値で被覆率とはしない。 |
| local_logic_legacy_defaults | PASS | 実差分/自己証拠レビュー: 局所clock/入力/進行加算式は維持、session/地形/counter保全。logic有効13条件と初回FAIL53.1%→影響10PASSを区別。旧default A/B/C layout/pose50/moss signatureは初回3件の一致を確認、最終option内調整後は未再走。GPU全近傍成熟fixtureで45/135秒進行、pause中光操作のwall rawは一致。 |
| cracks_elevation_pixels | PASS | 実コード/実GPU目視/offline: 壁/舗装ひびは独立層・動的受光、舗装幅だけ0.035→0.055m。ON/OFF独立集計は通常640舗装104px/近接640壁180px、通常壁の可視性は目視。仰角5〜85 UI同期/既定52、15/52/80画像で影変化と水反射を確認。代表640→GPU1920全RGBA nearest3一致。 |
| freeze_preservation_runtime | PASS | 独立hash/実ログ: manifest digest一致、source16・保全452・証拠44全件一致。GPU57936 exit0/stderr空。export append/write0、GLB importと最終asset読込成功。import safe-save ERROR1/P2 uid WARNING6を残し、runtimeエラーとは区別。派生sidecar66は親整理対象。 |
| independent_engine_run | NOT_RUN | 未実施: 新Godot/import/再生成/GPU/入力注入なし。自己計測の全leaf-transform和を別runtimeで取り直していない。 |
| native_environment_save | NOT_RUN | 未実施: native/物理入力/保存とeditor safe-save原因の追加調査。OS入力/前面化/cursor/ユーザーGodot操作なし。 |
| broad_geometry_regression | NOT_RUN | 範囲外: 全path/全mesh接触の幾何証明、全角度/夜/多灯、性能/長時間/全ゲーム回帰、任意建物/窓なし面GPU、最終美術評価。 |

根拠詳細: `asset-checks.json`（実GLB頂点/形状）、`offline-checks.json`（画像/面積・raw）、`hash-checks.json`（凍結・保全）。保全照合は一度。

限界: 最大画像は試験で根元近傍を成熟させたfixtureで自然拡張の到達画像ではない。被覆の自己値は窓穴を除いた壁面に対する重複込み保守面積上限で、画像の緑画素率ではない。独立画像差分も植物影/境界の変化を含み、正確な被覆面積の代替ではない。仕様を変更した箇所や明確な未解消製品不具合は見つからなかった。

独立証拠のみ保存。製品/docs/票/他者差分・sidecarは編集なし。新プロセスなし、編集停止・資源返却。最終受入/美術判断は親/ユーザーへ返す。
