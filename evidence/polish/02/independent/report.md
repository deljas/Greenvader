# POL-02 independent verification (green-verifier)
Target: 95793db + uncommitted. Frozen sha256 matched at start and end (7 files).
- Diff review: PASS (T in _unhandled_input only when menu=="", before the viewing branch; other view keys unchanged; save format untouched; help line + GUIDE row present).
- Own headless test v_text.gd (25/0): F2 while hidden, hidden click -> ground, Esc menu open/close while hidden, T ignored in menu, restore shows latest HUD/notice, F5 + load while hidden, viewpoint enter/leave via E while hidden, T in view, F3 ignored in view, toast expiry, title T ignored, new game keeps hidden: all PASS.
- Regression (79 SceneTree entry scripts, once each; current vs baseline copy = current tree with the 4 scripts from 95793db): identical summary. FAIL: hlp02_gat 1, poc01_logic 7, poc07_logic 7, poc07_mesh 4, poc08_core 1, poc09_play 1 in both. GPU scripts exit 2 headless (NOT_RUN); poc01/07/08 gpu and pol01_gpu timed out (124) in both.
- GPU images: viewed, PASS (text on/off contrast, night 640/960, view 640).
