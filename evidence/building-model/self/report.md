# TECH-3D-12 自己報告

対象: HEAD `99013702eaf36db72a64d60d284680fb834f13c5` ＋共有未コミット成果。2026-10-16、Sol実装。製品・asset・テストの編集停止、[source-manifest.json](source-manifest.json)の16件で凍結。原本はbefore/、[実差分](implementation.patch)、保全452/452件SHA一致は [integrity.json](integrity.json)。session/actor/world/play/data、水面、既存建物定義・生成元・素材は変更なし。

変更は新AのGLB/接続metadata/再生成元、mapのモデル読込・仰角UI、壁成長controller、共通植生2コードのoption拡張、独立壁ひび、舗装ひび幅。既存Aの基壇・論理衝突・地形はそのまま。

## モデルと植生

Godot GLTFDocumentで82meshの自作建物をGLBへ書出し、Godotの通常asset importを通したPackedSceneを小マップAへ読み込む。単なるruntime建物生成の追加ではない。窓の凹み/枠/桟、閉じた扉、ひさし、実際に欠けた屋根スラブ/分割パラペット/鉄筋を含む。旧屋根assetは残す。exportはappend/writeともOK、imported mesh AABBはmin(-3.175,-0.06,-2.56)、size(6.345,3.509645,5.355)で基壇X±3.2/Z±2.8内。足元中心原点、m単位、小マップではY+0.12。詳細/再生成手順は [資産README](../../../assets/models/ruin_house/README.md)（リポジトリの `assets/models/ruin_house/README.md`）、[GLB inspection](glb-inspection.json)。APIは [Godot GLTFDocument公式](https://docs.godotengine.org/en/stable/classes/class_gltfdocument.html)を参照。

小マップ専用のsparse_windows option。表面/開口/ひさしから共通処理で幹・枝を派生させ、個々の葉や段階別モデルの手配置はしない。窓枠以外では曲がりを加え、窓端を横断する短い枝が一部のガラスにかかる。扉・ひさしは葉半径を考慮した余白で避ける。窓なし表面には共通の曲がる代替経路を持つ（今回のA/B GPUは窓ありの可視2面のみ）。既存共通葉/茎Resourceを使用、地面草の重複/屋根植生はなし。最大root進行は1のまま、葉scale0.52/4点毎の葉、コケspan0.40で完成密度を調整。局所地面と既存clockによる遅延成長を維持する。

壁面被覆は画面全体の緑率でなく、各可視面の素地面積（幅×高さ−開口面積）に対する保守的な上限を計測した。完成時の各葉の実meshをCPUの描画transformで表面UVへ投影し、その外接矩形面積を全加算。さらに茎の全長×最大径0.048とコケの全シート幅×高さを加算する。重なり、窓上、壁外、shader discardを差し引かないため実被覆より大きい上限。最大被覆上限はA前24.6%/右36.0%、B前24.3%/右28.7%（[logic-raw](logic-raw.json)）。各面64%以上の素地が残る安全側の配置で、GPUでも壁材質・窓・扉が読めることを自己/親目視。数値は投影/表面面積の上限で、美術評価を代行しない。

## 検証と初回失敗

- logic初回 **12 PASS / 1 FAIL**。A右面の上限53.1%で余白条件FAIL。旧A/B/C default生成/50%成長/苔配置signatureは全一致。原結果を [initial/](initial/) に保持。
- 葉量・苔幅と曲がる経路をまとめて修正し、影響対象logic **10 PASS / 0 FAIL**。旧default比較3件は未再走（修正は専用option内）。有効な一意logic条件は **13 PASS / 未解消FAIL 0**。初期0/共通資源/窓部分重なり・扉ひさし回避/局所clock・counter不変/4面上限/仰角UI同期・成長不変。詳しくは [結果](logic-results.json)、[raw](logic-raw.json)、[ログ](logic.log)。
- 実GPUはVulkan Forward+ / RTX 5070 Ti、限定1runで **5 PASS / 0 FAIL** ([結果](gpu-results.json)、[raw](gpu-raw.json)、[ログ](gpu.log))。0/45/135秒、仰角15/52/80度、ひび独立ON/OFFを取得。1枚で640→GPU1920の全画素nearest3倍一致。
- 舗装のひびは全幅0.035→0.055m、生成位置/成長/草候補は不変。通常640のON/OFFで104画素差。壁の独立ひびは全幅0.055m、受光・cast OFF。壁180画素差は **A近景640** の値で、通常構図での量ではない。通常640でのひび可視性は自己/親の画像目視として区別する。太陽角度で明暗が変わっても材質の線として残る。

## 代表画像・操作

- [初期](model_initial_ui_1920.png)、[45秒](model_growth45_ui_1920.png)、[135秒最大](model_growth135_ui_1920.png)。GPU比較の地面は試験内で固定近傍だけ成熟させ、その後実時計を進めたもの。
- [窓/ひさし/壁ひび近景](A_window_cracks_closeup_ui_1920.png)、[同ひびOFF](A_wall_cracks_OFF_ui_1920.png)。近景は証拠用カメラのみ変更、通常操作構図は変えない。
- [仰角15°](elevation15_ui_1920.png)、[80°](elevation80_ui_1920.png)。建物/sprite影の長さ・水受影/反射を含め表示が変化。成長停止・内部stateは不変。

起動は既存 `launchers/labs/run_greening_map.bat`。2行目の方位/仰角をsliderか数値で操作。仰角は5〜85°、既定52°、見た目のみ。従来の歩行/散布/補給/成長停止は維持。

## import記録・停止・限界

GLB export成功後、headless editor importは終了code0、GLB import完了。ただし [import.log](import.log) 冒頭にeditor safe-save ERROR、および既存P2 uid6件のcache再生成warningがある。成功GPUログのエラーと混同せず、全ログerrorなしとはしない。PNG等の再importとuid追加を含む派生sidecar66件は [import-sidecars.json](import-sidecars.json) に一覧/hashを記録し、所有外のため未削除（親の整理対象）。元ファイルの保全hashは全一致。新モデル自身のimport設定/生成元uid等は凍結manifestへ含めた。

自動GPUはroot.unfocusable=true、Start-Process -WindowStyle Hidden、内部Control信号/状態操作とviewport取得のみ。APPDATAは本証拠配下profile。OS入力・前面化・カーソル操作なし。自己GPU PID57936は自然終了exit0 ([process.json](process.json))、最終確認時Godotプロセスなし。実行資源返却・編集停止。

NOT_RUN: native/物理入力、全角度・夜・多灯、性能/長時間、保存、通常ゲーム回帰、任意建物自動解析、窓なし面のGPU、最終美術評価。到達点は1棟の実モデル制作→import→植生接続の工程確認。独立確認・最終受入は親担当。
