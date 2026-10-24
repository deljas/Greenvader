# 小マップ建物モデルガイド

このガイドはTECH-3D-12のRuinHouse 1棟を再生成・小マップで使用するための補助資料です。任意形状のGLBを自動解析して植生接続する一般仕様ではありません。

## 資産と座標

- GLB: [`ruin_house.glb`](../assets/models/ruin_house/ruin_house.glb)、Godotコード生成の82mesh/83node。生成元、材質、形状、接続metadata、再生成手順は[資産README](../assets/models/ruin_house/README.md)を参照。
- 単位はm、Y軸が上。原点は足元矩形の中心。主要壁寸法は幅6.0 × 奥行4.8 × 高さ2.8m。
- 通常import後の全mesh AABBはmin `(-3.175,-0.06,-2.56)`、size `(6.345,3.509645,5.355)`。既存小マップAの基壇範囲内に収まり、配置Yは既存互換の+0.12m。
- 建物内に地面、衝突、植生、焼込み光/影は含まない。旧Aと生成元は保全。

## 植生の接続

小マップ専用のattachments metadataが壁面chart、開口、ひさし、通路を指定し、共通のツタ/苔部品をそこから派生します。窓枠沿いの経路と一部窓面を横切る短い枝を含み、扉・ひさしから余白を取ります。窓なし面用の曲がる共通経路もあります。屋根植生は対象外です。

既存コードは独立meshの表面/開口/ひさし情報を使うため、新しいモデルを追加する場合は対応するmetadataと接続設定が必要です。mesh形状から面や通行可能範囲を推測する機能、任意モデルへの自動巻付けはありません。今回の最大成長はprogress 1のままで、疎な見た目は葉scale、配置間隔、苔spanで調整します。被覆上限と検証上の注意は[TECH-3D-12検証記録](VALIDATION.md#tech-3d-12-建物モデル植生接続と仰角操作)を参照してください。

## 再生成・確認

リポジトリのルートから[資産README](../assets/models/ruin_house/README.md)記載のGodot `--script` exportと`--editor --import`コマンドを実行します。GLB import時にはeditorログに既知のsafe-save ERRORと既存P2 uid cache warningが記録されています。GLBのimport/runtime成功とログ全体がエラーなしであることは区別してください。

手動確認は既存の[`run_greening_map.bat`](../launchers/labs/run_greening_map.bat)を使います。壁面成長、壁/舗装ひび、太陽仰角の表示を確認する専用小マップで、通常ゲームのモデル統合ではありません。検証済み範囲とNOT_RUNは[TECH-3D-12検証記録](VALIDATION.md#tech-3d-12-建物モデル植生接続と仰角操作)に記載しています。最終美術評価はユーザー判断です。
