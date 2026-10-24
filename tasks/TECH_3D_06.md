# TECH-3D-06 分岐ツタ・独立苔/ひび割れ・A屋根復元

## 管理欄
- ID: TECH-3D-06
- 状態: 完了
- 担当ツール: なし
- 担当セッション: なし
- 更新日: 2026-10-16
- 予約中の編集範囲: なし
- 予約中の共有資源: なし
- 最終担当: codex-20261016-branch-moss

## 目的・対象・依存
- ユーザーはTECH-3D-05の仕組みに好感。縦一列のツタを共通部品のまま分岐/横へ広げ、苔を建物と独立させることを依頼。独立したひび割れは低優先、A屋根の簡略化を指摘。優先はツタ分岐、苔、元の屋根の復元。ひび割れは小規模な独立表示例を追加する。
- 共有C:/godot/greenvader、HEAD99013702eaf36db72a64d60d284680fb834f13c5＋既存未コミットART/TECH成果。AGENTS、tasks/README、TASK_TEMPLATE、docs/00〜04/STATUS/DECISIONS、TECH_3D_05を継承。専用labの更新であり通常ゲーム/P2/正式960基準変更なし。

## 編集割当・制約
- 親は設計/票/最終判定。Sol実装はscripts/vegetation_lab/とself_branch*、evidence/vegetation-branches/self/。別Sol検証はindependent_branch*、evidence/.../independent/。Lunaは上記docs/索引のみ。共有ツリーで他編集を戻さず再委任/commit/branch変更禁止。
- 旧render_study_3dやproject.godot、過去証拠、通常ゲーム、画像素材は変更禁止。旧geometryの屋根を読み取り再利用可。現plant_partsの草/葉/茎は使い回す。before原文とhashを残す。
- OS入力送信/前面化/カーソル移動禁止。自動GPUはroot.unfocusable=true＋Hidden、内部UIシグナル/viewport撮影のみ。他者の実行を止めない。Godot資源を競合させない。

## 仕様・合格条件
1. 3棟に共通の生成規則で、幹から左右/斜めに分岐するツタ。各建物で横へ伸びる枝が目視できる。壁のUV/円筒面へ配置し、共通の茎/葉Resourceを共有。枝は親の分岐点が育った後に伸び、浮いた独立枝が先行しない。配置/乱数は固定、同率往復で位置が変わらない。開口/通路を保持。
2. 苔は建物のmesh/基礎材質に焼き込まず、独立ノード/材質/表面パッチなどの層にする。壁足元や屋根などに不規則な広がりを示す。苔ON/OFFと被覆量0〜100をツタの成長率から独立操作。3棟同じ仕組みを使用、曲面に沿う。光は実照明で、広域の明暗は素材へ描き込まない。
3. A屋根は以前の3D試作の欠けたスラブ・破損した立ち上がり・露出鉄筋へ戻す。旧scripts/render_study_3d/ruin_geometry.gdのroofを再利用するか忠実に構成し、平たい箱だけにしない。寸法整合のためAを元の6×4.8×2.8へ戻してよい。植物経路も復元屋根の高さ/形に対応、宙に浮く/空いた欠けを横断する明瞭な不具合を避ける。
4. 低優先のひび割れは小さな独立表面模様層としてON/OFF可能な例だけ追加。実ジオメトリ破壊/穴/物理は対象外。建物の材質/苔/ツタと別操作できる。作り込みを優先しない。
5. 既存[run_vegetation_lab.bat](../launchers/labs/run_vegetation_lab.bat)から同じ3棟比較が開く。成長slider/プリセット/一覧と個別表示を保持、UI追加で被写体/操作が隠れない。640×360 nearest3倍/硬影/輪郭なしを維持。
6. 限定GPU確認:0/50/100とA屋根/分岐の近景、苔単独（ツタ0）とOFF対照、ひび割れ単独/OFFを必要最小限のPNGで確認。枝の親子到達順序/共通Resource/同率復元を別観点でチェック。headless MultiMesh getterは既知の制約につき証明に使わない。動画/全方向/長時間性能/全ゲーム回帰不要。問題修正後は影響のみ再確認。
7. 自己凍結と短い報告→独立検証→親の実差分/画像確認→Luna記録/予約解除。技術検証で美術の最終評価を代行しない。ユーザーが十分と判断した画像案の追加磨き込みはしない。

## 引き継ぎ
- 2026-10-16 親取得。既存Godotプロセスなし。
- 2026-10-16 実装凍結。自己15 PASS / 0 FAIL、GPU2回とも終了コード0（本確認と近景余白のみ再取得）。親が修正後A/C近景・ひび例を目視。source-manifest SHA256=5f127d46f3dc66174150eb56ea94fad753f8719920d04231187f9075ac961187。実装差分・before・証拠はevidence/vegetation-branches/self/。実装担当編集停止、Godotなし。別Solへ限定独立検証を依頼。
- 2026-10-16 独立6 PASS / 0 FAIL / 3 NOT_RUN。実コード/before-after/raw経路/GPU画像を確認、74凍結hash・保全6件一致。追加Godotなし。親は差分・実画像・報告を確認し専用labの限定技術受入を決定。Lunaへ確認済み記録を依頼。
- 2026-10-16 LunaのSTATUS/DECISIONS/ASSETS/VALIDATION/索引更新を親が確認。屋根は新規損傷追加ではなく旧形状復元と記録。全子編集停止、Godotなし、担当予約を解除。専用技術試作として完了、次はユーザー確認。

## 結果・限界
- 共通部品による横枝、親到達後の成長、独立苔ON/OFF・量、独立ひび模様、A旧屋根再利用を実装。主GPUと余白のみ近景GPUは終了済み。
- 証拠: [自己報告](../evidence/vegetation-branches/self/report.md)、[独立報告](../evidence/vegetation-branches/independent/report.md)、[条件別結果](../evidence/vegetation-branches/independent/checks.json)。親は実差分と最終A/C近景・ひび例を確認した。
- 枝は窓/端で止まる簡易方式。Bは除外後+u側のみ。表面定義が必要で任意meshへの自動巻付けではない。苔/ひびは技術用模様、ひびによる物理破壊なし。native/物理入力、独立GPU再実行、全表面・全照明・性能・通常ゲーム回帰はNOT_RUN。
- 次は同じ[run_vegetation_lab.bat](../launchers/labs/run_vegetation_lab.bat)でユーザーが見た目を確認。美術最終評価を代行せず、通常ゲーム/P2/正式960基準は変更しない。
