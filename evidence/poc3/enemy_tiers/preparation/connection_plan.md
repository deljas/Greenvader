# ENEMY-TIERS 接続・代表試験の準備（2026-10-24）

準備対象: HEAD `a72c39f71324367eccd00518725dc8dc4c640e64` + WORLDのsession/persistence接続差分。他者差分を戻さない。既存core・Godot/import・Git・共有docs/票は本準備で変更しない。未接続enemy_tiers.gdは既存の準備品を読み取り、そのまま維持した。

## 親へ渡す接続案

1. combatでTiers部品をpreload。add_nestはfree_position補正後のposと`session.start_position()`を使ってtierを一度確定。最大HPは規模基本40/100/240へ倍率。nest辞書にtierを保存。
2. spawnは初期個体も追加個体も生産元nestのtierを継承。通常/strong基本HP20/40へ倍率を適用しenemy辞書にtierを保存。現在のプレイヤー位置・enemy位置・動くmother位置からtierを取り直さない。
3. 敵の通常攻撃5・boar突進12は攻撃元enemyの固定tier、mother接触10はnestのtierを参照。プレイヤーと植物/helperへの該当加害を揃える。既存速度・windup/recovery・spawn interval/cap・見た目は変更しない。
4. 初期enemy報酬6/15、nest報酬30/80/200を固定tierで計算。中階級strongは22（22.5からfloor）。追加生産`initial=false`は全階級0。
5. persistenceはenemy/nestのtierが欠落した旧作業PoC3に0を補い、従来HPを保持。明示値は数値0/1/2の整数だけ（bool/小数/負/3/非有限は拒否）。JSON floatの0.0/1.0/2.0は整数値として認めintへ正規化する。max_hpは種別/strong/規模と固定tierの期待値に一致、hpは0超max以下。値検証後にTiers.hpを呼び、部品のassertを不正保存で踏まない。復元時は現在posで再判定しない。
6. ソースnestが既に破壊されている生存enemyも復元できるよう、その個体自身の固定tierと能力を検証する。旧PoC/PoC2保存は対象外のまま。

この案は現在未接続。core所有権は親の通知後に引き継ぐ。部品だけの試験もGodot実行権通知までは実行しない。

## 代表試験

- 準備した`tests/poc3/enemy_tiers/self_pure.gd`: 18m直前/ちょうど、32m直前/ちょうど、ユークリッド距離、0/1/2範囲、基本HP20/40/100/240、攻撃5/12/10、報酬6/15/30/80/200と追加生産0。手計算期待を用い式を試験側へ複写しない。
- 接続後の新Session: WORLDの固定開始点とfree_position補正後posからnest階級が一致し、初期配下全員が生産元固定階級・最大HPを持つこと。
- motherを開始点近くへ移した後に配下を1体生産し、元の外側tier・通常HP34を維持。主人公の移動でもtier不変。追加生産配下を倒した報酬0、初期strong中階級を倒した報酬22、代表nestの報酬を確認。
- 攻撃は通常敵→植物/helper、boar突進→主人公、mother接触→主人公の代表経路で実HP減少を直接測る。既存の移動/予兆/生産設定に無関係差分がないことをコード差分で確認。
- 実JSON save往復で固定tier/HP/現在posを保持し、移動後の現在距離へ変更されないこと。旧作業missing tierを0・旧能力で受理。不正tier/能力不整合を拒否し現在Session不変。
- 各条件1回・長時間走行なし・全回帰なし。初回FAILは原ログを保持し影響条件だけ追試。GPU/物理入力/難易度評価は本準備ではNOT_RUN。

## 準備結果

読取: tasks/README、対象票、TASK_TEMPLATE、POC3_SPEC階級節、既存preparation/report・hashes、Config/combat/session/persistence。新規編集は専用純粋試験とこの接続案だけ。ゲームcore編集・Godot/import実行なし、接続待ちで停止。
