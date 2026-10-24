# TECH-3D-15 実装自己報告

## 対象版・変更ファイル

HEAD `99013702eaf36db72a64d60d284680fb834f13c5` + 共有ツリーの既存未commit差分。
今回のソースは `source-hashes.json`。変更範囲は `scripts/town_lab/`、専用scene、
`assets/models/town_lab/`、専用bat、launchers索引、自己test/evidence。

## 実装

- 約50×50mの外回り街区。BLD-007/019/038/046/079/091/123の7種7棟、PRP-001/005/012/017/034/041/075、TRE-001少数。十字道路・歩道・北側脇道・空き地に元縮尺で配置する。
- 実mesh AABBで接地・入口方向を記録。壁は高さ0.15〜1.6mと交わる垂直三角形のXZ投影を簡易衝突に使い、巨大な屋根/建物外形を丸ごとの障害物にしない。約4044矩形を4mグリッドで検索する。大物・柱と境界も衝突する。
- 旧人間fixtureの4枚を再使用。専用actorで照明を有効にし、1.65m身長をzoomと独立させる。直立の表示/影板、足元snap、半径0.54mの余白。主な街灯1灯の人影は距離ヒステリシスと向き補間で近似する。他灯はその影板を投影しない。
- WASD/矢印は画面基準、斜め正規化。追従/全景、zoom、開始位置復帰。640×360、nearest整数倍、正投影仰角30°/方位45°、硬い影。
- 24h時刻、朝昼夕夜、再生停止、速度。既定120秒/周。画面上を北とし、太陽は6時東（画面右）→12時南（画面下）→18時西（画面左）。最大仰角55°。太陽・ambient・街灯4灯・近似月光が連動し、地平線以下の太陽は無効。
- 不規則な水たまり4箇所と共有320×180反射。反射像は照明済みなので色/光量を二重乗算しない。昼は太陽、夜は局所灯を受影対象とし、寄与はMAXに制限。夜の月光による影の打消しと多灯加算による発光を避ける。夜の局所受影は弱い近似で、厳密な多灯PBRではない。
- 納品15種のGLB/metadata/PNG42ファイルだけをコピーし、出典・SHA256をmanifestに記録。元納品・既存ゲーム・他labは変更しない。

## 実行した検証と結果

- 初回回帰は34 PASS / 2 FAIL。入力試験は初期unfocusable画面のfocus-out前の注入で最初のキーが消えた。画面安定後の注入へ修正した。水面受影0pxは交差点の覆い板が水面を覆っていたため、歩道を交差点で区切る形へ修正した。
- 夜の街灯自己遮蔽による大きな影も検出。点灯元のランプ本体を局所灯のcaster対象から外し、太陽影/反射には残した。
- 修正後は影響範囲だけ再取得。斜め/直進とも0.64m、昼受影ON/OFF差61px、夜受影差3625px、反射差を確認。既知007外壁でx=-5.8から-6.4へ停止し、主交差点→北脇道→戻る44m短ループが通行可能。
- **有効条件38 PASS / 未解消FAIL0 / NOT_RUN4**。`results.json`は40 PASS観測だが、夜受影と反射の初回PASS2件は後続修正結果で置換するため、合格条件の重複加算をしない。
- 120秒周期は固定1秒刻み120回の早送り1周で確認し、実時間120秒待ちはしない。24と0の状態一致、朝東/昼南/夕西と逆側への影、夜の太陽無効、停止、再現性を確認。
- RTX5070Ti / Vulkan Forward+で実GPU撮影。朝昼夕夜の全景、人物・水面の昼夜、壁際の人物を目視確認。夜の人物は照明に従って暗くなり、常時発光しない。nearest3の画像byte一致も確認。
- 反射viewport自体に建物の壁・窓・柱が映ることを直接目視した。初期P1は外廊下天井裏が黒く映る角度だったため、集合住宅の横壁脇へP1だけ移動。更新反射ON/OFFは1557px差、横壁色と窓端を水面で確認。最終P1に合わせ全景4画像を更新した。
- import exit0、通常importから15種読込成功。user設定/ログ/cache保存不可のsandbox ERRORはあるが、実行時のscript/shader/アセット読込ERRORはない。
- 追加の接近試験ハーネスでdispatch条件を撮影関数へ誤配置した実行は中断し、結果として採用しない。`gpu-contact-aborted.log` に保持。位置を修正した後の短い接近・回遊試験のみ有効。ゲーム実装の不具合ではない。
- 旧project/greening/vegetation/showcase/vine等167ファイルと元コピー42件を最終SHA256で照合する。

## 証拠

- `initial-results.json` / `gpu-initial.log`: 初回34/2。原記録を保持。
- `results.json` / `gpu-repair.log` / `gpu-contact.log`: 有効結果と影響範囲再確認。
- `placements.json`: 7棟ほかの接地AABB、元scale、入口、衝突数。
- `morning/noon/evening/night_overview*`: 最終配置のGPU全景。
- `building_wall_contact*`: 007外壁への接近停止。
- `water_day_shadow*` / `water_night_lamps*`: 昼/夜の受影とOFF比較。
- `water_building_reflection*` / `water_reflection_OFF*` / `water_night_building_reflection*`: 最終P1の反射。
- `reflection_viewport_day/night_320.png`: 反射パスの建物・人・点灯体。
- `raw*.json`: 段階ごとの撮影時刻・太陽・actor同期状態。P1移動前rawのカメラ位置はそのまま保持し、最終P1は `self_reflection.gd` の位置を参照。
- `protected-baseline.json` / `preservation.json` / `source-hashes.json`: 保全と凍結。

## 操作・未検証・残課題

`launchers/labs/run_town_lab.bat`。WASD/矢印で歩行、Fで全景/追従、Rで開始位置、上部で時刻/再生/速度/zoom。

NOT_RUN: 物理キーボードからOS経由の入力、全角度/性能負荷、ゲーム保存・戦闘・緑化の統合、ユーザーの美術評価。
衝突は屋外回遊用で、全建物の屋内・階段・全隅の通行を保証しない。主街灯の人影と水の夜受影は近似。
新しい植物や成長は制作しない。通常ゲーム/P2/P6を再開していない。

実行したGodotプロセスを終了し、import/GPU実行権を親へ返す。
