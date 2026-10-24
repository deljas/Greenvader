# ENV-002 独立静的確認

2026-10-16 / C:/godot/greenvader / HEAD 99013702eaf36db72a64d60d284680fb834f13c5＋共有未コミット差分。作業票と実際の移動前原文/移動後7本を1回照合。

| 対象 | scene | 原文維持 | cwd/--path | scene実在 |
|---|---|---|---|---|
| run_art_study.bat | scenes/art_study.tscn | PASS | PASS | PASS |
| run_greening_map.bat | scenes/greening_map.tscn | PASS | PASS | PASS |
| run_light_lab.bat | scenes/light_lab.tscn | PASS | PASS | PASS |
| run_quarter_view_lab.bat | scenes/quarter_view_lab.tscn | PASS | PASS | PASS |
| run_render_study_3d.bat | scenes/render_study_3d.tscn | PASS | PASS | PASS |
| run_sprite_shadow_lab.bat | scenes/sprite_shadow_lab.tscn | PASS | PASS | PASS |
| run_vegetation_lab.bat | scenes/vegetation_lab.tscn | PASS | PASS | PASS |

原文維持はcwd/--pathの意図した変更以外が一致することを確認したもの。5本は追加cd行と--path置換だけ、greening_map/vegetation_labの2本は元のcd /d "%~dp0"がcd /d "%~dp0..\.."へ変更された。最初の機械比較は全件cd追加と仮定してこの2本を不一致としたため、実際のbefore原文を読んで既存cdの置換であることを確認した（製品不具合ではない）。scene・既存options・%*の有無/内容も保持。%~dp0はbatの所在から解決され、launchers/labs/の2階層上はプロジェクトrootとなるため起動元cwdに依存しない。

- 1対1移動/ルートbatがrun_game.batのみ: PASS。
- run_game.bat不変: PASS。HEAD原文との改行正規化比較および整理前記録SHA256と一致（9cb1dce86c3942e13d8f0787dc67c6199feb03e0be7cde2540ac8d083f122595）。

結論: PASS（失敗なし）。

NOT_RUN: Godot/BAT起動・GUI・OS入力・ゲーム回帰（本作業は静的確認のみ）。docs/tasks/README案内更新は親確認のため対象外。製品ファイルは変更せず、この報告のみ保存。編集停止。
