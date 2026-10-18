# POC-01 independent verification (green-verifier, Sonnet 5.5 claude-sonnet-5-5)
Target: HEAD 9901370 + frozen sha256 (poc01_freeze.txt); all 8 files matched at start and end.
Files: tests/poc/independent/poc01_logic.gd (headless), poc01_gpu.gd (GPU window, unfocusable). Logs/images in this directory.
- Switch 640<->960: PASS. camera.size 18.5 constant; position/aim unchanged; render_view.size and content_scale_size switch; scale 3x/2x at 1920x1080 (integer_scale), 1x at 1000x700.
- Small window: PASS. 960 refused with notice in 800x600; enforce_window falls back to 640 with explicit notice and disables the 960 button.
- Coordinates: PASS. unproject_position -> pick_ground round trip worst 0.00001 m (both resolutions); margin and UI button rejected.
- Constants: PASS. 4px=0.4m; injected W/A/S/D via Input.parse_input_event: axis, diagonal both 1.92 m/0.8 s (normalized), identical at 640/960; x16 multiplier doesn't change walking; W moves screen-up only.
- Single clock: PASS. pause freezes time and position; resume advance 0.016 s only; 5 s delta capped at 0.25 s. Code: no separate clock in session/main (grep hour/Time/ticks_msec: none).
- Rendering (RTX 5070 Ti, Vulkan): PASS. sprite/shadow board same texture/feet/flip; changes outside sprite mask vs bare ground = 0 (no outline); sprite colours 9 static and 9 across 12 sub-pixel follow offsets at both resolutions; feet on integer screen px. Images: render_640.png, render_960.png, follow_640/960.png.
Note: moving the player toward +x/+y behind the wall block at cell (30,24) legitimately occludes the sprite (first run's extra "colours" were occlusion, not bleed); not a defect.
NOT_RUN: physical input, real 1080p window / non-integer window display, real window resize event path (window size override used in tests), shadow-correctness on walls beyond sync check.
