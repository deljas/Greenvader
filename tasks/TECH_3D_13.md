# TECH-3D-13 納品アセットの展示マップ

## 管理欄
- ID: TECH-3D-13
- 状態: 完了
- 担当ツール: なし
- 担当セッション: なし
- 更新日: 2026-10-17
- 予約中の編集範囲: なし
- 予約中の共有資源: なし（実装・検証のGodot終了確認済み）
- 最終担当: codex-20261017-asset-showcase

## 目的・対象版
- C:/godot/greenvader、HEAD 99013702eaf36db72a64d60d284680fb834f13c5 と既存の多数の未コミット試作を保持。共有作業ツリー。
- 納品元 C:/godot/greenvader_asset_deliveries/assets の6カテゴリから4件ずつ、飛び飛びIDの24モデルを選んだ専用展示マップを作る。地形は単純な床だけ。既存小マップ/通常ゲームは変更しない。
- 納品元は読み取りのみ。必要GLB/metadata/参照テクスチャだけ新規資産フォルダへコピーし、出典とSHA256を記録する。blend全件をコピーしない。

## 選択（実ファイル・indexで存在確認済み）
- BLD: 007,038,079,123
- VIN: 007,032,047,060
- MOS: 003,012,024,035
- TRE: 001,027,054,074
- GND: 009,036,059,077
- PRP: 001,041,075,121

## 編集割当・実行制約
- 実装Sol: 新規資産/専用scripts/scene/launcher、launchers/README.md、tests/asset_showcase/self*、evidence/asset-showcase/self/。実装と自己確認をまとめて担当。
- 別Sol検証: tests/asset_showcase/independent* と evidence/asset-showcase/independent/ のみ。実装の直接修正は禁止し失敗を実装者へ返す。
- Luna記録: 承認済み結果を docs/STATUS.md、VALIDATION.md、ASSETS.md に追記。作業票/索引は親。
- 子からの再委任禁止。他者の変更を戻さない。コミット/ブランチ変更なし。OS入力送信・前面化・マウス移動は禁止。GPU撮影はunfocusableのウィンドウ、必要ならGodot内入力注入のみ。
- 資料: AGENTS.md、tasks/README.md、docs/00_README.md、02_TECH_AND_ART.md、BUILDING_MODEL_GUIDE.md、既存 scripts/greening_map/map.gd と tests/greening_map/model_self_capture.gd。

## 合格条件
1. 全6カテゴリ4件ずつ24件が実GLBとして読込・配置され、ID/名前で識別できる。出典とコピーの一致が確認できる。
2. 640x360/nearest整数倍、正投影30度/45度、輪郭なし。過度な縮尺変更で一画面へ押し込まない。カテゴリ/個別へ移動できるカメラ操作、太陽方位/仰角操作を提供。
3. 主要物が重ならず、地面/樹木/建物の接地を実AABB等で確認。ツタ/コケの壁用には簡単な受け面を置き、必要な向きに設置。地形を作り込まない。
4. GPU実画面で各カテゴリと代表を確認。必要な短い自己確認と独立確認のみ。全角度や全候補を総当たりしない。
5. 専用batはlaunchers/labsへ。既存ゲーム/元納品ファイルは保持。水モデルの既存反射への接続・植物成長・当たり判定・主人公は今回範囲外と明示。

## 終了条件・証拠
- 実装自己報告、対象ソースhash、GPU画像、独立報告を親が確認し、ユーザー起動手順と限界を報告。
- 未検証をNOT_RUNとして区別。ユーザーの美術評価を代行しない。

## 受入と記録
- 2026-10-17: 実装・自己確認完了、実装者終了。自己62 PASS / 0 FAIL / 4 NOT_RUN。最終ソースは evidence/asset-showcase/self/source-hashes.json の66件。
- 独立確認: 6 PASS / 0 FAIL / 4 NOT_RUN。実装・素材・最終GPU画像を確認し、固定66/元コピー57/元GLB baseline24/既存7のhashが一致。独立Godot再実行はなし。根拠: evidence/asset-showcase/independent/report.md と checks.json。
- 親は実ソースと6カテゴリ画像、影修正後のBLD/TRE・低太陽画像を確認。既存7ファイルの保全も自分で照合し、専用展示の合格条件を受入。最終美術承認はユーザー判断。
- 影の初期ぼけをカメラ距離/描画範囲調整で修正し、影響する画像を更新。既存ゲーム・元納品に変更なし。入力はエンジン内注入のみ、Godotプロセス残なし。
- 未検証: 物理入力/配布ビルド、全角度/負荷/残り納品モデル、ゲーム接続（反射・成長・衝突・主人公）、ユーザー美術評価。import/GPUのuser設定・cache保存不可ログは残るが、モデル読込/スクリプト実行の失敗はない。
- 次の一手: launchers/labs/run_asset_showcase.bat でユーザーがモデルを確認。地形作り込みや通常ゲームへの統合は自動開始しない。
- LunaがSTATUS/VALIDATION/ASSETSへ承認済みの記録を反映し、親が内容を確認。実装・検証・記録担当は終了、予約解除。今回の専用展示作成を完了した。
