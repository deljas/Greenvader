# POC-07 自己検証報告（親が実装担当の返却本文から要約転記）

- 対象: HEAD 9901370＋既存未コミット差分（scripts/poc・data/poc・tests/pocは未追跡）。再現手順は repro.txt、盤面は town_ascii.txt。
- 変更: poc_session.gd（マップ寸法可変、街区JSON読込、seed_sources）、poc_main.gd（主シーン起動・`--town`・meta poc_townで town_01、`--fixture=02/04`・`--combat`・`--bare`は旧挙動）、asset_catalog.json（BLD-046/BLD-123/PRP-001/041/075追加）、新規 data/poc/maps/town_01.json（48 instance、地域・巣・供給源・敵調整・layoutを固定）、tests/poc/map/logic.gd・gpu.gd・ascii.gd。
- 街区: 112×112セル=44.8m四方、建物7棟（BLD-007/038/019/046/079/091/123）、外周の舗装環状路（3.2m）、路地、中央舗装広場と恒常水源（水16×14＋水辺）、池中央の4×4島（孤立緑化対象）、廃車3・街灯10・バス停・滑り台・コンテナ2・消火栓3・電柱3・樹木11・装飾水たまり7。安全地帯zone0（初期緑化484、供給源(82,80)(94,92)、開始(88,86)）、戦闘zone1に巣3（(14,93)(14,36)(88,38)）。舗装3854セルは全て緑化対象。
- 100％: 事前上限 869.0s（far.completion_bound_seconds）。安定73.5s、安定後796.5sで9464/9464厳密到達（無入力・資源消費なし・再侵攻0・島含む）。
- 結果: map logic 49 PASS、回帰 base 40 / assets 45 / play 69 / combat 48 / environment 81 / occlusion 37、GPU 5 PASS。0 FAIL。
- 撮影演出: 「後」は巣・敵除去＋全対象成熟＋560s早送り。全景のみcamera.size=38m（通常18.5m）。追従カットはプレイヤー表示位置のみ置換。
- NOT_RUN: 物理入力、実速度での一周、性能。
- 固定値（POC-08用）: instance 48、terrain hash 1356403921 / target hash 4099287451、targets 9464、初期greened 484、rng 20261018、sprout 81026。
