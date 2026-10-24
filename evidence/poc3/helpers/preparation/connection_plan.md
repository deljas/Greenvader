# POC3-HELPERS 未接続準備

対象: HEAD `e7d86a5adedf3a221fe90b88be099a4b530bfb98` + ENEMY凍結中の共有tree。現在の所有は新規helper_work.gd、専用tests/evidenceだけ。既存core/表示/UIへpreloadせず、Godot/importは実行していない。

## 部品と内部値

`scripts/poc2/simulation/helper_work.gd`はSessionを保持しないstatic判断部品。候補スナップショットと任意の到達可否Callableを一呼出だけ受け取り、元辞書を変更しない。保持型RefCountedによるSession循環を追加しない。

- 共通home範囲60論理px=6m、Army追跡80px=8m、帰還判定3px。
- Armyは範囲内味方攻撃中→食害中→その他、同順位距離順。同順位の現targetが新target距離の1.25倍以内なら保持し振動を抑える。現target死亡/消失/追跡限界超過では-1を返してまず帰還、到着時にadapterがtarget_idを解除して次探索。巣/motherを取得しない。
- Sprinklerは未給水crop→成長草。進行中の有効job_kind/job_idを保持し、給水済み/成熟/消失で再選択。危険・水切れと補給の実行順は既存plantsへ接続するadapterが管理。
- Gatは範囲内のplantable候補からgreen_distanceの小さいものを優先、同値は個体距離とtile順。飛行中target予約を除外、ammo0なら仕事なし。green_distanceは局所frontier探索が計算し、毎フレーム全世界scanを追加しない。
- 退避は35pxで開始、fleeing中は45pxまで解除を待つhysteresis。60px内の近い生存Armyの敵と反対側20pxを優先し、現在位置から敵との距離が広がる場合だけ採用。Armyがなければ安全なhome方向、unsafehomeなら敵から離れる方向へ。全候補が通れなければ停止して退避状態を保つ。adapterはnav経路の最初の一歩も敵へ近付かないことを確認する。
- idle_stateは帰還後・仕事なし3秒でsleeping。新仕事で即リセット。Army、移動/資源切れ/補給/退避/到達不能ではZzzを抑止。idle_sinceはゲーム時計を使い終了中進行なし。

内部閾値は試遊用の低リスク初期値。未接続なのでゲーム実行の合格を主張しない。

## coreへの接続案（後続の親範囲通知後）

1. **plants**: _army/_gatlinger/_sprinklerの探索と退避を部品へ委ねるadapterを置く。移動・与ダメージ・給水・資源変更は今のSessionだけが実行。homeを自動更新せず、move_helper指示でのみ変更。仕事完了後homeへ戻し、unsafehomeへの帰還は危険判定が優先。Sprinklerのwater_taskは補給/退避を跨いで保存し、補給完了後homeへ戻る。水は初回有効散水1、追い水仕事なしを維持。
2. **combatのArmy優先情報**: 現在victimはローカル変数だけなので、各enemyへattack_target_type（plants/helpers/player/none）とattack_target_idを明示する。対象が変わる/なくなる時に必ず解除。Armyは実際のphaseと対象の生存・home範囲を照合し、古いidだけで最優先にしない。LOCUSTのphase eat/eating・食害先との接続はLOCUST完了後に合わせる。
3. **Gat飛種**（親承認条件を反映）: 既存kind=seedのshotへsource_type=helper、source_id、target_tile、sow_width=1、reserved_seed=0を付ける。発射時に個体ammo1だけを消費し、以後は使用済み。共通備蓄自動補充なし。個体撤去/破壊後も飛翔を継続し、撤去返還は未使用ammoだけ。helper由来は通常seedの共有予約・壁refund・範囲播種決済へ絶対に流さない。
4. **着弾**: 壁/無効着弾は共有備蓄へ返還しない。地面はtargetセルのcan_plantを再評価し1セルだけ播種。敵/巣へ偶然当たる場合は通常種同様5ダメージ可、自主敵選択はしない。launch時とload後とも全飛翔helper弾のtarget_tileを予約集合にし、別Gatの同セル重複発射を防ぐ。着弾/消失で予約を解放する。
5. **保存**: 既存shots ROWにhelper由来flightを保持。source消失を理由に無効にしない。validatorはsource_type（欠落は従来player）、source_id、target_tile範囲、helperのwidth1/reserved_seed0、通常seedの予約1を分岐検証。source_type不正やhelperを装う通常予約の混在を拒否。発射済弾薬を復元時に再消費/返還しない。新helperのjob_kind/job_id、idle_since/sleeping、退避intentは任意fieldとして旧作業保存に既定値を持たせ、無効なenum/非有限時刻を拒否する。
6. **循環**: 判断部品はstaticのままなのでclose不要。将来adapterがSessionを保持する構成へ変更する場合は既存plants.close相当で参照を切る責任を明示し、Session.close/restoreの両経路へ接続する。

## 表示/UI接続案

- EntitySpriteStateの既存状態attack/sow/water/fleeとhit反応を利用し、必要な短い期限をgame側から渡す。新素材は追加しない。飛種は既存seed shot、着弾芽はWorldState、散水/初回だけ短い水滴きらめきはview-onlyから描く。表示がstate/弾薬/給水を変更しない。
- helperにidle_since/sleepingと状態icon用情報を付け、個体上とmap付近へZzz。Armyはなし、空弾/補給不能は種・水・問題icon、補給/退避は個体iconと選択中mapだけ。必要なら古い仮Meshにも共通の短い表示を付け、仮spriteを維持。
- map_uiの選択時home/rangeは現行Gat60/他40から全役60pxへ変更。追跡80px円は重ねず、home/現在job先も選択時だけ表示。_gaugeの満タン非表示は既存実装済みなので保持。
- 設置previewはprojectedな地面沿い薄円（3D平面上の半径6m）。通常種の範囲播種previewと別条件で表示し、モーダル時や選択解除で消す。設置後の常設円は追加しない。
- HUDや個体に既存HP/水/種ゲージがある場合は満タン非表示を揃える。撤去/弾薬補給UIは維持。world_view/map_ui/poc2_main/UI等の編集は親から範囲を通知されてから。

## 試験準備・NOT_RUN

専用`tests/poc3/helpers/self_pure.gd`に優先順位・target安定・6/8m範囲・巣除外、播種cluster/予約、給水優先/継続/追い水除外、退避hysteresis/Army後方/unsafehome回避、帰還後3秒/即復帰/抑止を用意した。**未実行でありPASSではない**。

接続後は各条件1回、代表fixtureだけで以下を用意する。

- 同じ小world/時計/初期資源でGatなしvsありをゲーム内早送り。自然拡張を同じ条件にし、播種セル数と個体ammo差を比較。飛行中save/load、個体撤去後着弾、壁/無効着弾、2体Gat予約の代表条件で種/弾の二重消費・共有への返還なしを確認。
- 同じ乾燥crop/草でSprinklerなしvsあり。給水株数・同じ時刻の年齢進捗を比較し、crop優先・追い水スキップ・水切れ補給→homeを確認。WATERと同じT/dry半速仕様を維持。
- Armyが味方を攻撃中の敵と食害敵を順に選び、target保持、8m打切り、撃破後帰還、巣へ進軍しないこと。危険中の退避→安全復帰、unsafehomeへ突っ込まない経路を限定確認。
- no_focus/minimizedのGPU画像で設置薄円、選択map home/range/job、飛種/散水、Zzz/資源/補給/退避icon、満タンゲージ非表示を代表撮影。実OS入力/前面化なし。
- 既存全map100%は統合担当へ残す。全回帰・長時間総当たりなし。初回FAIL保持、修正影響だけ追試。

## 準備終了

新規部品・専用試験・本証拠だけ編集。既存core/UI/viewと共有docs/票、Git、Godot/importには触れていない。実行/描画/操作/成果比較はすべてNOT_RUN。LOCUST後に親が接続範囲を渡すまで未接続で停止。
