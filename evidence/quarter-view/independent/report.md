# TECH-QV-01 独立検証（初回凍結版）

2026-10-15。最終受入判断は親。共有記録文書、ゲーム実装、素材、設定は編集していない。

## 対象と環境

- HEAD `99013702eaf36db72a64d60d284680fb834f13c5` ＋ `../self/source-manifest.json` の未コミット8件。
- `source-before.json` / `source-after.json`: 凍結8件すべてSHA256一致。通常ゲーム127ファイルも不変（`integrity.json`）。
- Windows 10.0.26200 / Godot 4.7.2 stable official.ed1daf0bf / Vulkan Forward+ / NVIDIA GeForce RTX 5070 Ti。
- 専用試験は実GPU Window、960内部画像とPrintWindowの実1920×1080 client画像を取得。root.unfocusable=true、Hidden起動。OS入力・カーソル移動・前面化APIは使用していない。APPDATAは検証専用runtimeへ分離、終了後この専用runtimeだけ削除。全Godot終了を確認。
- 独立試験: `tests/quarter_view/independent_checks.gd`。GPU一巡、マウス経路の限定切り分け1回、別プロセス通常ゲームスモーク1回。物理入力や大規模ゲーム回帰は実行していない。

## 合格条件別

| 条件 | 結果 | 独立証拠 |
|---|---|---|
| 1 専用シーン起動・通常ファイル保全 | PASS | 専用シーンを実GPUでinstantiate、通常ゲーム127ファイル不変、別プロセス通常ゲームsmoke PASS。通常ゲームは640×360 / Window1280×720、512セル幅の地域で起動 |
| 2 960×540の建物・通路・低障害物 | PASS | `front_960.png` を目視。大建物と周囲の地面、低障害物を視認。単純な仮色面での成立確認で、美術承認ではない |
| 3 前横後の順序・遮蔽 | PASS | 前/左側面手前/右側面手前で既存花の不透明82画素がすべて原画と一致。背面は不透明時0/82、透過時に花が認識できる。各PNGを目視。`behind_opaque_960.png` / `behind_faded_960.png` |
| 4 足元境界と周回 | PASS | 四面の停止位置(302,340),(450,340),(376,270),(376,418)が期待値と一致。建物から論理4単位離した一周通路を通過。低障害物も(478,330)で接触。見える基底と衝突が同じfootprint由来であることをソースでも確認 |
| 5 画面方向と斜め等速 | PASS | 実際のphysics入力経路へW、D+SをInput.parse_input_event。0.25秒で画面上(0,-25.00427)、(17.67773,17.67773)。仕様100px/sに対し0.05px許容。許容は表示1pxより十分小さく、結果から閾値変更なし |
| 6 カメラ込みマウス逆変換とセル | FAIL / 部分PASS | 逆変換とマーカーは既知画面(494,413)→論理(550,466) / セル(137,116)へ一致しPASS。エンジンイベント注入を現在マウス位置として読む経路はFAIL。下記再現と `mouse.log`、`mouse_marker_960.png` 参照 |
| 7 斜め移動・カメラの画素 | PASS（限定） | 小数論理位置から斜め移動後、花(41,581)、カメラ(41,521)、canvas平行移動(439,-251)が整数。nearest、zoom1、非変形16×16花を確認。`diagonal_camera_960.png`目視。連続動画/全位置の網羅ではない |
| 8 実1080で正確な2倍 | PASS | 同一固定フレーム `same_frame_original_960.png` と `native_1080.png`。518400ブロックの原画不一致0、2×2ブロック内不均一0。テスト側CPU拡大による代用なし |
| 9 素材条件と統合課題 | PASS（技術値） | 次節の値をソースと投影から確認。最終制作条件文書への反映と受入は親の範囲 |

## マウス入力の失敗と再現

- 重大度: 中（自動入力経路の試験不能）。実マウス経路が壊れている証拠とは扱わない。
- 対象: `scripts/quarter_view_lab/lab.gd` の `_physics_process()` が `get_viewport().get_mouse_position()` を取得する箇所。独立試験 `run_lab()` と `--mouse-only` の診断経路。
- 最小再現: 専用シーン、camera_follow=false、camera=(70,365)に固定。画面(494,413)のInputEventMouseMotionをInput.parse_input_event、flush後にphysics(0)を呼ぶ。期待論理(550,466)、実論理(1241.5,286.5)。初回 `gpu.log` / `results.json` にFAIL保持。
- 限定切り分け: 同じ位置を `root.notify_mouse_entered()` → `root.push_input(event,true)` で注入。event=(494,413)に対しviewport.get_mouse_position=(1343,653)、論理(1214.5,281.5)。`mouse.log` / `mouse-results.json` にFAIL保持。
- 同じ場で公開 `set_mouse_screen(Vector2(494,413))` を呼ぶと期待論理(550,466)、セル(137,116)に一致。従ってカメラ込み変換自体はPASS、イベントと現在マウス位置取得の接続が独立試験で確認できなかった。
- 公式根拠: [Input.parse_input_event](https://docs.godotengine.org/en/stable/classes/class_input.html#class-input-method-parse-input-event) はOSカーソルを移動しない。[Viewport.push_input](https://docs.godotengine.org/en/stable/classes/class_viewport.html#class-viewport-method-push-input) のlocal座標指定も使用した。これ以上の注入方式試行は行わず親へ返却。
- 親へ報告済み。ゲーム修正は独立検証者から行っていない。親から実装者への修正戻し予定。変更後はマウス条件のみ対象版を更新して再取得する。

## 素材へ渡せる確認値

- 状態セル4×4論理単位は外接8×4px菱形。16×16論理素材なら32×16px、32×32なら64×32px。美術単位と緑化セルを同一視しない。
- 大建物footprint144×144、高さ112画面px、外接288×256px。画像原点は南の足元角(144,256)。基底4角は(144,112),(288,184),(144,256),(0,184)。
- 低障害物footprint48×24、高さ12、外接72×48px。衝突は地面footprint、屋根高さは表示のみ。
- 1px幅の表示列ごとに前端足元を持ち、花と同じY-sort親に配置。左右側面試験の82画素一致が、南角一点でソートしない必要性と今回の成立を示す。
- 屋根/壁は制作レイヤーを分け、帯/列の深度メタデータを保持する。門・アーチ・ひさし等の複雑形状は今回の閉じた箱では未検証で、別partが必要な候補として渡す。
- nearest/非回転/整数表示、花は既存16×16。地面に広域の明暗グラデーションなし。

## NOT_RUNと試験側の診断

- 物理キーボード/マウス→OS→Godot、起動前後フォーカスの読取り比較、Windows書き出し後、他解像度、長時間/性能、大規模成長/保存/戦闘、複雑建物の重なり、通常ゲーム統合はNOT_RUN。
- 最初の試験起動は定数名ProjectionとGodot組込み型の衝突でparse時に終了。ゲーム条件は一つも実行していない。試験側定数のみQuarterMapへ修正して一巡した。`harness-parse-initial.log`を保持。
- 初回一巡の13 PASS / 1 FAIL、限定マウス切り分け1 PASS / 1 FAIL、通常スモーク1 PASS。重複条件を合算して合格数を増やさない。各試験の物理入力はNOT_RUN。
- 通常ゲームGPUスモーク画像は `normal_game_smoke_640.png`、ログは `smoke.log`。共有設定への専用960持ち越しなし。

## 起動例

`C:\godot\Godot_v4.7.2-stable_win64_console.exe --path C:/godot/greenvader --script res://tests/quarter_view/independent_checks.gd --log-file <専用ログ>`

限定マウス診断は末尾 `-- --mouse-only`、通常スモークは別プロセスで `-- --smoke`。実行権を親へ返却済みのため、再実行は調整後に行う。

## r2限定再検証（2026-10-15）

親が実装者へ修正を戻した後、`../self/source-manifest-r2.json` の9ファイルを新対象として固定。lab.gd SHA256は `90dc921293d7e0b4a461ecebf4f03b76ad85fe1a791c809789fa7ede9d962830`。実差分はマウス画面位置の保持、初回取得、`_input(MouseMotion)`での更新、physicsで保持位置を既存逆変換へ渡す変更。ゲーム実装は独立検証者から編集していない。

独立テスト `tests/quarter_view/independent_mouse_r2.gd` を実GPUで1回実行。初回一巡や通常ゲームスモークは繰り返していない。結果は `mouse-r2-results.json` / `mouse-r2.log`、版固定は `source-r2-before.json` / `source-r2-after.json`。

| 再検証条件 | 結果 | 実結果 |
|---|---|---|
| Input.parse_input_eventで既知位置→地面座標とセル | PASS | camera=(70,365)、event=(494,413)→保持位置(494,413)、論理(550,466)、セル(137,116)。r1の同再現が解消 |
| マウス静止・カメラだけ移動 | PASS | camera=(100,385)、新イベントなし→保持位置(494,413)のまま、論理(585,471)、セル(146,117) |
| マーカー実画素 | PASS | GPU960×540、セル中心の画面(496,413)が黄色。マーカー非表示の地面参照と比較し、期待する8×4範囲に菱形16画素の差。`r2_camera_reprojected_marker_960.png` を目視 |

r2は3 PASS / 0 FAIL、物理OSマウスはNOT_RUN。r1の13 PASS / 1 FAILと切り分けFAILのJSON・ログは改変せず保持する。合格条件6のイベント経路について、r2で解消を確認。その他の条件はr1で取得した範囲の証拠であり、r2で再走したものとは扱わない。

低重要度の観測: 情報ラベルは `present()` が `set_mouse_screen()` より先のため、単発physics直後のセル文字列が1 tick前になる（初回画像は0,0、次の画像は137,116）。マーカー位置と内部セル値は同tickで正しく、通常連続physicsでは次tickに文字列も更新する。親へ事実を報告済み。今回のマーカー条件の阻害とは扱っていない。

`integrity-r2.json`: 凍結9ファイル不変、通常ゲーム127ファイル不変、Godotプロセス0。専用runtime-r2だけ絶対パスを確認して削除。OS入力・前面化・カーソル移動なし。GPU/import実行権を親へ返却。
