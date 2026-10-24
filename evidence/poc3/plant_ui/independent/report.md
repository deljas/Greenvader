# POC3-PLANT-UI 独立限定確認

**9 PASS / 0 FAIL / 3 NOT_RUN。** 対象はHEAD `b5e68bfa61337819e874fa07221a0058ede63e7b` + PLANT-UIゲーム7ファイル。self/context.jsonのfinal_hashes（ゲーム7/自己試験3）と実ファイルを前後照合して全件一致。Windows NT 10.0.26200.0 / Godot 4.7.2-stable、headlessで1回実行。実diff/前後hashと観測は [results.json](results.json)、原ログは [run.log](run.log)。新規UI3ファイルも実コードを読んだ。

| 独立条件 | 結果 | 観測 |
|---|---|---|
| 未成熟を含む数・成熟のみ実生産 | PASS | 通常worldへ実配置したclover3株中2株成熟・1株未成熟。現存3、表示対象実生産0.0666667/s、実crop_rate4/min。緑地5/min込みの1ゲーム秒収入は0.15で未成熟株の生産加算なし |
| 指定桁・非生産・成熟1株説明 | PASS | 0.5→+0.500、1→+1.00、100→+100.0、非生産—。実行のclover行は株3/実生産+0.067 ●/s、成熟1株hoverは+0.033 ●/s |
| 解放済み限定とrank/同rank順 | PASS | 初期一覧はcloverだけ。全解放時はclover,carrot,army,wheat,gatlinger,sprinkler,rafflesia,watermelonの独立期待順と一致 |
| 5枠・同枠解除・重複種の別枠切替・HUD | PASS | 5個の枠、KEY1で選択/解除、同種のKEY2へslot単位切替。選択cost10/種60/主人公HP100・水100を確認 |
| E停止・クリック保持登録・選択枠上書き | PASS | E一覧中は時計停止、番号キーは背後選択を変更しない。carrot行クリックは登録保持のみ、選択中枠の上書きで旧設置選択を解除 |
| Button上の右クリック取消 | PASS | army行を保持した後、その子Button上で右クリック。保持解除、一覧継続、元5枠不変 |
| 代表D&D | PASS | Viewportのmouse motion/press/releaseで実engine drag状態を観測し、一覧cloverを第5枠へ登録。保持も終了 |
| 閉じた保持クリックの漏れなし | PASS | UI由来の右保持・左保持をそれぞれEで閉じ、世界側でtick。射撃なし、種/水消費なし、_primary/_secondaryは作動しない |
| 保存往復・不正値拒否・以前のPoC3既定値 | PASS | 実UI登録した5枠が隔離保存/読込で一致。数値を混ぜた不正favoritesは拒否し現行snapshot不変。favorites欠落はclover+空4へ復元 |
| 独立GPU/native外観/物理入力 | NOT_RUN | 提供画像を目視したのみ。OS入力・前面化・実カーソル操作なし |
| 広い回帰/長時間 | NOT_RUN | 主要境界と集計・保存に限定。自己全条件の再走なし |
| 全サイズ/全照明/書き出し後動作 | NOT_RUN | 今回の対象外 |

期待値は票/仕様の枠単位操作、成熟のみの収入、3/2/1桁表示から導いた。集計fixtureは正常worldの実配置で作り、保存には別の通常ゲームsessionを使用した。仮の最小entity配列を保存の正解へ流用していない。入力は全てheadlessのViewport.push_input。原ログにnotify_mouse_enteredの重複通知WARNINGが1件あるが、試験コードの通知に起因し、ゲームのエラー・検証FAIL・終了残存診断はない。

self/hud.pngとplant_list.pngを実際に開き、640×360内の左下5枠と番号、右上選択/現在cost/種/HP水バー、一覧の8行/名前/株/種生産/s/価格、成熟1株の説明を目視した。字形と画素は明瞭。自己D&Dのui_results.jsonと試験ソースは実engine drag状態を検査していることを確認し、独立でも代表1操作のみ実行した。連続配置は、自己engineの2連続配置記録と、_placeが選択を保持する実コードを照合した範囲であり独立再走していない。

自己backend12 PASS、初回UI18 PASS/1 FAIL、修正後限定2 PASSは別々の履歴として保持し、独立結果へ合算/上書きしていない。修正はplant_listのvisible時_inputで右取消を先に処理するものと確認した。

直前CONTENT-01は第1段階/共有資源なし、Godot0件。APPDATA/LOCALAPPDATA/user_dataは当該profileへ隔離。実ユーザー旧save3件は読取hashのみで前後一致。終了時Godot0件。WORLD-LAYOUT未接続準備は対象外として保持した。

ゲーム/文書/票/Gitは未編集、割当independent試験と証拠だけ追加。再委任/commit/stage/branch/pushなし。Godot/import権を親へ返却し、編集停止。最終受入は親判断。
