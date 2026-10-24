# TECH-3D-13 独立検証

- 対象: HEAD `99013702eaf36db72a64d60d284680fb834f13c5` + 共有未コミット差分。固定対象は `self/source-hashes.json` の66件。2026-10-17。
- 環境: Windows / バンドルPython・Pillow。提出GPU画像の環境はログからGodot 4.7.2 / Vulkan Forward+ / NVIDIA RTX 5070 Tiと確認した。独立Godot起動・import・GPU再撮影は実施していない。
- 根拠: 作業票の合格条件、実装 `scripts/asset_showcase/showcase.gd` 全文、専用scene/bat/manifest、元GLB・metadata・参照PNG、親baseline、最終GPU画像を直接確認。実装者の報告だけで合格としない。
- 結果: **6 PASS / 0 FAIL / 4 NOT_RUN**。美術品質の最終承認は含めない。

| 条件 | 判定 | 確認根拠・限界 |
|---|---|---|
| 6カテゴリ各4件、飛び飛びID、実GLB、出典一致 | PASS | 指定24IDがmanifestと一致。全24GLBのGLB2ヘッダ・実mesh node・参照画像の存在を独立解析。57件の元ファイル/コピー/記録SHA256がすべて一致。 |
| 640×360・整数nearest・正投影30°/45°・輪郭なし | PASS | AA/TAA無効・nearest・整数stretch・固定カメラを実ソースで確認。最終カテゴリ画像全6枚は1920×1080で各3×3画素が同色、rawは640×360。アウトライン追加なし。 |
| 元縮尺、配置、接地、壁/床受け面、簡単な地形 | PASS | scale変更/縮小コードなし。剛体の実mesh AABB下端を床Y=0へ移す処理を確認。植物は元Y-upを維持。窓ツタの開口、VIN-060ひさし、MOS-012内角、MOS-035根元曲面をmetadataと照合。最終6枚で4件ずつ分離し、接地と受け面を確認。小さい地表コケは個別画像でも確認。runtime AABB計測の独立再実行はしていない。 |
| カテゴリ/個別、カメラ移動/ズーム、太陽方位/仰角操作 | PASS | OptionButton/キーとfocus処理、WASD/矢印、Q/E/ホイール、スライダー0〜360°・5〜85°から光方向への接続を実ソースで確認。カテゴリ全景6枚・MOS-003個別・BLD-123の320°/52°と225°/15°で異なる明暗/影を画像確認。入力コードと提出結果の整合を確認した範囲。 |
| GPU実画面で各カテゴリ/代表と硬い影を確認 | PASS | `self/*_category_ui_1920.png` 6枚、`MOS003_individual_ui_1920.png`、`BLD123_sun52_ui_1920.png`、`BLD123_sun15_ui_1920.png`を独立目視。最終TREで葉と枝の影の輪郭が明瞭、建物影も明瞭。初期長距離カメラ画像は最終根拠から除外。美術の良し悪しの承認ではない。 |
| 専用入口、通常ゲーム/元納品の保全と範囲の明記 | PASS | `launchers/labs/run_asset_showcase.bat` と起動一覧、展示READMEを確認。元GLB24件が親取得baselineと一致、既存7件も一致。水反射・成長・衝突・主人公は展示へ接続されておらずREADMEに範囲外と明記。 |
| 独立Godot再起動/実入力経路/配布ビルド | NOT_RUN | 主要な懸念がなく提出GPU画像と実ソースの確認に限定。OS入力・前面化・カーソル操作なし。ゲーム実行ファイルへの書き出し確認もなし。 |
| 全角度・性能負荷・全納品モデル | NOT_RUN | 今回の24件と提出代表画像のみ。総当たりなし。 |
| 反射/植物成長/当たり判定/主人公/通常ゲーム統合 | NOT_RUN | 作業票で範囲外。水たまりは納品材質の展示。 |
| ユーザーの最終美術評価 | NOT_RUN | ユーザーが展示を確認して判断する。 |

## 照合と実行記録

`tests/asset_showcase/independent_verify.py` をバンドルPythonで1回完走。`checks.json` にファイルhashと集計を保存。

- 固定ソース66件: 全一致。
- 元コピー57件: 全一致（GLB24 / metadata24 / PNG9）。
- 親取得の元GLB24件baseline: 全一致。
- 親取得の既存7件baseline: 全一致。
- 実GLB解析24件、最終カテゴリ画像の整数3倍検査6枚: 不一致なし。
- 固定manifest SHA256: `fb46b0aba674944455764be6dc79abc9e41ef3a4b5d832f1987a6a8d9c40577d`。
- 初回はシステムPythonにPillowがなく実行前importで終了。その後、既存バンドルPythonへ切り替え正常完了。追加インストールなし。
- 提出GPUログにuserログ/シェーダcache書込不可ERRORがある。画像が出力されていることと、ログが完全無エラーであることは区別する。
- ゲームコード・設定・素材・元納品は編集していない。独立テストと本証拠のみ新規作成。
- 自分が起動したGodotプロセスは0件。終了時 `Get-Process -Name '*Godot*'` に該当なし。CIMの詳細取得は権限不足だったため使用していない。import/GPU実行権を親へ返す。

最終受入は親が判断する。
