# POC-03 自己検証報告（親が実装担当の返却本文から転記）

実装担当（Sonnet 5.5）のreport.md書込みはハーネス制約で拒否されたため、親（claude-20261018-poc-opus）が要約転記した。合否は変更していない。

- 対象: HEAD 9901370＋既存未コミット差分。scripts/play・scripts/world・data直下・既存sceneは未変更（再利用のみ）。
- 変更: 新規 scripts/poc/play/poc_projectiles.gd（表示非依存の論理弾、壁→敵フック→着弾の順）、poc_play_view.gd（MultiMesh差分更新の成長表示、拾得物・栽培植物・供給源・弾の仮表示）、data/poc/play_setup.json（射程70px=7m、弾速140px/s、上限24、供給源落下半径6〜12px、供給源セル）。変更 poc_session.gd（PlayState接続、一本のadvance_gameループ、fire/inspect/緑化率）、poc_main.gd、poc_input.gd（E/Tab/ホイール/F9）、assets/placement.gd（封鎖屋内セルを弾遮断に、1行）。
- 結果: tests/poc/play/logic.gd 69 PASS / 0 FAIL、POC-01回帰 40 PASS、POC-02回帰 45 PASS、旧P1 p1_01〜06_checks 全て失敗0（書換えなし）、GPU 8 PASS / 0 FAIL（RTX 5070 Ti、1280×720窓、unfocusable、OS入力なし）。
- 証拠: logic.log、regress_*.log、p1_0*.log、gpu.log、exit_codes.txt、scene0〜3_*_640.png、scene4_pickups_960.png、base_640.png。
- 仕様判断: 壁に当たった種・水は失われる（栽培植物の弾は種返却）。種散布の壁越しタイルは取消す。水の散布（Landing.splash_water、変更不可）は壁の反対側の水分を上げうる（植付・緑化率には影響しない軽微な制約として親が受入）。全補給は既定無効、`--debug-refill`時のみF9。
- NOT_RUN: 物理入力、実1080p窓、敵命中（POC-04）。
- 残課題: fixture_02は対象784セル中多くが封鎖で安全地帯が狭い→POC-07で見直し。高い建物が北側の地面とプレイヤーを隠す→POC-06。
