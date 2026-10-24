# ENV-002 launcher organization self report

Seven prototype launchers moved from repository root to launchers/labs. Each now sets cwd and --path to "%~dp0..\..". Static resolution from its actual destination equals C:/godot/greenvader. Original scene/options/%* start lines were preserved byte-for-byte apart from --path substitution. Before originals are in before/.

| Launcher | Existing scene | Static check |
|---|---|---|
| run_art_study.bat | scenes/art_study.tscn | PASS |
| run_quarter_view_lab.bat | scenes/quarter_view_lab.tscn | PASS |
| run_render_study_3d.bat | scenes/render_study_3d.tscn | PASS |
| run_sprite_shadow_lab.bat | scenes/sprite_shadow_lab.tscn | PASS |
| run_light_lab.bat | scenes/light_lab.tscn | PASS |
| run_vegetation_lab.bat | scenes/vegetation_lab.tscn | PASS |
| run_greening_map.bat | scenes/greening_map.tscn | PASS |

All source/destination absolute paths were checked within the workspace before Move-Item -LiteralPath. No destination existed; none was overwritten. Root now contains only run_game.bat; its SHA256 is unchanged: 
9CB1DCE86C3942E13D8F0787DC67C6199FEB03E0BE7CDE2540AC8D083F122595
.

No Godot, GUI, OS input, or test execution. No docs/source/scene/project edits. Editing stopped.
