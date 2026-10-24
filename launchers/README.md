# 起動方法

通常ゲームはリポジトリ直下の [`run_game.bat`](../run_game.bat) から起動します。専用試作は次の一覧から選んでください。ランチャーは `launchers/labs/` にあります。

| 起動ファイル | 用途 |
|---|---|
| [`run_poc2.bat`](run_poc2.bat) | 第二弾PoC。224×224セル、共通種・化石・栽培5種・おたすけ3種。WASD/矢印、左=種、右=水、Q=たいあたり、R=バズーカ、M=時間停止マップ、F1=説明、F5=保存、N=音。専用保存先 `user://poc2_saves/` |
| [`run_poc.bat`](run_poc.bat) | 3DクォータービューPoC。起動時にタイトル（新規開始／続きから／操作説明）。WASD/矢印で歩行、左クリックで種・右クリックで水、F2で640×360/960×540切替、Escでポーズメニュー（再開・保存・読込）、F5で保存。保存先は PoC専用の `user://poc_saves/`（旧セーブとは別） |
| [`run_town_lab.bat`](labs/run_town_lab.bat) | 納品モデル7棟の小街区を仮人間で歩行。昼夜・街灯・4水面、追従/全景 |
| [`run_vine_compare.bat`](labs/run_vine_compare.bat) | 旧ツタと納品VINのID切替・同期推定成長。外部フォルダ再読込、共通ズーム、太陽・受け面 |
| [`run_asset_showcase.bat`](labs/run_asset_showcase.bat) | 納品6カテゴリ各4件、計24件の展示。カテゴリ/個別選択、カメラ移動、太陽方位・仰角 |
| [`run_greening_map.bat`](labs/run_greening_map.bat) | 小マップで歩行、地面緑化表示、太陽方位を確認 |
| [`run_vegetation_lab.bat`](labs/run_vegetation_lab.bat) | A/B/C建物の植生、ツタ・苔の成長表示を確認 |
| [`run_light_lab.bat`](labs/run_light_lab.bat) | 太陽角度と周回点光源の照明を確認 |
| [`run_sprite_shadow_lab.bat`](labs/run_sprite_shadow_lab.bat) | 仮歩行spriteと3D投影影の同期を確認 |
| [`run_render_study_3d.bat`](labs/run_render_study_3d.bat) | 低解像度3Dと朝・昼・夕の影を確認 |
| [`run_quarter_view_lab.bat`](labs/run_quarter_view_lab.bat) | クォータービュー投影・移動・遮蔽を確認。`--1080`で1920×1080を起動 |
| [`run_art_study.bat`](labs/run_art_study.bat) | 草地と樹木の密度A/Bを比較 |

各試作は専用の確認用です。通常ゲームの設定や保存データを切り替えるランチャーではありません。

