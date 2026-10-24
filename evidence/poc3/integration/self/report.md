# POC3-INTEGRATION 自己統合確認

2026-10-24。Windows / Godot 4.7.2.stable.official.ed1daf0bf、GPUはVulkan Forward+ / RTX 5070 Ti。共有ツリー。基準HEAD `45501239102cc0f3590d3b6f13ce6b7864d71e99`＋親が固定したREFLECTION world_view差分。実行中に親がREFLECTIONを`f8fd003`へコミットしたが、そのゲーム内容hashは同じ。最終版は本フォルダfreeze_after.jsonとactual_diff.patchで特定する。最終合否は親と独立検証へ返す。

## 変更

- `scripts/play/walker.gd`: EPSだけ`1e-4`→`5e-4`px。Vector2の反復substepで残る約0.0002pxの横ずれを境界接触として扱う。実足幅/移動速度/MAX_SUBSTEPは変更なし。許容0.0005pxは0.00005m。
- `scripts/poc2/poc2_main.gd`: `_exit_tree()`で既存Session.closeを呼び参照を解放。replace_sessionの旧Session close、Persistenceの候補closeと役割を揃えた。
- 本担当の`tests/poc3/integration/`と本証拠のみ追加。既存ゲームの変更は上記2ファイルだけ。共有資料/票/Git index/commit/push/CONTENT-01への変更なし。

## 結果（別走行を合算しない）

| 走行 | 結果 | 主な証拠 |
|---|---|---|
| core初回 | **14 PASS / 1 FAIL** | core.log / core_results.json。原移動FAILを保持 |
| Walker限定追試 | **4 PASS / 0 FAIL** | movement.log / movement_followup_results.json |
| 公開ゲームAPI通し | **10 PASS / 0 FAIL** | journey.log / journey_results.json |
| 最終通常GPU/UI接続 | **12 PASS / 0 FAIL**（撮影/接続条件） | gpu.log / gpu_results.json / PNG。連続反射の像は初回位置では未確認 |
| 最初の反射限定撮影（北橋岸） | 撮影5 PASS、**反射時系列の目視根拠として不十分** | water.log、north_fixture_*。成功総数へ加算しない |
| 有効な反射時系列（西岸） | **5 PASS / 0 FAIL**（撮影/接続）＋代表目視確認 | water_west.log / water_west.exit.json / water_followup_results.json / water_followup_0〜5.png |
| 正常終了前後 | 修正前39 ObjectDB / 21 resource残存、修正後いずれも0件 | startup_before_fix.*、startup_after_fix.*、startup_exit_followup.* |

native exit記録の留保: 初期PowerShell pipelineはstderr警告を例外化したためstartup.logはハーネス中断として保存し、stdout/stderr分離へ訂正してstartup_before_fixを取得した。Start-Processの速い終了でExitCodeがnullになるハーネス記録もmovement/journey/gpu/startup_after_fixに残る。これをnative exit0と報告していない。各SceneTreeは完走結果JSONを書いた後failuresに応じて明示quitし、runtime abortも未完走FAILへ反映する。以後はProcess.Handleを保持して待ち、exit nullを拒否する方式へ訂正した。西岸GPUと終了限定追試はnative exit0を取得した。ゲーム条件全部の再走はしていない。

共通runnerの初回JSON not_run欄には汎用の「GPU rendering」「unassisted player conquest」が残るが、実際のGPU確認範囲と小巣攻略は下記の実行/画像証拠に従う。最後に将来出力用ラベルだけ具体化し、既存raw JSONは書き換えていない。

## 重要回帰

全マップ: 新Sessionで全巣と敵へ実damage APIを与え、通常Session更新で安定を確認。その後に入力/直接stage書込/手播種/給水なしで**38,330/38,330対象セル**が緑化し、state.cleared/counters一致。孤立4×4は開始0/16→最終16/16。通常成長/自然拡張/遠距離播種の値とsignal接続を維持し、親承認の固定120ゲーム秒刻みを20回、最後だけ通常Session更新、計2401ゲーム秒。FarSeed上限3207.5秒以内。fair sweep実播種27,931、island播種1。緑化対象外を分母へ入れず、丸めで100%扱いしていない。全100%条件は修正前後で影響しないため再走なし。

この100%用Sessionは戦闘をdamage APIで設定しており、プレイヤーが全敵を実操作攻略した証拠ではない。加速中は空のcombat・収入・reveal・helper/crop仕事（未設置）を省略、Clockの成長/拡散順は維持。終わりにmax_advanceを戻して通常更新。敵/巣は空のまま再出現せず、安定地域のhostile nav経路も空。安定侵入の内部条件と生産個体報酬0は変更していないLOCUST/ENEMY-TIERS独立証拠も再利用する。

保存/資源: 実残高からクローバー設置/初回給水/3×3弾、着弾後9種決済。成長中/給水済/実支払費/お気に入り/播種幅/固定階級敵などの複合状態を実JSONで保存/復元し全状態一致。復元直後に時計・株年齢・種が勝手に増えない。明示的な種水0fixtureで実生産により種1へ回復、給水済株は成熟、水辺へ置くfixture後に通常更新で水20まで補給。資源0fixtureと岸への配置は通常開拓による到達結果と混同しない。

移動: 初回は通常Session.walkで北経路step9、(461.9998,418)→目標(462,414)、誤差4pxを再現。原FAILはcore_resultsへ保持。EPS限定修正後は北/南の斜め→軸経路とも完走、水際で足半幅2pxが水へ抜けない、空地で6px移動が維持されることを4条件だけ追試。

終了: 修正前の通常headless起動終了で39/21残存を実確認。main._exit_treeへ既存closeを接続後、同じ通常起動終了でObjectDB/resource警告は消えた。最後の終了限定追試はnative exit0。GPUでもmainをfreeして終了し、同残存警告はない。既存の37/20履歴ログは消していない。

## 公開ゲームAPIの通し

新規Sessionから資源・HP・unlocked・地形・主人公位置を直接注入せず実行。歩行はnavが示す経路へSession.walk、進行は通常advance_gameを使用。ゲーム時間の早送りとしてAPIへdtを供給したスクリプト経路であり、入力の使いやすさやプレイヤーの判断・難易度評価ではない。

1. 中央から探索化石へ歩き、実revealの接近回収でcarrot解放。
2. 最寄りboar小巣の32〜56px手前へ歩いて活動開始。通常fire3回・種バズーカ1回、通常の敵AI/衝突/HP/cooldown/種消費で巣を破壊。HP100、種96となり、巣化石のarmy解放を確認。
3. gatlinger・sprinkler探索化石へ歩いて回収。北spider前線へ歩いて活動を確認し、中央へ帰還。
4. 実残高からcarrot1株＋army/gatlinger/sprinkler各1体（Gat弾5）を設置。追加の収入待ちは0秒、残高1。給水、お気に入り登録、Army持ち場変更を行って0.25秒進行。
5. 稼働/移動中helper・栽培株・化石/巣記憶・残存敵/階級等を実JSONで保存/復元し全状態一致。再開後1ゲーム秒、全3helper/1株が残り実systemが進行。

この通しで全種の状態組合せや全巣を攻略していない。helper飛翔弾の特殊保存や有無比較を再実行せず、HELPERSの独立10 PASSと自己比較/弾保存証拠を再利用する。

## 実GPUの確認

new_start.pngは中央緑地・水路・主人公・5枠と種60を表示。map_helpers.pngはクォータ向き地形、主人公と3helperを表示。plant_list.pngはクローバー株1/現在価格11/+0.000種s、helper固定費と生産なし表示を確認。E/Tabで時間が止まり、mapを閉じる際の長押し左クリックが戦闘へ漏れない。640×360、nearest、整数拡大の実プロパティも確認。

sprite草mask: plant_list背景とwater_bank.pngでクローバーの白花が草の上に埋もれず見え、おたすけ3体が区別できる。最終world_viewの草mask集合差分版で撮影した。個別壁際/足元・全種の差替え基盤はSPRITE-VIEWの有効代表画像/CPU証拠も再利用。全対象の完成スプライトや美術承認ではない。

反射: 初回南岸(112,104)は鏡像が草地側へ投影されて水面像が読めず、次の北橋岸(111,55)も建物/木の遮蔽で不十分。いずれの撮影成功も連続反射目視PASSにしない。最後の西岸(108,98)は水が映る側にあり、実Session.walkで川沿いDOWN3回/UP3回、0.08秒×6=0.48ゲーム秒の短い連続区間を撮影した。water_followup_0〜5.pngで足元下の水面像を目視し、歩行frame0→1→2→3、反転時の形を読め、極端な潰れ/位置飛び/消失を認めない。actor.snapshotのmatching_feet/flip/texture、walking、640×360反射も全フレーム一致。親も最終0/2/3/5画像を見てこの代表時系列範囲を受入。全時刻/全角度のちらつき保証や動画全フレーム解析ではない。

GPU用のみの明示fixtureとして種500・helper解放を与え通常APIで株/3helperを配置した。時系列岸への位置設定も撮影用fixture。これらをゲーム内経済や探索成立の証拠へ流用していない。

起動前CreateNew override.cfgでno_focus=true/mode=1、root.unfocusable/MODE_MINIMIZEDを始終確認、offscreen SubViewport UPDATE_ALWAYS、force_draw(false)。OS入力/カーソル/前面化/復元なし。root.notify_mouse_entered重複の試験警告は出たが、ゲーム不具合や漏れに置換していない。自分で作ったoverrideだけをfinallyで解除。

## 既存証拠の再利用と範囲

preparation.mdの再利用表を継続する。SOURCE/保存方式/入力/価格/永久水/マップ検知の既存境界試験は全部再走せず、最終の実API通し/実JSON/UI接続で関連範囲を確認。HELPERS後のgame差分はREFLECTIONのworld_view内7行（環境辞書複製＋divisor1）と今回main終了/Walker EPSのみ。combatの報酬/LOCUST AI/Plants優先/価格/Persistence/検知/入力分岐を変えていないので、LOCUST/HELPERS/階級独立証拠を引き続き再利用可能と判断。共通Walkerへの影響だけ上記4条件と通しで確認した。

## 保全・未確認・引渡し

旧PoC/PoC2保存3件は読取hashだけで、先行HELPERS独立前hashと全件一致（old_saves_after.json）。隔離APPDATA/LOCALAPPDATA内だけを保存先に使用。project.godot・他者変更は保全。最後Godotプロセス0、override.cfgなし。Godot/importを親へ返却し、以後実行/編集停止。

NOT_RUN: 物理キーボード/マウス→OS→Godot経路、長時間の人間プレイ/楽しさ・最終バランス、全角度/時刻/画面条件、全スプライト完成素材、書き出しビルド、全マップをプレイヤー通常攻撃だけで攻略する走行。ユーザー試遊を代行しない。機能単位の独立証拠と今回統合結果をPOC3-VERIFYへ渡す。
