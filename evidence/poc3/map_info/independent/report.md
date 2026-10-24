# POC3-MAP-INFO 限定独立検証

**11 PASS / 1 FAIL / 3 NOT_RUN。固定巣の一時検知で発見記憶が失われるFAILが残る。最終受入は親判断。**

対象は共有tree HEAD `b2420865b900c1f5e91f8fa0827bb48e17c9318c` + 指定6ゲームファイル差分。前後のHEADは同じ。self/context.jsonのゲーム6件・自己試験2件のhashと実ファイルを前後照合し全件一致。各hashと実diff、新camera_geometryの全文は [results.json](results.json) のcontextに保存。Windows NT 10.0.26200.0、Godot 4.7.2-stable official `ed1daf0bf001b61586d9930840f2f1394092c079`。独立実行はheadlessだけで、APPDATA/LOCALAPPDATAと実user_dataは本証拠内profileへ隔離した。

## 条件別結果

| 条件 | 結果 | 独立観測 |
|---|---|---|
| 通常カメラが検知源となり未検知遠方は隠す | PASS | player600,600に対しcamera内680,600は検知、遠方162,202は未検知。未発見固定巣も非表示 |
| 生存おたすけが独立した検知源となる | PASS | 遠方helper122,202から敵162,202を検知。helperのHP0で検知を失う |
| 固定巣の発見/離脱淡色/死亡と母の非記憶 | PASS | revealを通した発見後、固定巣は淡色四角、死亡時は消える。母は検知中に通常敵の点と違う形、離脱後はdiscovered=trueでさえ非表示 |
| 遠方緑地の敵検知と緑地喪失 | PASS | cell40,50の発芽で敵を検知し、緑地を失うとアイコンが消える。地形knownは1を保持 |
| 化石の播種/緑化/検知のみ未解放/記憶 | PASS | cell40,70のseed段階では未発見、発芽で発見するが未回収・carrot未解放。緑地喪失後も骨型を保持 |
| 発見記憶の保存復元 | PASS（限定追試） | 通常worldの固定巣・探索化石をhelperで実検知し、helper除去後に隔離保存/読込。discovered保持・化石未回収/未解放を確認 |
| 不正discovered型の拒否と現行不変 | PASS | nests文字列yes/fossils数値1をそれぞれ拒否。既知の有効な通常world snapshotでも現行保存状態不変を確認 |
| 以前のPoC3作業保存で欠落した発見値 | PASS（限定追試） | 通常worldのsnapshotからdiscoveredを省略すると読込可、nests/fossilsの全値をfalseへ補完 |
| 化石へ接近して回収/解放/アイコン消去 | PASS | 発見だけでは未解放だった化石へ4logicまで接近後、found=true・carrot解放・アイコン消去 |
| 巣報酬の維持 | PASS | 巣報酬化石は地上アイコンなし。巣破壊で回収済みになりwheat解放、巣は配列から消える |
| mini追試の地形色 | PASS | cell112,112は実terrain3。source Imageとmini raster中心は4d8eab。提供mini内にも同色912画素。荒地色を期待した自己assertが誤り |
| 一時検知を発見記憶へ反映する | **FAIL** | 下記の通常移動/時間経路で、固定巣が表示されたのに離脱後は記憶アイコンなし |
| 独立GPU・native外観・物理入力 | NOT_RUN | 提供GPU7点/画像/ソースの照合まで。独立追加GPU・OS入力・前面化・カーソル操作なし |
| 広い回帰・長時間プレイ・楽しさ | NOT_RUN | 主要条件各1回と、失敗2条件の限定追試/親追加観点1件のみ |
| 全照明/全サイズ/Windows書き出し後 | NOT_RUN | 今回の対象外 |

初回は9 PASS / 2 FAIL。初回2 FAILは、WorldStateのstageを段階的に直接操作した検知用fixtureをそのまま保存へ流用し、成長シミュレーションとの整合性を保証していなかったことによる試験不備。実際の拒否理由は `invalid_growth`。この結果をchecks/failuresと [run.log](run.log) に保持した。親への報告後、通常worldでhelperによる実検知だけを行い保存を1回再確認し、保存復元/欠落補完はPASS。型拒否も同じ有効stateで確認した。全体を再走せず、ゲームコードも条件も変更していない。限定追試と追加観点はresults.jsonのlimited_followupおよび [limited_followup.log](limited_followup.log) に別記した。

## 未解決FAIL: 表示された固定巣が記憶されない

- 重大度: **中**。固定巣の「発見後は検知外でも薄い位置表示を保持」に違反する。
- 期待: 固定巣が通常カメラ内でマップ表示されたら、離脱後も破壊まで位置を淡色で記憶する。
- 実際: map.icon_styleは即時のdetectedで表示するが、discoveredは0.5秒周期のrevealでのみ更新する。次のreveal前に離脱すると、表示済みの巣が未発見のまま消える。
- 最小再現: 通常Sessionのplayerを400,400へ設定し、実Camera3Dのpixel642,180から地面上に得た位置502.2525,268.228へ未発見固定巣を配置する。初期画面外でadvance(0.05)を行い、walk(RIGHT,0.1)→advance(0.1)で画面内へ入れる。この時マップアイコンは表示されるがdiscovered=false。walk(LEFT,0.1)→advance(0.1)で画面外へ戻すとアイコンが消える。
- 観測: 実移動は±3.394165logicずつ、elapsed=0.25、次のreveal_at=0.55。初期非表示→一時表示→離脱非表示を1回実測した。OS入力は使わず通常Session.walk/advanceを利用した。
- 対象: `scripts/poc2/poc2_session.gd` のadvance_game/reveal/detected、`scripts/poc2/ui/map_ui.gd` のicon_style。画像はなくヘッドレス結果。results.jsonのlimited_followup.transient_camera_detectionに状態と座標を記録。
- ゲーム実装は修正せず親へ返した。化石でも同じ時間窓があり得るが、独立再現は固定巣1件だけであり化石の瞬間検知経路は未検証。

## 提供GPU証拠とmini追試の切り分け

self/gpu_results.jsonの7点は実Camera3Dのrayで地面点を作り、engine unproject_position/frustumとhelperを比較していることを自己試験ソースで確認した。全点in/out一致、保存結果から計算した最大誤差は0.000165px未満。式を写した期待だけの結果ではない。実world_viewがこの共通camera_geometryへ接続していることも実diffで確認した。独立GPU再実行ではない。

self/minimap_followup.pngとfullmap.pngを実際に開いて目視した。地形・水路・建物、敵の点、親玉の菱形、通常/淡色の固定巣四角、現在/記憶の小さい骨型が確認でき、常時の名前・数値はない。640×360の画素は明瞭。両マップのアイコン描画は同じstyle/_draw_icon経路であることを実コードで確認した。

自己mini追試の `known_ground_source_matches=false` / FAIL / exit1は上書きしていない。データのwater矩形[109,1,6,222]内にあるcell112,112に荒地676856を期待したassertが誤りで、独立headlessの実source/rasterと提供画像の4d8eab画素を根拠にゲームの地形色不具合と区別した。初回miniの古いcache画像も、自己logic17 PASS/GPU9 PASSとも別の証拠として維持する。独立結果を合算して自己結果を上書きしない。

終了時もゲーム6件hash不変、Godot0件。実ユーザー旧save3件は読取hash照合のみで前後一致。実行直前CONTENT-01は第1段階/共有資源なし。割当試験/証拠以外は未編集、共有進捗も未編集。再委任/commit/stage/branch/pushなし。Godot/import権を親へ返却し、編集停止。
