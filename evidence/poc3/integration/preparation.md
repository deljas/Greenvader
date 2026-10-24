# POC3-INTEGRATION 準備記録

2026-10-24。対象読取版: `dc2033baed11be964f1fd423da742f6efe0def27` + LOCUST作業差分。共有ツリー。**準備だけであり、全ゲーム実行条件は NOT_RUN。GDScript構文検証・Godot import・ゲーム起動・画像確認も未実施。** PowerShellのParseFileによるラッパー構文確認だけPASS（ラッパー自体は実行していない）。ゲーム・設定・資料・作業票・Git indexは変更していない。CONTENT-01は対象外。

読取: AGENTS.md、tasks/README.md、POC3_INTEGRATION.md、TASK_TEMPLATE.md、docs/00_README.md、01/02/03/04、STATUS/DECISIONS、POC3_SPEC、Session/Combat/Plants/Persistence/Save/Navigation、Clock/FarSeed/Spread、既存PoC3試験と独立記録。GDScript/headless testingスキルを使用した。

## 実行順と凍結

1. HELPERS/LOCUST/REFLECTIONの親受入後、親が対象HEAD・全ゲーム差分hash・`git --no-optional-locks status`を保存。各独立証拠の対象hashと、その後変更した機能を照合する。同じファイルに変更があっただけで一律無効にせず、実際の影響を読む。影響があれば下表の最終接続条件で確認する。
2. 本担当へGodot/import所有が渡ってから、必要なimportを1回。隔離APPDATA/LOCALAPPDATA、旧PoC/PoC2保存3件は前後hash読取のみ。
3. `self_core.gd`を1回。失敗やruntime abortを非0終了にする。原FAILを保存し、修正後は失敗と影響分だけを別ログで追試する。
4. 下表の通し後半と、通常画面GPU代表接続を各1回。既存独立試験全件の再走はしない。
5. 正常起動/終了をheadlessで代表1回。ObjectDB/resource残存の有無をログで比較し、未解消なら親へ返す。終了処理に修正が入ったら影響終了条件だけ再取得。
6. 対象版を凍結してPOC3-VERIFYへ渡す。ユーザーの物理入力、楽しさ、完成美術を代行したことにしない。

## 準備した試験

- `tests/poc3/integration/self_core.gd`: 新Sessionの中央/資源、実残高からクローバー設置・初回給水、3×3弾の着弾決済、成長中/給水済/実支払費/お気に入り/播種幅/階級付き敵などの実JSON複合保存。復元直後の時計・株年齢・所持種不変。種水0の明示fixtureで生産回復と水辺補給。Session.walkを用いる北巣への斜め→軸経路。別Sessionでdamage APIにより全巣/敵撃破後、安定・hostile経路禁止・全マップ自動100%・孤立4×4を確認する準備。
- `tests/poc3/integration/self_run.ps1`: 隔離profile、親の実行許可を表す`-Authorized`が必須。core / 通常headless起動終了の2モード。スクリプトエラーを終了0のまま通さない。実行は現在禁止。

全100%は親承認の**固定120ゲーム秒刻み1方式**を使用。通常のSession.advance_gameは0.25秒ごとに実処理し、0.5秒ごとの全セルrevealが長時間試験を重くするため、全敵が実damage APIで排除され、実Session更新で安定を確認した後だけ、既存Clockのmax_advanceを120へ一時変更する。既存clock→growth/spread/far signalはそのまま、通常の周期順に実行する。成熟閾値、給水倍率、自然拡張倍率、播種/走査予算は変えない。通常Clock値へ戻しSession更新で完了判定する。省略対象は敵排除後の空combat・収入・定期reveal・植物仕事（この専用Sessionでは未設置）。直接のstage埋めや緑化カウンタ書込、手播種、補助植物、追加給水を使わない。

全50176セルに対するtarget/greened実数、島のtarget/開始時green/最終green、ゲーム秒、far保証上限、実sweep/island播種数、刻み、省略対象を記録する。これは戦闘を含めたプレイヤー攻略所要時間の測定ではない。

## 有効性確認して再利用する既存証拠

| 範囲 | 主な既存証拠 | 再実行しない条件 | 最終接続で追加する条件 |
|---|---|---|---|
| SOURCE / SAVE-BASE | `source/independent/report.md`、`save_base/independent/report.md` | 単一通常bat、旧保存分離、形式拒否 | 最終入口・通常終了、旧保存hash、複合JSON |
| VISIBILITY / MAP-INFO | `visibility/independent/report.md`、`map_info/independent/report.md` | 距離描画、現在敵検知、固定巣/化石記憶、過渡検知修正 | 最終マップ上のLOCUST/HELPERS/化石表示を代表画像で確認 |
| PLANT-UI / INPUT / AREA-SEED | 各`independent/report.md` | 桁数境界、5枠登録、全Shift/長押し境界、1/3/5/7、着弾再精算/返還 | 上記実3×3弾、UI停止/閉じた後の入力漏れを1経路で確認 |
| WATER-GROWTH / CROP-PRICING | 各`independent/report.md` | 乾/湿2倍、永続/非加算、価格同種/実支払返還 | 成長中給水株の保存→続行、種水切れ回復 |
| WORLD-LAYOUT / ENEMY-TIERS | 各`independent/report.md` | 中央円177/水辺/距離帯、固定階級倍率/境界/不正型 | Session.walk既知精度、複数前線から安定、複合保存 |
| SPRITE-VIEW | `sprite_view/independent/report.md` | サイズ/足元/判定分離の代表ロジック | 最終mask版の通常GPU、HELPERS/LOCUST行動本接続 |
| LOCUST | 親受入後に`locust/independent/report.md`を確認 | 群れ/食害/再生/初期vs生産報酬/保存/安定等 | 通し内の迎撃と表示、全100% |
| HELPERS | 親受入後の独立報告・有無比較 | Army/Gat/Sprinklerの有無差・優先/範囲/退避/補給/待機 | 最終通常画面/マップ仕事表示と複合保存 |
| REFLECTION | 親受入後の独立報告・比較GPU | 同一場面の320/640比較・静止/歩行/方向転換・負荷 | 最終ゲームの水辺に設定/表示が接続していること |

パスの基点は`evidence/poc3/`。この表は**証拠を再利用する計画**で、将来版での有効性や未実施機能のPASSを宣言していない。

## 最終通し後半（依存凍結後に最小限接続）

| 経路 | 手法と記録 | 現在 |
|---|---|---|
| 化石探索→解放→配置 | 最寄り探索化石へSession.walk＋advance_game、revealの実接近回収でcarrot解放、公開配置APIで1株。探索の瞬間移動やunlocked直接追加を成功の根拠にしない | NOT_RUN / 凍結後に短い通しへ接続 |
| 近巣→別方向前線 | 到達位置と接近/緑化による巣activeを記録、2方向で条件差を確認。戦闘はfire/skill等の実APIを使用。攻略準備として敵HP/所持種/位置を強制する場合はfixtureとして別記し、プレイ成立と混同しない | NOT_RUN |
| 生産個体報酬0→巣報酬 | 初期個体と生産個体を区別。実撃破前後の備蓄差、巣の報酬と化石解放を記録。既存LOCUST/階級証拠と重複する全倍率再走はしない | NOT_RUN |
| helper込み複合保存 | 実APIで解放・設置・補給・移設したhelper、飛翔弾、永続水、実支払費、発見記憶を同時に保存/読込。全state一致＋再開後短い1仕事を確認。1体ずつ全状態組合せ網羅はしない | NOT_RUN / HELPERSの確定字段待ち |
| 通常画面/Tab/E/Shift | エンジン内入力のみ。範囲播種→Tab停止/マップ植物表示→E一覧/価格→閉じる時に戦闘漏れ無し。通常640×360/マップ/水辺の代表3画像程度 | NOT_RUN |
| 安定後の侵入 | stable Sessionのhostile経路禁止と、実combat経由の活動/侵入禁止を短い1条件。手動で無効なstable内敵をspawnして回避する試験にしない | NOT_RUN / 既存LOCUST安定証拠と実装差分を照合 |

GPU起動は既存`tests/poc3/reflection/self_run.ps1`等の安全方式を再利用する。所有確認後、既存override.cfgが無い場合だけCreateNewで`no_focus=true` / `mode=1`。root.unfocusable/Window.MODE_MINIMIZEDを起動直後・終了前に検証、別SubViewport.UPDATE_ALWAYSから撮影、RenderingServer.force_draw(false)。OS入力・カーソル・前面化・ウィンドウ復元はしない。現在はGPUスクリプトも起動も未実施。

## 既知課題

1. 通常終了でObjectDB37/resources20。main._exit_tree不在は仮説で、修正していない。既存close呼出し/Scene参照の所有を読んだ。通常起動終了の生ログを残して親の限定修正判断へ返す。
2. WORLDの北/南AStar経路で約0.0002px残差からWalkerが次軸へ進めない原FAIL。self_coreは北経路をSession.walkで再現する準備。失敗後に別経路へ差替えて解消扱いにしない。最終ゲームへの支障と原因を親が判断する。

## 停止状態

Godot/import実行なし、ゲーム/共有資料/票/Git操作なし。準備ファイルだけ。実行許可と全依存凍結まで停止する。全実行結果、描画、未接続の後半通し、性能、楽しさはNOT_RUN。
