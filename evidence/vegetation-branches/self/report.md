# TECH-3D-06 self report

Target: HEAD `99013702eaf36db72a64d60d284680fb834f13c5` plus shared prior uncommitted work, 2026-10-16. Isolated vegetation lab only; final acceptance belongs to parent/independent verifier.

Changes: `building_defs.gd`, `building_geometry.gd`, `growth_patch.gd`, `lab.gd`; new `surface_layers.gd`, `moss.gdshader`, `cracks.gdshader`; new `self_branch_capture.gd` and `self_branch_closeups.gd`. Same scene and `run_vegetation_lab.bat` entry. `before/` preserves all original vegetation scripts plus project/scene/bat/old geometry, with SHA in `before-manifest.json`. `implementation.patch` is the limited before/after diff. No old render-study or normal-game edit.

## Behavior

- Fixed trunk samples generate diagonal branches in both UV directions. Each branch begins at the exact parent sample and inherits the measured root-to-junction length as its start distance. Shared global distance advances the parent first and then its branches. Branches stop before expanded opening rectangles and surface edges; no rerouting or recursive generations. A/B/C have 10/8/94 branch paths respectively, with maximum lateral reach 0.51/1.02/1.36 world UV units. The same grass/leaf/stem mesh and material Resources remain shared; `plant_parts.gd` is unchanged.
- Moss is an independent set of small tessellated surface sheets, common generation/material for all buildings. Its checkbox and 0–100 amount slider/SpinBox are independent of plant growth. The moss shader discards an irregular area of each patch, receives real light, and casts no shadow. Wall and roof charts include cylinder/cone curvature. The shader is a technical pattern, not final moss art.
- Cracks are a separate receiving-only pattern layer with a separate material and checkbox. It neither changes the wall base material nor removes geometry. Small fixed examples only; no destruction simulation.
- A is restored to 6×4.8×2.8. Its window/door/corridor data were adjusted accordingly. The old `OldGeometry.build()` roof node is detached intact, and the temporary remaining old building is freed. This restores the exact missing-corner slab, broken parapets and rebar, instead of approximating them with a flat box. Plant routes climb the parapet and query the extracted roof's triangles for support height; a missing support stops the route. Rebar is excluded from support sampling.
- Original growth/presets/view selector remain in row 1; moss and cracks occupy row 2. Individual A/B/C cameras reserve room above the main building for both rows. Initial A/C framing overlapped the top of the roof; only those close views were recaptured after a small camera framing adjustment. Initial views remain under `initial/`.

Use the same BAT, adjust growth, toggle moss or set its amount, and toggle the independent crack example. Default growth=50%, moss=60% ON, cracks OFF. The UI and world use 640×360 with integer nearest display to 1920×1080. No video, auto-growth or additional lighting controls were added.

## Limited verification

`results.json`: **15 PASS, 0 FAIL** on Vulkan Forward+ / NVIDIA GeForce RTX 5070 Ti. `path-snapshot.json` records actual parent/junction/distance/UV/positions and shared resource IDs for independent review. Checks cover same-rate CPU pose/layout restoration; actual shared mesh/material object identity; exact parent junctions and independently accumulated parent segment lengths; horizontal reach; independent moss and cracks GPU changes; moss amount 0 and both OFF images exactly matching the unmodified world baseline; one full-byte GPU nearest3 comparison. No headless MultiMesh getter is used as proof. These are self checks, not an independent geometric proof or final art assessment.

Actual GPU overview PNGs: `growth_000_ui_1920.png`, `growth_050_ui_1920.png`, `growth_100_ui_1920.png`. Independent layers: `moss_only_100_ui_1920.png`, `moss_amount_000_ui_1920.png`, `moss_OFF_ui_1920.png`, `cracks_only_ui_1920.png`, `cracks_OFF_ui_1920.png`. Final framing: `A_roof_branches_closeup_ui_1920.png`, `C_branches_closeup_ui_1920.png`.

Each `_ui_640.png` and `_world_640.png` is a real GPU viewport capture. UI1920 PNGs are nearest3 exports of GPU root640. `growth_100_world_1920.png` is the separate GPU nearest3 TextureRect capture and passed full-byte equality with nearest3 of world640. MP4/compression is not involved.

Self image inspection: branches spread laterally on each building; moss differs from leaf clumps and remains visible at plant growth 0; A's missing corner/parapet/rebar and openings are visible. Revised closeups leave the selected building below both UI rows. B framing uses the same reserved-space setting but was not separately recaptured, as requested.

Headless `parse.log` is structural load only, exits at GPU NOT_RUN. Final main GPU PID 38104 and framing-only GPU PID 48668 exited with code 0. Both stderr logs are empty. Hidden/unfocusable startup and viewport capture were used; no OS input, foreground API or cursor control. No Godot process remains.

## Limits and freeze

Branches stop rather than navigate around holes; trunks retain conservative vertical opening lanes. Flat/curved support comes from configured charts, not automatic arbitrary-mesh analysis. A roof support queries highest triangles and uses a clearance offset, so this is not a physics-based wrapping solver. The same shared fixture leaves retain an explicit clearance from surfaces. Moss/cracks are thin faceted surface sheets with alpha discard and simple procedural shapes; final art quality, arbitrary viewpoints and long-term stability were not evaluated.

NOT_RUN: physical input/native desktop assessment, video, full direction coverage, performance and normal-game regression. No game integration or final art acceptance. `source-manifest.json` freezes source; `integrity.json` confirms read-only dependencies/entry/plant library unchanged. `evidence-manifest.json` hashes evidence excluding runtime profile and itself. Editing stopped and Godot/import resource returned to parent.
