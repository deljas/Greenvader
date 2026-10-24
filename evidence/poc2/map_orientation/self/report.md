# POC2-07 implementation self verification

Target: HEAD `151a53f20255489ef08481e2a353258cd8ac559c` plus inherited dirty tree. Runtime edit only `scripts/poc2/ui/map_ui.gd`; SHA256 in source-manifest.json. Shared status/spec files not edited.

Ground projection follows real Camera3D yaw 45 / elevation 30: diamond width224 height112 inside existing full map224 frame. Mini retains circular108 frame. Terrain is sampled directly at output pixel centres, nearest; no texture rotation. Mini terrain and icon anchors share one projected-pixel-snapped centre. Source map disclosure refresh remains 0.5s; mini scroll rerasterizes when that centre moves. Icons/gauges/buttons stay upright. Projected ground-circle activity/home lines, selection rings and gauges are clipped at viewport. Offscreen selected controls hide. World exterior cannot receive helper orders.

Zoom 2x / 4x retains cursor's ground anchor exactly. Returning to 1x deliberately re-fits the complete world and resets centre; this is the only anchor exception.

- Normal GPU full check: 13 PASS / 2 FAIL, results.json + gpu.log. Actual camera maximum direction error 0.0000005545 rad, exact inverse error 0.0, snapped moving mini, full diamond, 2/4 cursor anchors, selection/upright controls, popup input ownership, exterior rejection, offscreen controls, hidden enemy disclosure, 640 nearest 2x checked.
- Two FAIL were test fixture errors: move target overlapped the remove button, opening a popup; that popup then swallowed zoom. First replacement was water (properly refused), recorded in affected-results.json / affected.log (1 PASS / 2 FAIL). No runtime code changed for these.
- Final limited command retry selected one walkable point outside control rectangles BEFORE clicking. 3 PASS / 0 FAIL: fixture, correct helper home at inverse-projected click `(698,690)`, 1x refit. command-retry-results.json + command-retry.log. Initial logs retained; view.gd now uses validated cell174,172 for a future run, not rerun in full.
- Normal import exit0 with no parse/runtime errors: import.log. First sandbox import lacked user-directory permission, so normal permission was used for final import/GPU. No application input/focus/cursor manipulation; root.unfocusable + Input.parse_input_event only.

GPU screenshots: mini-normal, mini-moving, full-explored, full-terrain, zoom-selected, edge-clipped, integer-2x-internal. All capture the real rendered640x360 viewport. At integer-2x the native window is1280x720 and final transform is2x; screenshot remains internal640 to preserve source pixels. Implementer inspected zoom-selected; parent independently inspected main views.

NOT_RUN: physical keyboard/mouse path; full game regressions; long-play balance/performance; final fun/art approval. No simulation/save/first-PoC edits. Godot processes exited and implementation editing stopped for independent handoff.
