# TECH-3D-06 限定独立確認

対象: HEAD `99013702eaf36db72a64d60d284680fb834f13c5`＋凍結未コミット差分。Windows。提出GPUはGodot 4.7.2 / Vulkan Forward+ / RTX 5070 Ti。作業票/README/TASK_TEMPLATE/自己報告、実before/after・取得コード・raw経路・代表GPU画像を照合し、Python/Pillowで経路/画素/hashを独立検査した。**6 PASS / 0 FAIL / 3 NOT_RUN**。自己15 PASSは独立実行結果として合算しない。

| 条件 | 結果 | 確認できた事実 |
|---|---|---|
| 共通部品の分岐・親接続・成長順・横展開 | PASS | raw位置からEuclidean距離を再計算。A/B/C枝10/8/94、親junctionとの隙間0、startと根元から親junctionへの実距離の最大誤差約4.8e-8、全点距離の誤差約8.4e-8以下。UV横幅0.51/1.02/1.36、実水平弦長0.51/1.02/1.49。共通の進行距離から枝startを差し引くコードなので親到達前に可視の枝が先行しない。4段階素材でなく同じResource/固定候補を使う。rawの葉/茎Resource IDも3棟で一致。0/50/100 GPUと近景に横枝が見える。 |
| 独立した苔量・ON/OFF | PASS | 苔は建物基礎材質を変えない別sheet/node/materialで、量UIは苔uniformだけを変える。成長0のworld画像を独立比較し苔100は6,091画素変化、量0とOFFは基準と完全一致。C曲面/屋根と壁足元にも不規則な模様を目視。 |
| A旧屋根の再利用と経路 | PASS | 旧Geometry.buildのroofノードをそのまま取り出し、残りの一時建物をfree。旧geometry自体は不変。A寸法6×4.8×2.8、欠けたslab/破損立上り/鉄筋を最終近景で確認。経路は立上りを越え、鉄筋を除いた屋根三角形の支持高さを使い、支持がなければ停止するコード。明瞭な欠け横断/浮いた枝は代表画像で見られない。全頂点の厳密な接触計測ではない。 |
| 小さな独立ひび模様 | PASS | 苔/ツタと別node/material/checkbox、影cast OFF。基準worldに対しONは19画素変化、OFFは完全一致。小さな表示例に限定し、ジオメトリ破壊ではない。 |
| UI余白・表示・代表nearest3倍 | PASS | 修正後A/C近景の選択建物の屋根が2行UIより下に収まる。既存scene/batは不変。成熟worldとA/CのUI、計3組の640×360→1920×1080が全画素最近傍3倍一致。UI1920はGPUroot640のCPU拡大、world1920は実GPU別viewport。 |
| 凍結・before/after・保全・最終ログ | PASS | source/evidence計74hashは凍結版・開始/終了で一致。before原文全件は前回独立hashと一致。実差分は既存4ファイルの更新と新規layer/shader/撮影コード。読取専用6件は不変。main/closeupの両GPU終了0、stderr空、ログにERRORなし。 |
| 独立GPU/エンジン/実instance再実行 | NOT_RUN | 不要な再走なし。既知invalidのheadless MultiMesh getterも使っていない。成長順はraw幾何＋コードの進行則、同率復元はコードと提出GPU結果のレビューであり独立動画計測ではない。 |
| native・初期フォーカス・物理入力 | NOT_RUN | 提出GPU viewport画像の確認に限定。OS入力/前面化/カーソル操作なし。 |
| 全表面/照明・性能・ゲーム回帰 | NOT_RUN | 開口/通路は代表GPUで保持を確認する限定範囲。動画/総当たり/長時間試験/通常ゲーム回帰なし。 |

Bの実枝は開口除外の結果+u方向だけとなるが、共通生成は左右を試み、各建物の横展開は確認できる。枝は開口/端で停止し迂回しない。A支持判定は最高三角形とクリアランスを使う近似で、任意meshへの完全な巻付けではない。苔/ひびも小分割面の技術用模様。美術の最終評価はユーザーへ残す。

source-manifest SHA-256: `5f127d46f3dc66174150eb56ea94fad753f8719920d04231187f9075ac961187`。数値・開始hashはoffline-checks.json、条件別判定・最終hashはchecks.json。新しいFAILは発見しなかった。製品/共有docs/票は変更せず独立報告のみ保存。Godotを起動せず、終了時Godot 0件。編集停止・資源使用なし、最終受入を親へ返す。
