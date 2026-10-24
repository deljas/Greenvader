# TECH-3D-05 implementation self report

Target: HEAD `99013702eaf36db72a64d60d284680fb834f13c5` plus shared existing uncommitted ART/TECH work, 2026-10-16. This is an isolated technical fixture, not normal-game integration or final art acceptance.

## Implementation and use

Run `run_vegetation_lab.bat`. The default is 50%. Move the growth slider, type the percentage, or press 0/50/100. Select the overview or A/B/C close view. No automatic growth or lighting controls were added; those were optional.

`building_defs.gd` contains only building-scale shape/size/color, deterministic seed, surface charts, opening rectangles, paving extent and entrance corridor. `building_geometry.gd` constructs the buildings; `growth_patch.gd` applies the same placement and root-to-roof growth rules to each. `plant_parts.gd` constructs one shared resource library: two grass meshes, one leaf-cluster mesh, one stem mesh, one foliage material and one stem material. All three patches use these identical resource objects. Plant instance transforms change with growth; candidates are generated only during setup. No stage-specific assets or generated bitmap art.

Per-building setup:

- A: one size, two plane surface charts, three opening rectangles, one straight corridor, one seed. Six automatically derived vine paths; 298 grass candidates.
- B: one size, two plane surface charts, four opening rectangles, one corridor, one seed. Two derived paths because the generic rule excludes the full horizontal span of stacked openings; 276 grass candidates.
- C: radius, wall height, cone height/radius, one periodic cylindrical surface chart, three opening rectangles, one angled corridor, one seed. Twelve derived paths; 300 grass candidates. Brick pattern and dark metal cone identify an old utility tower. Curved wall samples and cone normals orient the same leaf mesh. Paths sample at no more than 0.12 units and pass via the roof eave.

No individual leaf positions or per-stage plant definitions are entered in building data. Opening exclusion conservatively reserves a vertical strip rather than routing vines around each hole. Ground rejection includes 0.34 units for clump width in addition to the entrance corridor. Leaves/stems use a 0.16 surface offset to remain outside the 0.22-thick box walls; this is a simple surface-chart approximation, not automatic mesh wrapping or botanical simulation. Only two visible plane walls are configured on A/B. C covers the full cylinder; roof paths end before the cone apex. No wind animation, collision, gameplay growth timing or persistence.

## Verification and evidence

The single final GPU run used Godot 4.7.2, Vulkan Forward+, NVIDIA GeForce RTX 5070 Ti. Root was unfocusable and launched with PowerShell `Start-Process -WindowStyle Hidden`; no OS input, cursor movement or foreground APIs were used. `process.json`: PID 18596 exited, exit code 0. `gpu.log`, `stdout.log`, `stderr.log` preserve the final run; stderr is empty.

`results.json`: 14 checks PASS, zero FAIL. Engine Control signals exercised 0/50/100 presets and slider/number synchronization. The same 100% leaf transforms and fixed layout signatures were restored after 50%. Each building checked actual mesh/material object identity, grass/vine opening exclusions and finite instance transforms. The representative world image passed a full-byte equality comparison with nearest3x of its 640 source. These checks cover the fixture rather than game regression.

The self exclusion checks call the same Geometry helper used during candidate construction; they establish implementation consistency, not an independent geometric proof. The separate verifier should assess actual positions/margins and images independently.

GPU images:

- `growth_000_ui_1920.png`, `growth_050_ui_1920.png`, `growth_100_ui_1920.png`: overview comparison with controls. Each corresponding `_ui_640.png` is the actual GPU root image; the UI 1920 file is a nearest3 export of that source.
- `growth_000_world_640.png`, `growth_050_world_640.png`, `growth_100_world_640.png`: actual 3D SubViewport captures.
- `growth_100_world_1920.png`: actual GPU TextureRect nearest3 output, exact agreement with 640 source verified.
- `C_mature_closeup_ui_1920.png` and 640/UI/world counterparts: cylindrical wall/roof example.

Self visual inspection found three distinct building silhouettes/materials, readable controls, increasing ground clumps and root-first vines, retained windows/doors/corridors, and vegetation receiving light/casting dynamic shadows. C's window outline is faceted because the cylindrical opening is sampled on a 96-column/40-row mesh. Grass and leaves are intentionally simple angular fixture geometry; fine visual quality is not evaluated as final art. The hard filter retains renderer sampling/bias behavior and is not claimed to be mathematically binary shadowing.

The initial headless structural run (`parse.log`) printed zero-vector Quaternion errors for extremely short unstarted stems. The growth code was corrected to hide those segments before orientation. The following final GPU run exercised the affected states without those errors. Headless was not used as rendering evidence.

NOT_RUN: physical keyboard/mouse delivery, interactive desktop display assessment, video, performance, all-direction camera/light sampling, complete normal-game regression. The task permits comparison PNGs in place of video.

## Freeze and preservation

`source-manifest.json` hashes the new source/scene/bat/self test files. `source-before.json` and `integrity.json` show the five preexisting read-only dependencies/project settings unchanged. `image-manifest.json` hashes the PNG evidence. No commits, branches or old-source edits. Godot process ended; editing and GPU use stopped. Parent/independent verification retains final acceptance responsibility.
