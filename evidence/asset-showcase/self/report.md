# TECH-3D-13 実装自己報告

- 対象版: HEAD `99013702eaf36db72a64d60d284680fb834f13c5` + 多数の既存未コミット差分を保持した共有ツリー。今回の凍結範囲は `source-hashes.json` の66ファイル。
- 実装: 6カテゴリ各4件、計24件を納品GLBそのものとして配置。元縮尺、Y-up維持。実mesh AABBで接地、壁/窓/ひさし/内角/根元曲面はmetadataを参照した簡単な受け面。
- コピー: GLB24 / metadata24 / PNG9、計57件。出典、SHA256は `assets/models/delivery_showcase/manifest.json`。最終凍結時も元とコピー57件すべて一致。元納品は編集しない。
- 変更: `scripts/asset_showcase/showcase.gd`、`scenes/asset_showcase.tscn`、`assets/models/delivery_showcase/`、`launchers/labs/run_asset_showcase.bat`、`launchers/README.md`、`tests/asset_showcase/self*`。通常ゲーム・既存小マップの実装は編集していない。

## 検証と結果

- Godot4.7.2 importはexit0、全24GLBの通常import後runtimeで読込成功。importログにはサンドボックス内のRoaming/Godotの作成・設定保存不可ERRORあり。エラーログ完全ゼロという意味の合格ではない。
- RTX5070Ti / Vulkan Forward+ の実GPU、unfocusableウィンドウで撮影。OS入力・前面化は行わず、入力確認は `Input.parse_input_event` のみ。
- 最終自己GPU: **62 PASS / 0 FAIL / 4 NOT_RUN**。24件mesh存在/scale1と接地、6カテゴリのUI、個別選択、整数nearest3の画像byte一致、カテゴリキー・カメラ移動・ズーム、太陽方位/仰角の描画変化、正投影30度。
- 6カテゴリの最終GPU画像を目視し、4件ずつの形状、接地、受け面と向きを確認した。細かい美術品質の承認はユーザー判断。
- `self_freeze.py`: 元/コピー57件再一致、カテゴリ件数6×4、66ソースhashを取得。
- 初回GDScriptのfloat.snapped API誤記はsnappedfへ修正。長いID名が選択欄の最小幅を押し広げる点をclip/固定幅で修正後、影響するUI画像を再取得。
- 親の目視で初回の影のぼけを指摘。カメラoffset100 / far2000 / shadow距離160から、既存小マップと同じoffset22、far120 / shadow距離90へ変更。代表TREで硬い葉・枝影へ戻ることを確認し、影響する6カテゴリと代表画像を更新した。初期の比較用画像は `TRE_initial_long_camera_640.png` に保持。最終結果は修正後の対象に対するもの。
- GPUログのuserログ/シェーダcache保存不可ERRORは残るが、runtimeのSCRIPT ERRORやアセット読込ERRORはない。

## 証拠

- `gpu-results.json`: 最終62チェック、adapterとNOT_RUN。
- `placements.json`: 24件の実AABB、配置、元縮尺、mesh数。
- `*_category_640.png` / `*_category_ui_1920.png`: 6カテゴリ各4件。
- `MOS003_individual*`: 小さい地表コケの個別フォーカス。
- `BLD123_sun52*` / `BLD123_sun15*`: 太陽スライダーによる変化。
- `source-hashes.json`: 凍結ソース66件。
- `import.log` / `gpu.log`: 実行ログ。

## 操作・限界

`launchers/labs/run_asset_showcase.bat`から起動。カテゴリとIDを上部で選択し、WASD/矢印でカメラ移動、1〜6でカテゴリ、Tabで次の部品、Q/Eまたはホイールでズーム、Rでカテゴリ全景。太陽方位0〜360°・仰角5〜85°。

NOT_RUN: 物理キーボードからOSを経た入力、全角度/性能負荷、反射・緑化・衝突等のゲーム接続、最終美術評価。水面は納品材質の展示だけで既存小マップの反射材質へは未接続。キャラ/衝突/ゲーム進行なし。地形は単純な床。

実行したGodotプロセスは終了済み。import/GPU実行権を解除して親へ引き渡す。
