# POC3-PLANT-UI 自己報告

- 対象版: HEAD `b5e68bfa61337819e874fa07221a0058ede63e7b`（MAP-INFO受入済み）+ 今回PLANT差分。最終ゲーム7ファイル/試験3本SHA256は `context.json` のfinal_hashes。初回試験時のhashはinitial_hashes。shared treeの他担当成果は保持、子stage/commit/branch/pushなし。
- 変更ファイル: `poc2_main.gd`、`poc2_session.gd`、`simulation/persistence.gd`、`ui/poc2_ui.gd`、新規 `ui/plant_list.gd` / `favorite_slot.gd` / `plant_list_row.gd`、自己試験/証拠とGodot付随uid。MAPのcombat/map_ui/world_view/camera_geometryを変更していない。共有文書/作業票は子から未編集。
- 通常UI: 左下5枠+E一覧、クリック/1〜5で同枠解除・別枠切替。初期clover+空4、重複可でslot単位選択。配置後も選択維持。右上に選択icon/現在cost/共通所持種/緑化率と主人公HP/水バー。既存symbolを使用し新美術なし。
- 一覧: 解放済みのみ、承認rank順/同rank既存KEYS順。名前/icon/未成熟含む生存現存数/成熟した生存株の実生産s/現在cost。hover説明+成熟1株rate、非生産—、生産は+数値 ●/sで1未満3桁/100未満2桁/以上1桁。スクロール、クリック保持→枠、Godot D&D、上書き、Esc/右クリック取消。取消は元枠不変。選択中slotの上書きで設置選択を解除。
- API/保存: session.favorites、set_favorite(index,kind)、current_cost(kind)、plant_stats(kind)={count,rate_per_second}。current_costは今回は基礎costを返しUI/HUD/ガトリンガー投入dialogで共用。実際の価格倍率/決済への接続は後段CROP-PRICINGで、plants.gdは未変更。5個string/空か既知解放済みだけを保存検証、旧PoC3で欠落時は初期5枠。不正値は既存session保存状態不変で拒否。
- 時間/入力: E一覧でpause、閉じて以前の通常/ポーズ状態へ復帰。一覧中1〜5は背後選択を変えない。背景map/helpボタンを隠しsignal側もmodal guard。mouse releaseは_inputで必ずdisarmし、armは未処理のworld pressだけ。mode遷移で長押し/移動キーをclear。UI-origin holdを閉じた後の射撃/散水へ継承しない。Q/R/M/N/Shiftの全体改定は後続INPUTの範囲。
- import: Godot 4.7.2 headless import 1回、exit0、ログエラーなし。`import.log`。
- backend自己: `logic_results.json`、12 PASS / 0 FAIL、exit0。初期値/重複/拒否、未成熟数と成熟のみ実生産、基礎price API、桁境界/非生産、正常保存往復/欠落初期値、不正長さ/非string/未知/未解放の拒否とsession不変を各代表1回。集計用の最小fixtureと保存用正常worldは分離。
- UI初回: `ui_results.json`、18 PASS / 1 FAIL、exit1をそのまま保持。Viewport.push_inputのengine click/key/motionで新規、同枠解除/同種別枠切替、2連続配置、E停止、rank順、番号抑止、クリック保持登録/上書き選択解除、Esc取消、実D&D登録/取消、UI左長押し漏れなし、HUD/hover/640px撮影を確認。右クリック取消だけFAIL。
- 修正/限定追試: 子Buttonが右クリックをGUI段階で消費しpanelへ届かなかった。plant_listの_inputでvisible時だけ取消を先に受ける修正。`cancel_followup.json`、2 PASS / 0 FAIL、exit0（行上の右取消/元枠維持、右保持のままE閉→世界で散水/射撃なし）。全UI19/logic12/撮影は再走せず、初回FAILを上書き/合算しない。後の修正は入力取消だけで初回backend/GPU表示経路へ影響なし。
- GPU画像: `hud.png` / `plant_list.png` を目視。5枠と番号、右上の選択/種/主人公バー、8解放行の名前/株/実生産/価格、hover成熟rateが640×360内で読める。内部nearest/整数表示を維持。初回画像は右取消修正前の対象で、表示コードは追試時変更なし。
- 安全/保存保全: 各実行前CONTENT-01共有資源なし/Godot0を確認。APPDATA/LOCALAPPDATAは自己profileへ隔離。起動前override no_focus=true/mode1を作りtry/finally除去、開始/終了でruntime最小化/フォーカス禁止を確認。撮影は復元せずUPDATE_ALWAYSの640px SubViewportへcanvasを移して取得。OS入力/前面化/カーソル操作なし。実ユーザー旧保存3件の一覧/SHA256は初回/限定追試後とも一致。
- NOT_RUN: 物理入力、native窓外観、全サイズ/全照明、広い回帰/長時間、他キー/Shiftの全操作再設計、後続価格倍率。GUIは検証用のengine注入であり実マウス/キーボード経路の保証ではない。
- 終了/文書担当へ: 最終hashはcontext.json、Godot0/override除去、編集/実行停止。上記操作/API/保存互換/限定結果とNOT_RUNをガイド/検証記録へ渡す。独立検証と親の技術受入を待ち、PoC3全体完成やユーザーのUI評価を代行しない。
