# 起動方法

通常ゲームはリポジトリ直下の [`run_game.bat`](../run_game.bat) から起動します。現在は `project.godot` の `main_scene` が `scenes/poc2.tscn` を指しており、PoC2が通常のプレイ対象です。PoC3の機能は未実装です。専用labは比較・確認時に一覧から起動してください。

| 起動ファイル | 用途 |
|---|---|
| [`run_town_lab.bat`](labs/run_town_lab.bat) | 納品モデルの街区を歩き、昼夜・街灯・水面を確認 |
| [`run_vine_compare.bat`](labs/run_vine_compare.bat) | 旧ツタと納品VINの成長表示を比較 |
| [`run_asset_showcase.bat`](labs/run_asset_showcase.bat) | 納品モデルの材質・寸法・影の受け方を展示 |
| [`run_greening_map.bat`](labs/run_greening_map.bat) | 地面・壁面の緑化表示と水面の受影を確認 |
| [`run_vegetation_lab.bat`](labs/run_vegetation_lab.bat) | 植生の生成と成長表示を確認 |
| [`run_light_lab.bat`](labs/run_light_lab.bat) | 太陽角度・点光源の照明と影を確認 |
| [`run_sprite_shadow_lab.bat`](labs/run_sprite_shadow_lab.bat) | 歩行スプライトと投影影の同期を確認 |

旧通常入口 `launchers/run_poc.bat` / `run_poc2.bat` と、旧lab入口 `run_art_study.bat` / `run_quarter_view_lab.bat` / `run_render_study_3d.bat` は整理時に削除しました。いずれも保全タグ `poc2-before-poc3`（`6429634`）から復元できます。対応するシーンや素材は削除していません。既存シーンを直接試す場合は、Godotに `--path C:/godot/greenvader res://scenes/<scene>.tscn` を渡して起動します。

各labは専用確認用で、通常ゲームの設定や保存データを切り替える入口ではありません。履歴の保全は新しい動作検証を意味せず、現在の起動・描画確認状況は[進捗](../docs/STATUS.md)と[検証記録](../docs/VALIDATION.md)を参照してください。

