# POC3-MAP-INFO 自己報告

- 対象版: 調査開始HEAD `77e3463`、実装/試験基準は親のVISIBILITY確定後 `b2420865b900c1f5e91f8fa0827bb48e17c9318c`。他担当の資料/作業票変更を保持。最終HEAD、変更ゲーム6ファイル/試験2本のSHA256は `context.json`。childによるstage/commit/branch/pushなし。
- 変更ファイル: `poc2_session.gd`、`simulation/combat.gd`（初期discoveredだけ）、`simulation/persistence.gd`、`ui/map_ui.gd`、`view/world_view.gd`（camera接続だけ）、新規 `view/camera_geometry.gd`。自己試験 `self_logic.gd` / `self_gpu.gd` とGodot付随uid、当該自己証拠。
- 実装: 既存の45度yaw/30度elevation/18.5m/640×360とtarget画素snapを純粋helperへ抽出。実world cameraとsessionの検知に共有。通常画面内OR生存helperの既存72logic半径OR発芽以降の緑化セルで現在検知。主人公の旧72円は通常cameraへ置換し重ねない。地形knownは履歴、visibleは現在のセル状態として保持し、entityは丸め誤差を避け実位置で判定。建物遮蔽は検知条件へ追加しない。
- 記憶/表示: 固定巣はdiscovered、未発見非表示・現在検知時通常四角・検知外は淡色四角・死亡/破壊で消去。母クモは現在検知時だけ菱形で、discovered記憶を使わない。探索化石はfoundと別のdiscoveredを持ち、回収まで骨型を保持。ミニ/全体マップは同じstyle/描画関数で文字なし。shape最大半径に応じて全体マップ端の内側余白を確保し、既存の味方選択範囲は維持。
- 回収/保存: マップ発見で植物を解放しない。既存12logic接近回収と巣破壊時の報酬解放を維持。discoveredは通常entity保存へ含み、存在時はbool必須。不在の既存PoC3作業版stateのみ保守的falseを補完。旧PoC2の外包/内包拒否は変更しない。保存先もpoc3_savesのまま。
- import: Godot 4.7.2、隔離profileで1回成功、exit 0、エラーなし。`import.log`。
- ロジック: `logic_results.json`、17 PASS / 0 FAIL、各代表条件1回。通常cameraへの置換/旧円非重複、helper72境界、遠方緑地、播種直後非検知、緑地喪失後の敵非表示/known保持、固定巣発見と淡色記憶/破壊消去、母クモ検知外消去、化石検知のみ未解放/緑地喪失後記憶/接近回収/巣報酬、発見保存往復、以前のPoC3欠落false、nests/fossils不正discovered型拒否と保存状態不変、旧PoC2拒否を確認。
- GPU: `gpu_results.json`、9 PASS / 0 FAIL。式を写した期待値だけで判定せず、実world_viewのCamera3D rayで生成した地面点とengine unproject_position/frustum結果をhelperへ照合。画面内/外の各辺を含む7代表点で画面誤差0.02px未満・in/out一致。fractional移動後の画素snap一致も確認。map zoomで通常camera検知が変わらないことを確認。
- 初回画像: `minimap.png` / `fullmap.png`（全体マップzoom4）を目視し、敵の点、親玉の菱形、通常/記憶の固定巣四角、現在/記憶の化石骨型を確認。ただし初回minimapはknown.fill(1)/位置変更後の地形cacheを明示更新せず、0.5秒更新前の旧cacheを撮影して地形が暗かった。初回GPU9 PASSは投影/取得/形状等の限定結果であり、初回miniの地形描画が正しかったという結果ではない。内部640×360、nearest、整数表示を維持。表示fixtureの全known/地面stage変更は検証用session内だけで保存せず、ロジックの保存往復には別の整合したSessionを使用。
- 実行制約: CONTENT-01共有資源なし/Godot0件を直前確認。APPDATA/LOCALAPPDATAは自己 `profile/` 下。root override.cfgの既存なし確認後、起動前にno_focus=true / mode=1を設定しtry/finallyで除去。内容 `startup_override.cfg`。runtimeと終了時にも最小化/フォーカス禁止を確認。最小化を解除せず、通常ゲームのcanvasをUPDATE_ALWAYSの640px SubViewportへ移してGPU撮影。復元/前面化/OS入力/カーソル操作なし。nativeウィンドウ外観とは区別する。
- 保存保全/終了: 実ユーザー旧PoC/PoC2の3保存ファイル一覧/SHA256が前後一致（実poc3保存は存在なし）。runtimeの保存操作は隔離profileのみ。override除去・Godot0件を `context.json` へ記録。ゲーム/自己試験の編集と実行停止。
- NOT_RUN: 物理入力、nativeウィンドウ外観、全照明/全サイズ、長時間/広い回帰、建物遮蔽回帰、ゲーム体験評価。これらを合格へ読み替えない。
- 付随生成: `tests/poc3/visibility/independent_visibility.gd.uid` がimportで生成。割当外のため削除/編集せず親へ報告。
- 文書担当へ: 上記検知3条件とentity種類別記憶・回収条件、discovered保存/保守的補完、17+9の別々の限定結果とNOT_RUNを記録へ渡す。共有STATUS/仕様/作業票は子から未編集。PoC3全体の受入・完成を意味しない。

## ミニマップ地形cache追補

- 親レビューを受け、ゲーム6ファイルを変更せず自己fixtureだけ `self_minimap_followup.gd` を追加。known/位置変更後に `map.refresh_terrain()` を明示し、同じ最小化/no_focus/隔離profileで1回だけ実行。旧minimap.png/gpu結果は保持し、logic17/全GPU9は再走していない。
- `minimap_followup.png` は640px画像取得成功。地形可視判定true、最小化mode1とno_focus trueを保持。目視では地面・水路・建物と、敵点/親玉菱形/固定巣四角/淡色記憶巣/化石骨型が見えることを確認。
- 追加probeの固定色assertは誤り: cell(112,112)を荒地色676856と決め打ちしたが、マップJSONのwater矩形 `[109,1,6,222]` に含まれ、sessionの地形順序ではwater=3、map描画の期待色は4d8eab。したがって `known_ground_source_matches=false` による **FAIL / exit 1** をそのまま保持する。画像取得・地形可視・安全状態の成功と、誤った色assertの失敗を区別し、自動FAILをPASSへ上書きしていない。実際のsource pixel値の再計測や追加実行はせず、親の指示どおりデータと画像の目視で補足した。
- 結果/ログは `minimap_followup.json` / `.log`。最後のtest SHA256 `93205531C495A296EA7E3EC7105DC562987ACC566854BBF7458409383ACB4B79`、ゲーム6ファイルhash不変をcontext.jsonに記録。override除去・Godot0件、編集/実行停止。
