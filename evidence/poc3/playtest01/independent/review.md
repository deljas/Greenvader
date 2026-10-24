# POC3-PLAYTEST-01 independent verification

Target: HEAD da1eeb0 + uncommitted diff, manifest_C.txt (172 files) matched before and after.
Tests: tests/poc3/playtest01/independent/ (ind_logic, ind_full, ind_gpu_a/b/c, ind_reg, reg_core/reg_journey copies, run.ps1).
Results: results_summary.json, logic_results.json, gpu_a|b|c/results.json, full_*.json, reg/.
Real GPU images (offscreen 640x360 composite, window minimized): gpu_a/wet_stage*.png, water_anim_sheet.png, price_n*.png,
rate_with_crops.png; gpu_b/out_*.png, in_*.png, fade_out_sheet.png; gpu_c/*.png.
Items 1-13 all PASS. See final report for findings (self-test overwrote older evidence; fade-in end pop; sweep removal slows full greening).
