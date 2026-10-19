# POL-02 report (base 95793db, uncommitted)
Changed: poc_input.gd (poc_toggle_text=T), poc_main.gd (text_visible, set_text_visible, T in _unhandled_input when menu==""), ui/poc_ui.gd (help line, text_visible, badge/toast), view/viewpoint_panel.gd (suppressed), docs/POC_GUIDE.md (T row), new tests/poc/polish/text_toggle.gd and text_toggle_gpu.gd. sha256: sha256.txt.
Tests:
- text_toggle.gd headless: PASS 47/0 FAIL (640/960, normal/view/menus, hidden-button click goes to ground, save v2 unchanged, load keeps setting, boot visible).
- text_toggle_gpu.gd (GPU, unfocusable): PASS, images night_{640,960}_text_{on,off}.png, view_640_text_{on,off}.png (viewed).
- Regression: all SceneTree entry scripts under tests/poc run headless once (logs in logs/). Failures in hlp02_gat(1), poc01_logic(7), poc07_logic(7), poc07_mesh(4), poc08_core(1), poc09_play(1) are IDENTICAL on a baseline copy with the 4 original files from HEAD (pre-existing, not from POL-02). All others 0 FAIL. Helper scripts (bot/cmp/full_flow_bot) were wrongly launched once (modal warning); not counted. perf.gd exit 2 = NOT_RUN headless.
