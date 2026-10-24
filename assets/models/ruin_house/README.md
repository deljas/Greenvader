# RuinHouse / TECH-3D-12

ローカル自作のコード生成GLB。AI画像・外部モデル・Blenderは使用していない。壁、窓の凹みと枠、閉じた金属扉、扉ひさし、欠けた屋根スラブ、分割パラペット、露出鉄筋を別meshで保持する。StandardMaterial3Dの素地色と実ライトを使い、光や影の焼込みはない。モデル内に植物・地面・衝突は含めない。

- 単位: m、Y上、足元矩形中心を原点。主要壁は幅6.0 × 奥行4.8 × 高さ2.8。
- import後の全mesh AABB: min(-3.175,-0.06,-2.56)、size(6.345,3.509645,5.355)。既存A基壇のX±3.2 / Z±2.8以内。小マップでは既存どおりY+0.12に置く。
- 接続データ: `attachments.gd`。既存Aの表面chart・開口・通路を継承し、扉ひさしのUV除外領域を追加。任意meshから自動抽出しない。
- 植物: 共通generatorが表面/窓/扉/ひさしから疎な経路を派生。個々の葉や成長段階専用assetは持たない。屋根植生は対象外。

リポジトリルートを作業ディレクトリとして再生成:

```powershell
& C:/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://scripts/model_build/ruin_house_export.gd
& C:/godot/Godot_v4.7.2-stable_win64_console.exe --headless --editor --path . --import
```

通常確認は `launchers/labs/run_greening_map.bat`。旧植生labのA生成元/屋根は保全している。本資産は工程確認用の小モデルで、完成美術や任意モデル対応ではない。
