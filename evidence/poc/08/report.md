# POC-08 自己検証報告（親が実装担当の返却本文から要約転記）

- 対象: HEAD 9901370＋既存未コミット差分。scripts/world|play|enemy、project.godot、run_game.bat、旧セーブは未変更。
- 変更: 新規 scripts/poc/save/poc_save.gd（FORMAT_VERSION=1、REQUIRED表）、scripts/poc/ui/poc_ui.gd、tests/poc/save/logic.gd・ui_logic.gd・gpu.gd。変更 poc_main.gd（make_session/replace_session/_teardown_world、タイトル・メニュー）、poc_session.gd（cancel_shots_for_save）、poc_input.gd（F5保存）、launchers/README.md（PoC行に追記）。
- 保存先: user://poc_saves/slot.json＋slot.bak.json（書込み中のみslot.tmp.json）。一時ファイル→再読込確認→旧slotをbakへ→rename。キー: format_version、map_id、map_hash、game_elapsed、saved_at（表示専用）、world/growth/spread/far/clock/play/enemies/wall_growth/session/combat_stats/ui。
- 保存責任: マップ版・サイズ・zone割当、WorldState全配列と地域状態・sprout_seed、GrowthSim/SpreadSim/FarSeedSim進捗、SimClock、PlayState（資源・HP・選択・拾得物・栽培植物・供給源タイマー）、EnemyField（巣・敵・各個体rng・死骸）、壁植生、プレイヤー位置・地域ログ・統計、解像度index。保存しない: 飛翔中の弾（消滅し消費分・予約種を返却。種が上限満タンのとき返却は上限で切られる軽微な制約）、照準、倍速、pause、現実時刻、表示専用状態。
- 読込: 新セッションへ適用し成功時だけ差し替え、表示はbuild→bind経路で再構築。拒否コード missing/corrupt/missing_key/version/map/hash/invalid、拒否時は現セッション・占有・表示不変、slot破損時はbak案内。読込後はゲーム時計の続き。
- UI: タイトル（新規開始／続きから／バックアップから続ける／操作説明、run_poc.bat起動時）、Escポーズメニュー、操作説明、内部緑化率バッジ（端数切捨て、100は厳密一致のみ）、保存/拒否のトースト。
- 結果: save logic 58、ui_logic 28、GPU 7 PASS、回帰 base 40 / assets 45 / play 69 / combat 48 / environment 81 / occlusion 37 / map 49 PASS。0 FAIL。
- NOT_RUN: 物理入力、run_poc.bat実起動でのタイトル実描画（headless起動のみ）、960のタイトル・操作説明、実速度一周、性能、自動保存（任意・未実装）、downed中保存の組合せ。
