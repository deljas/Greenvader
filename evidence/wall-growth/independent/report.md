# TECH-3D-11 独立限定検証

2026-10-16 / HEAD `99013702eaf36db72a64d60d284680fb834f13c5`＋共有未コミット成果。凍結manifest SHA256 `6e155b63a50a5410ad6c38fdde4dbaf7cf1812de53d2a60e914ec02dcdbdce07`。

**6 PASS / 0 FAIL / 3 NOT_RUN**。実差分・製品5件・自己試験経路・rawと代表実GPU7枚を確認。独立Godot実行なし。

| 条件 | 結果 | 方法・根拠 |
|---|---|---|
| local_input_growth | PASS | ソース/実GPU/独立offline: 初期0、45→135秒でA前面だけ成長を目視。代表root2/moss2のcellsは基壇外・半径0.65m内で、明示成熟fixtureから期待した入力と45/135秒進行が一致。右面/別棟21記録は0。 |
| clock_state_preservation | PASS | 実clock接続/自己証拠レビュー: session実growth_tickedへ接続し0.5ゲーム秒ごと、Sessionは0.25秒分割で先に実GrowthSimを更新。描画/光では進まない。分母1422固定、fixture後の緑44は45→135秒で不変。pause中の全wall rawも光/反射操作前後で一致。自己17PASSのloss保持/再開・土舗装同等もコードと整合。 |
| branches_resources_exclusions | PASS | 実ソース/代表画像: 幹/枝は同rootのtravelと親junctionの累積距離で順序制御。共通mesh再利用、苔はpatch別material複製。walls_onlyで上端0.34m手前、既存開口marginを保持。屋根/追加地面草/ひびは無効。窓/扉/屋根を代表GPUで確認。 |
| legacy_defaults | PASS | 実before/after/自己signatureレビュー: options既定値は旧挙動、root metadataはpathsと別。旧原本と新defaultのA/B/C layout/pose50/moss signatureの各一致を確認。旧lab全走行の代用ではない。 |
| water_shadow_pixel | PASS | 提出GPU目視/独立offline: 反射OFFでcaster ON/OFFを比較。独立に選んだ池内ポリゴンで42px暗化（RGB和8549<12348）、caster OFFの反射差745px、太陽225→270で82px差。岸から水へ影が続き反射も維持。代表640/1920は全RGBA画素nearest3一致。 |
| freeze_preservation | PASS | 独立SHA256/実ログ: 親指定manifest digest一致、source7件・保全117件・証拠39件全件一致。self GPU PID27960 exit0/stderr空、logic/GPUログにERRORなし。 |
| independent_engine_run | NOT_RUN | 未実施: 既存実GPU/raw/実ソースで足りるため新Godot実行・独立入力再注入・再GPUなし。自己17logic/6GPUはレビュー結果として区別。 |
| native_physical_save | NOT_RUN | 未実施: native/フォーカス/物理入力・保存。OS入力/前面化/カーソル/ユーザーGodot操作なし。 |
| broad_generalization | NOT_RUN | 範囲外: 全角度/全map/全raw位置/全branch mesh境界の網羅、長時間/性能/全ゲーム回帰、美術最終承認。屋根接続は次段階。 |

数値は `offline-checks.json`、凍結/保全は `hash-checks.json`。水の独立計測は目視で内側へ取ったpolygonを使用し、自己の投影helper/池全体57pxとは範囲が異なる。

限界: GPUの壁緑化は前面成熟地面を直接配置したfixtureで、自然拡張が到達した画像ではない。種散布→発芽→実clock接続は自己logicの実コード/ログで確認した。地面入力は速度だけを変え、減少時は停止保持。水は現太陽1灯のATTENUATIONを42%下限で適用する簡易材質で汎用PBRではなく、追加反射描画コストは未測定。建物A/B可視2面の固定試作。

独立証拠のみ保存、製品/docs/票/他者差分は編集なし。新プロセスを起動せず、編集停止・資源返却。最終受入は親、最終美術評価はユーザーへ返す。
