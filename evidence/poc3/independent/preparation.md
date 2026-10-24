# POC3-VERIFY 独立検証準備

2026-10-24。基準読取HEAD `f8fd0035e566e241c0abf48b3b2165d48f76e1fd`。**ゲーム未凍結・準備のみ。Godot/import未実行、最終PASS/FAIL判定なし。** 実行権はINTEGRATION実装者が保持する。

所有は `tests/poc3/independent/` と `evidence/poc3/independent/` のみ。ゲーム/他test/docs/票/Git編集、再委任、他者差分の復元なし。OS入力/前面化/カーソル/未知プロセス停止は禁止。

## 読取済み根拠

AGENTS.md、tasks/README.md、POC3_VERIFY/INTEGRATION票、TASK_TEMPLATE、POC3_SPECの目的/全体完了条件と各機能の仕様、SOURCE運用、暫定ガイドを読んだ。機能別の独立報告・原失敗/限定追試と、現在の自己統合self_core/self_journey/self_gpu試験を確認した。

preparation_context.jsonは機能freezeと現在のソースを比較した**暫定**hash一覧。共有ファイルのhash変化は機能全体の証拠失効とは限らないが、一致しない証拠を自動的に現版PASSへ移さない。最終freeze後に意味のある後続差分と影響追試の接続を確認する。preparation_unfrozen_diff.patchとpreparation_status.txtも準備時点の観測であり、凍結manifestではない。

## 再利用候補と最終版への接続

| 完了条件 | 既存独立/自己根拠 | 凍結後の確認方針 |
|---|---|---|
| 通常入口1本・旧保存保全 | source/independent、save_base/independent | project/main_scene/run_game.batと保存パス/形式の静的照合。旧save3件はhash読取りのみ。通常起動/終了の最終自己ログを別監査 |
| 通常敵/巣の距離非非表示 | visibility/independent、sprite_view/independent | _entitiesの化石のみvisible条件を維持するか実コード確認。sprite導入後のGPU証拠へ接続し、旧mesh画像だけで現版外観を断定しない |
| 地図の検知/巣化石記憶/接近回収 | map_info/independent原11P1Fとmemory_fix4P、locust/independent | 記憶修正後の_remember_discoveries経路、MAPの生表示条件を確認。WORLD地形/HELPERS map装飾の後続差分を区別。旧FAILを修正追試なしに消さない |
| UI/Shift/保持の入力分離 | plant_ui/independent9P、input/independent9P | input_latchは準備時hash一致。main後続変更はAREA描画/HELPERS preview/予定終了closeを監査。最終UI代表1操作だけ新実行候補 |
| 幅播種・着弾決済 | area_seed/independent9P、helpers/independent | seed_area本体は準備時hash一致。combatの後続差分は個体helper弾の独立分岐、プレイヤーreserved1を維持。全幅・全候補の再走なし |
| 草/作物の永続給水・途中進捗・再植付 | water_growth/independent11P1試験設定F+継続1P、locust/independent | growth/world_state本体は準備時hash一致。plantsの後続変更は価格/HELPERS、食害resetはLOCUST証拠で接続。全時間例を再走しない |
| 同種価格・historicalpaid返還 | crop_pricing/independent10P | session価格/払済costとpersistenceの後続tier/helper検査を監査。過去の支払額を現価格から再構築しない。最終複合保存の代表へ含める候補 |
| 中央開始/敵間隔/地域0 | world_layout/independent10P、LOCUST配置証拠 | town03追加は遠方locust巣のみ。通常初期画像と生距離/177草を既存証拠で再利用。未解消だったWalkerは下記別扱い |
| 固定tier/後生産報酬0 | enemy_tiers/independent9P、locust/independent | Tiers本体は準備時hash一致、combat/persistenceの後続locust/helper分岐を監査。多数倍率の総当たりなし |
| locust食害/分散/占有/乾燥再生 | locust/independent9P | AI本体は準備時hash一致。HELPERSはArmy防衛連携と加害対象情報のみ、LOCUST AIを直接攻撃対象へ変えない。生産cap/食害保存の再走なし |
| helpers仕事/資源/退避/Zzz/比較 | helpers/independent10P、比較自己生結果 | helper_work/plants/combat/persistence等の最終hashを再確認。反射後の変更は表示setupだけ。Gat0/2、Sprinkler3/5.875、水0/1、Army草0/4の有無比較は再走しない |
| 代表GPU/native/反射 | sprite/reflection独立画像監査、最終統合GPU予定 | 元画像と最終通常GPUを実際に開く。反射のCPU0.358msをGPU専用性能と主張しない。実歩行・転向時系列の新証拠を確認 |
| 資源枯渇でも進行・終了中進行なし | integration自己core現14P1F | 生結果/実コードを独立監査。最終複合保存代表を少数新実行候補。時間待ちだけの長時間/全回帰なし |
| 全敵排除→安定→孤立を含む100% | integration自己core | 全map再走なし。下記の条件・hash・補正なし・最終凍結との同一性を監査して再利用判断 |
| 新規開始→解放/前線/攻略/配置/保存 | integration自己journey予定/進行中 | 資源/HP/解放/地形注入のない実API経路を監査。ユーザーによる巧さ/難易度評価と区別する |

すべて現在は再利用候補であり最終判定を確定していない。機能別合格件数を最終統合の新規実行件数へ合算しない。

## 既知の統合自己結果と留保

- core原14 PASS / 1 FAILを読んだ。全map38330/38330、孤立16/16、2401ゲーム秒/上限3207.5、初期177から到達。入力0、成長/播種値を直接書換えず、敵排除後は120秒固定刻みでclockが元のgrowth/spread/far信号を時系列順に送る。省略は敵不在のcombat・income・reveal・未設置helper/crop処理。この代表を再走しない。
- 同coreの北step9は実Session.walkでも(461.9998,418)に残るFAIL。原結果を保持し、四近傍別経路PASSへ置換しない。
- 親通知: Walker EPS1e-4→5e-4の限定修正に対し北/南/壁抜けなし/自由距離4条件追試、main._exit_treeのclose/nullで起動時残存がstderr空へ。最終freeze後に実差分/生追試を読む。通知だけを証拠に合格確定しない。
- 親通知: journey10P、実歩行で化石→近巣fire3/bazooka1→Army解放→Gat/Sprinkler探索→別前線→中央帰還→作物/3helper配置・給水→JSON全一致/続行。チート資源/HP補充なし。最終生結果とtrace/試験を読む予定。
- 最終通常GPU、反射の実歩行時系列、終了ログ、freeze、ガイド/既知制約とコミットの整合は未確認。これらが揃う前に最終受入判断をしない。

## 凍結後の少数独立実行案（未実行）

1. **Walker修正の代表影響**: 元の北step9直前の非中心位置から実Session.walkで隣セルへ進む条件を1回。近隣の本来水であるセルへの侵入は拒否される対照を1回。全経路/全4方向/長距離は再走しない。南/自由距離は自己影響証拠を監査。
2. **最終版の複合JSON代表**: 新規Sessionで水あり作物・支払額・お気に入り/幅・発見記憶・helper状態の組合せから1保存往復を構成し、全保存状態一致/復元時に時計不増/同刻みの再開を確認。必要な状態は実APIで作り、validatorを緩めない。既存全不正ケースや全個体弾保存を再走しない。
3. **通常入口・入力・終了の代表**: 最終main_sceneを隔離headlessから開始し、EまたはTabで停止、UI由来保持の解除後漏れなしを代表1回。終了はmainの本来_exit_tree経路で行い、手動session.closeで不具合を隠さず、プロセス終了/新ERRORなしを確認。旧機能の全INPUT一式/GPU一式を再走しない。

実行量は親の最終freeze/差分で削減できる。新しい懸念がなければ上記以外を追加しない。独立試験期待は仕様から定め、実装を写して正解にしない。実行不可や主要未確認はNOT_RUN、FAILは重大度/期待/実際/最小再現/ファイル/ログ画像を返してゲームを直さない。

## 実行開始前の必須状態

- 親から最終target HEAD/未コミット差分hash/自己freezeと実装者停止、Godot/import移譲の明示通知を受ける。
- 旧save3件hashと対象/保護hashを読み、試験保存は専用evidence/poc3/independent/profileへ隔離する。過去作業者のprofile/旧saveをロードしない。
- 既存Godotの有無を確認し、所有不明プロセスは停止しない。今回準備ではプロセス状態から実行権を推定しない。
- GPU再走が必要になった場合は親へ理由を先に返す。OS入力を使わず、起動前CreateNewのno_focus/minimized、非前面化SubViewport撮影が必要。既存最終GPU証拠で足りれば実行しない。
- 出力に最終版と環境、独立新実行/既存証拠監査/NOT_RUNを別記する。楽しさ/完成美術/物理入力/全性能はユーザー確認または未実施として残す。主要条件のFAIL/NOT_RUNを完了へ変えない。

準備完了後は実行せず親へ返す。最終freeze通知まで待機のためのGodot・タイマー・別タスクを起動しない。
