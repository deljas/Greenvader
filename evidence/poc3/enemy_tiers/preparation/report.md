# POC3-ENEMY-TIERS 未接続準備

対象はHEAD `9d54a6d1795065e6e642fe01543b2c8d2a1f27ee` とINPUT凍結差分を含む共有tree。編集は新規 `scripts/poc2/simulation/enemy_tiers.gd` と本preparation証拠のみ。INPUT/他担当の既存コード・データ・資料・作業票・Git indexを変更していない。

## 部品/API

- `tier_for(initial_start_logic, placement_logic) -> int`: 両引数は論理px。既存Config.px_to_m（0.1m/px）でユークリッド距離を換算し、18m未満0、18m以上32m未満1、32m以上2。180px/320pxが境界で、境界ちょうどは上位階級へ入る。
- `hp(base_hp,tier)` / `attack(base_attack,tier) -> float`: 基本値へ1/1.3/1.7、1/1.2/1.4を適用。HP/攻撃を整数化しない。
- `reward(base_reward,tier,initial) -> int`: 初期個体/巣は1/1.5/2倍後floor。追加生産は常に0。中階級の基本報酬15は22、基本報酬1は1になる設計。
- `valid_tier(tier) -> bool`: 0/1/2のみ。将来の保存検証で値を検証してから能力APIへ渡す。設定配列・距離境界を本部品へ集約。session/乱数/状態変更/描画への依存なし。

## 後続接続ポイント

WORLD-LAYOUTの初期開始点を用い、combat.add_nestの配置確定時にtierを1回設定し保存する。free_positionの補正前後どちらを『配置点』とするかは本接続で実配置に合わせ確定。通常初期敵と生産配下は元巣の固定tierを継承。動く親玉が移動/生産してもtier_forを再実行しない。

combatのadd_nestの規模別HP40/100/240、spawnの基本HP20/40にhpを適用する。既存strongと巣規模は距離階級と独立。敵の通常攻撃5/突進12と親玉接触10をattackへ接続し、プレイヤー/おたすけ/植物への該当加害を揃える。初期敵の基本報酬6/15、巣規模報酬30/80/200はrewardへ接続し、追加生産のinitial=falseは0を保持。

persistenceの敵/巣entityに固定tierを保存・厳格検証する接続が必要。旧PoC3保存のtier欠落の扱いは親の方針に従い、本準備では変更していない。tick・移動・描画からtierを再計算せず、速度・予兆時間・生産能力・外見は変えない。

## 静的確認 / NOT_RUN / 停止

tasks/README、POC3_ENEMY_TIERS、POC3_SPEC距離階級節、既存Coords/Config・combatを読取。Configの0.1m/論理pxと型注釈、18/32の不等号、倍率配列、追加生産早期0、報酬floorをコード上で照合した。これは実行PASSではない。SHA-256はhashes.json。

Godot/import、構文実行、単体/ゲーム/境界/継承/保存試験、GPU・操作はすべてNOT_RUN（INPUT独立検証が実行資源を所有）。OS入力・前面化なし。CONTENT sandboxを含め既存プロセスの停止なし。未接続のまま編集停止。本接続と独立検証はWORLD-LAYOUT後、親の解除待ち。
