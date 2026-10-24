# Corner selection follow-up

Independent reproduction confirmed product bug: visible helper at logic894,894 rounds to pixel320,232 whose inverse is world896,896, causing exterior guard to reject selection.

Minimal fix: reject outside map rectangle first, resolve existing drawn icon hit targets, then reject world-exterior clicks only for non-icon interaction. Popup and command-button ownership remain earlier in the control flow. Simulation/save unchanged.

One affected GPU run, corner.gd: 2 PASS / 0 FAIL. Last-cell icon selectable with upright commands; distant exterior click leaves home unchanged. Engine input only / unfocusable true, no OS automation. corner-results.json, corner-gpu.log, corner-selected.png. Earlier FAIL evidence retained. No broad suite rerun.

Runtime freeze hash is in corner-source-manifest.json. Godot exited and editing stopped for independent handoff.
