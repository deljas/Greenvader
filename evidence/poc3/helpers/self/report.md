# POC3-HELPERS 実装者自己報告

## 対象版・変更ファイル

共有HEAD `a97fbcdb996ba90a74c9cf5cf66cdb8206d19786`（LOCUST親コミット）+ HELPERS未コミット差分。WORLD/PRICING/ENEMY/LOCUSTを再適用せず、その上へ実装。ゲーム9ファイルのSHA-256、試験hash、実ユーザー保存保全、終了状態は`freeze.json`。既存7ファイルの実差分は`actual_diff.patch`、新規2部品の正本は実ファイルと凍結hash。

- 新規 `scripts/poc2/simulation/helper_work.gd`、`scripts/poc2/view/helper_effects.gd`。
- 更新 `simulation/plants.gd`、`combat.gd`、`persistence.gd`、`poc2_main.gd`、`view/world_view.gd`、`entity_sprite_state.gd`、`ui/map_ui.gd`（scripts/poc2/以下）。
- 専用 `tests/poc3/helpers/{self_pure.gd,self_logic.gd,self_markers.gd,self_gpu.gd,self_run.ps1}`、Godot生成の専用`.gd.uid`、本証拠。
- `poc2_ui.gd`の主人公HUD変更は親判断に従い除去し、内容差分なし。新素材・共有docs/票・Git index/commitは編集していない。

環境はWindows / Godot `4.7.2.stable.official.ed1daf0bf`。logicはheadless/Dummy audio、GPUはVulkan 1.4.341 Forward+ / RTX 5070 Ti、640x360。APPDATA/LOCALAPPDATAは本ディレクトリ下のignored profileへ隔離。

## 実装内容

行動判断はSessionを保持しないstatic部品に分離。6mの持ち場とArmy最大8m追跡、優先順位（仲間植物攻撃中→食害中→侵入）・同順位距離/標的安定化・撃破/打切り後帰還を接続した。Armyは敵リストだけを対象とし巣を自主選択しない。combatにattack_target_type/idを記録し、phaseと生存対象を照合して優先する。

Gatは局所frontier探索で緑の近くからまとめて空地を選び、飛行中の個体弾targetを予約して重複発射を避ける。1発につき発射時ammo1、共通備蓄自動補給なし。既存seed shotをsource_type=helper/source_id/target_tile、幅1/共有reserved_seed0で区別する。壁・無効着弾では共通種へ返さず、地面着弾時に1セルのcan_plantを再評価する。偶発的な敵命中は5ダメージ。個体撤去/破壊後も飛翔を続け、返還は未使用ammoだけ。通常AREA弾の幅・共有予約/返還経路へ混ぜない。

Sprinklerは危険→水切れ補給→未給水crop→未給水成長草。既存jobを保ち、初回散水だけ水1、追い水を仕事にしない。補給intentは退避を跨いで維持し、補給後に元のhomeへ戻る。選択mapの仕事先もbank/homeを追う。

退避は3.5mで開始・4.5mで解除するhysteresis。近いArmyの敵と反対側を優先し、敵から遠ざかる到達可能候補だけを使う。最初のnav一歩が敵へ近付く経路は採用しない。仕事終了/空弾の共通帰還と水補給帰還にもunsafehomeのガードを置いた。帰還後無仕事3秒で作業役にZzz、新仕事で即解除。Army、資源切れ、補給、退避、到達不能ではZzzを抑止。

表示は既存仮sprite/meshを維持。短いattack/sow/waterと命中反応、既存飛種、着弾きらめき、Zzz/種不足/補給/退避/問題マークを付けた。個体には小さな12x2px仮HP/種/水バーを必要時だけ出し、満タン時は非表示。数値3行の常設テキストは出さない。主人公の右上HUDは保持。設置時6m薄円は3D地面平面に置き、草の上でも読める深度非依存の表示ガイドにした。設置後はmap選択時だけhome/6m/range/jobを表示し、8m追跡円は重ねない。表示コードはゲームstate/資源を変更しない。

保存はhelper任意job/idle/action状態と由来別seedの予約/幅/target/typeを検証。旧player shotの既定予約1を保持し、helperは共有予約0のみ、source消失を許容する。二重helper target予約や共有予約混入は拒否。static部品・view部品はSession強参照を新設せず、既存plantsのclose責務も保持した。

## 実行した検証・結果

- import 1回: `import.log`、exit0、エラーなし。後追加のview/試験は該当Godot実行でparse/動作を確認。
- 純粋試験1回: `pure.log` / `pure_results.json`、**19 PASS / 0 FAIL**。優先/安定/6m8m/巣除外、cluster/予約、給水順/継続、退避hysteresis/Army後方/unsafehome、Zzz抑止/復帰。
- 初回実Session: `logic_initial.log` / `logic_initial_results.json`（原logic.log/resultsも保持）、**12 PASS / 1 FAIL**。個体ammo先払い・共有予約0、飛翔予約、個体撤去後の実JSON完全snapshot往復/着弾、共有残高不変、壁無返還、予約混入拒否、AREA代表、配置有無比較、unsafehomeとArmy食害保護がPASS。
- 初回FAILは帰還後Zzz代表。検索待ち中にtarget_pos=homeを作業先として扱う経路があり、空jobでもworking/wateringへ入った。空jobは検索時刻まで帰還/待機を継続するよう修正。元条件・式を緩和していない。
- 待機限定追試: `idle_first_followup.log/results`でGat idle/wake/unsafehome **3 PASS**。その後Sprinklerの影響確認も含めた`idle_followup.log` / `idle_followup_results.json`は**5 PASS / 0 FAIL**。空jobをwatering扱いしない、実水切れ補給から元homeへ戻る（距離2px、水100、water_task空）も確認。全論理の再走なし。
- 補給の選択map向けtarget_posをbank/homeへ追従させる最終表示情報変更だけ、`markers.log` / `marker_results.json`で**1 PASS**を確認。Map scriptもpreloadして構文を確認。
- 比較は同じSession世界/初期条件で6秒をゲーム内早送り。helper寄与を分離するため両側の自然拡張thresholdを同じ1e9に置いた局所fixtureで、通常全mapの結果ではない。**Gatなし/あり播種0/2セル、Sprinklerなし/ありwatered0/1・年齢3.0/5.875**。同じLOCUST条件のArmyなし/ありでは食害セルstage0/4。経済・楽しさの評価を代行しない。
- GPU初回: `gpu_initial.log/results`、構造/撮影条件は7 PASSだったが、実装者目視で円が草に隠れて読みづらく、状態fixtureも密集していた。**構造visibleだけで範囲表示を合格にしていない**。原3画像は`*_initial.png`に保持。
- 最初の表示限定追試: 深度/薄円幅0.08m/alpha0.55とfixture間隔を限定調整、`gpu_range_followup.log/results`と`*_range_followup.png`を保持。7 PASS、親も楕円・Zzz/補給を目視。
- 最終表示限定追試: 個体間距離を全て2.4m以上にした四隅配置、selected mapをzoom4へ変更して**7 PASS / 0 FAIL**。`gpu.log` / `gpu_results.json`。短い命中反応はfallback仮meshにも適用し、Gatのvisual_state=hitを同じ撮影条件で確認。新しい美術磨き込み・全論理再走はしていない。
- 重複を除いた最終有効結果は **42 PASS / 0 FAIL**（pure19 + 有効logic16 + GPU7）。元証拠との対応は`results.json`。`git diff --check`成功、改行に関するGit noticeのみ。

## 最終画像の識別と目視

実装者は以下3枚を最終生成後に開いて確認した。

- `range_states.png`: 草越しに6mの薄い楕円、離れたZzz/補給/種不足マーク、部分バー。個体の数値常設表示なし。
- `flying_actions.png`: 飛翔中の個体種と短いsow/water/攻撃・命中状態の代表。静止画なので全動作の時間的読みやすさは評価していない。補給/アクションの一部は表示用fixture状態で、補給の実行自体はlogicで別確認。
- `selected_map.png`: 同fixtureをzoom4。選択個体のhome・6m範囲・仕事先・部分ゲージ。状態マークは選択/待機条件に従う。

最終3枚と原画像は別名なので、受入時はサフィックスなしの上記3枚を参照する。全GPU開始/終了ともno_focus=true・native root minimizedをassert。UPDATE_ALWAYS・force_draw(false)でoffscreen撮影し、OS入力・前面化・カーソル移動・ウィンドウ復帰は行っていない。

## 未検証事項・残課題・終了

全224x224の自動100%・広い全回帰・長期性能/難易度/楽しさ・物理入力・連続動画の読みやすさはNOT_RUN。通常全map100%は統合担当へ残す。細かい全障害物経路・全状態組合せを総当たりしていない。

本票の未解決FAILなし。実ユーザー保存3件は開始前後hash一致、Godotプロセス一覧0、override.cfgなし。ゲーム編集・Godot実行を停止し、freeze情報と実行権を親へ先に返却した。共有記録・状態票は子から更新せず、文書担当へ上記の承認実装/比較数値/初回FAILと限定修正/最終画像/NOT_RUNを渡す。コミット・stage・ブランチ切替・再委任・未知プロセス停止なし。最終合否とPoC3全体の受入は親の独立確認に委ねる。
