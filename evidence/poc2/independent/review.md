# POC2-05 独立検証報告

対象: HEAD `151a53f20255489ef08481e2a353258cd8ac559c` と既存未コミット差分。第二弾対象の正本は `../integration/freeze-manifest.json`（16件）と `git-status-at-freeze.txt`。共有ツリー。仕様は `docs/POC2_SPEC.md` と作業票。環境: Windows、Godot `4.7.2.stable.official.ed1daf0bf`、GPUはVulkan 1.4.341 / NVIDIA GeForce RTX 5070 Ti。

**結論: 今回確認した条件に未解決の実装FAILはない。** 独立logic 36項目、追加境界12項目、GPU/入力10項目を確認した。初回の検証fixtureによるFAIL 3件は原記録を保持し、下記の根拠で解消を区別して記載する。最終受入は親が判断し、人間による楽しさ・最終美術評価を代行しない。

## 対象と保全

- PASS: 実行前後とも凍結対象16件のSHA256一致、第一弾baseline91件のSHA256一致。`freeze-before.json` / `freeze-after.json`。
- PASS: ゲームコード・設定・素材・通常保存・共有進捗文書を編集していない。独立テストと証拠だけを作成。ゲーム修正、commit、再委任なし。
- PASS: 終了時にGodotプロセス0件。Godot/importの専有を親へ返却する。
- GPU起動は正規のrequire_escalated承認を使用。`root.unfocusable=true`。入力は `Input.parse_input_event` のみで、OS入力・実カーソル移動・前面化を行っていない。

## 条件別結果

| 条件 | 結果 | 証拠・範囲 |
|---|---|---|
| 224×224、第一弾の縦横2倍、初期250緑化セル・60種 | PASS | 独立logic、第一弾mapの112×112とも比較 |
| 初期土地5種/分、pause中の時計・収入停止 | PASS | 地形拡張と敵圧力を切り離した60秒一回の測定 |
| 5株の採用コスト・成熟時刻・成熟前収入0・成熟後合計47種/分 | PASS | 独立した仕様値を使い、15/20/30/45/90秒の単一時系列で測定。土地5と合わせた60秒収入52も確認 |
| 化石未解放、荒地、部分緑化のfootprint、占有重複 | PASS | 公開設置APIから拒否、資源不変を確認 |
| 地下の緑地収入維持、実支払費用20%切捨て | PASS | 土地5維持。テスト個体の支払費用13で2返還。通常費用や保存形式の変更を提案するfixtureではない |
| 個体弾薬移送・遠隔補給・上限失敗・自主撤去・死亡 | PASS | 備蓄と弾薬の数を直接照合。満杯超過で部分引落しなし。自主撤去は未使用分全返還、死亡は返還なし |
| 初期小型6/強敵15、生成敵0、巣小30/中80/大200 | PASS | 実damage処理の前後差。生成を直接呼ぶfixtureで報酬の属性を分離 |
| 小数収入・解放・弾薬・移動命令の復元、異常保存の原子性 | PASS | メモリー内capture/restore。負数種を含む異常snapshot拒否時に現在snapshot全体不変 |
| アーミーの迎撃・撃破後帰還・非戦闘8秒後の低速回復 | PASS | 到達可能な敵への迎撃→撃破→元位置復帰。7.5秒はHP60維持、9秒で61.25。初回fixture修正の経緯は下記 |
| スプリンクラーの補給出発・5秒給水・元位置への帰還 | PASS | 別位置へ実際に歩行。到着から2.5秒で水50、5秒で100、帰路は消費せず100で復帰 |
| 到達可能な水辺がないと待機 | PASS | 検証用navの水辺集合を空にした境界fixture。`no_water_route`、移動なし。通常mapは変更しない |
| 未知の水面への命令秘匿、既知になってから到達不能 | PASS | 指示受理→`exploring`で移動→known公開後`unreachable`。未知を即拒否しない |
| 巣の遠方停止・主人公接近起動・離脱遅延停止・緑化接近起動 | PASS | 自然拡張を切り離した一つのsourceの時系列。遠方30秒で生成なし、接近後生成、離脱後停止、緑化で起動 |
| 安定地への敵経路禁止、生産源と残敵消滅後の安定化 | PASS | hostile routeのsafe拒否、実damageで全source/残敵を除去した短い境界試験 |
| 孤立地を含む安定後100% | PASS（提出実行＋独立コード照合） | `../self/simulation_results.json` の3500ゲーム秒一回で100%/cleared。試験fixtureが水中の4×4島とおたすけ占有を含むこと、FarSeedの全index公平走査とzone安定条件、helper下のseed開始を独立に読んだ。**独立長時間再実行はNOT_RUN** |
| 全画面マップの停止・wheelズーム・植物選択とボタン | PASS | 独立GPUで実Input注入。拡大4、elapsed不変、選択により撤去/補給表示 |
| 補給popupのクリック貫通防止と一度だけの投入 | PASS | 実Inputで開く/ラベルを押す/確定。homeと時刻不変、種5減・個体5増を確認 |
| 満タン時ゲージ非表示、不足時HP/種/水ゲージ表示 | PASS（画像比較） | 同一runの`map-full.png` / `map-depleted.png`を独立目視。差分60px=HP緑16、種黄8、水青6、ゲージ背景30で、いずれも3ゲージ位置内。`gauge-image-review.json` |
| 未知の敵非表示・640×360/nearest・停止時の光更新抑制 | PASS | 生存enemy nodeをvisible消去時に隠す。実SubViewport640×360とnearest。静止時計でlight_updates増加なし |
| 遮蔽の半透明＋高さcut | PASS（限定画像/ソース） | `../view/06_cutaway_ui.png`の実GPU画像とcutaway shaderのdiscard、cut高さの設定、shadow twinを独立に確認。全建物・全角度の保証ではない |

経済試験ではgrowth/spreadの信号と敵圧力を切り離した。植物・備蓄・combat・保存の実コードは使用するが、これを広い自然拡張回帰と同一視しない。追加境界も少数の目的別fixtureであり、ゲーム全体のバランス測定ではない。

## 初回FAILの保持と解釈

1. `boundary-results.json` / `boundaries.log`: 守備兵の迎撃と回復がFAIL。検証者が敵を `(171,188)` の建物内（terrain4、歩行不可、path空）へ強制配置していた。`army-fixture-probe.log`に実地形・経路の証拠。敵を北側の到達可能な `(177,182)` へ置く同条件の限定再試験のみ実施し、`guard-affected-results.json` / `guard-affected.log`で迎撃・帰還・回復がPASS。ゲームコードは変更していない。重複チェックを件数に再加算しない。
2. `map-gpu-results.json` / `map-gpu.log`: 初回のゲージpixel読みがFAIL、画像幅640に対してx830を読んだエラー。検証側が画像座標にwindow倍率を重ねて適用した。Inputのwindow変換は正しく、クリック群はPASS。GPU再実行はせず、同一runの画像比較によりHP/種/水の3ゲージを確認した。試験ソースの採取座標だけを補正し、原結果は上書きしていない。
3. 実装者のview初回保存比較FAILとwheel FAILはそのまま証拠に残っている。保存は極小の小数表現差、wheelは入力座標fixtureの倍率であり、各限定追試と独立の保存/実Input試験を合わせて未解決FAILとはしない。

先行静的指摘S1（待機通知status不一致）、S2（preview footprint/size不一致）は凍結版で修正済み。statusリストに`no_water_route/unreachable`があり、previewはCATALOGの`size`を使用している。実装者の3×4preview実行結果と画像も読んだ。

## NOT_RUNと引渡し時の限界

- 物理キーボード/マウスからOS経由の操作。ユーザー手動確認。
- 最初の数分の楽しさ・種収支の快適さ・複数前線を任せた満足感。今回の数値は採用仮値であり、技術PASSを体験評価に読み替えない。
- 独立3500秒全走の再実行、全組合せ回帰、全マップ/全角度/終盤最大密度の性能。
- 書き出したWindows配布物の起動。本対象は既設Godotの専用launcher/sceneであり、第二弾export preset/配布物は今回独立実行の対象にない。
- 壊れた保存全形式のfuzz、全拠点規模でのspawn cap、全敵相性/誘引忌避の長期戦、すべての退避復帰組合せ。既存コード/証拠の確認範囲を超える保証はしない。
- ちらつきの時間動画による主観評価、第一弾との動画A/B、水面反射の磨き込み。太陽更新が毎フレーム行われないコードと停止時の挙動だけを確認。
- 第一弾の天候変化は第二弾で固定晴れの暫定実装。追加スキル群・化石発見補助植物・多地域は未実装の将来項目。

共有進捗は更新していない。本報告と実結果を親へ返し、独立検証の実行を終了する。
