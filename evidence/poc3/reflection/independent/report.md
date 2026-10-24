# POC3-REFLECTION 独立確認

2026-10-24。**独立監査8 PASS / 0 FAIL、4 NOT_RUN群**。これはソース・生GPU証拠の監査と画像目視であり、新しいGodot実行の合格件数ではない。追加のゲーム修正が必要な失敗は代表証拠から確認されなかった。最終受入は親へ返す。

## 対象と方法

- 当初基準 `a97fbcdb996ba90a74c9cf5cf66cdb8206d19786` + 承認済みHELPERS index差分 + REFLECTIONのworld_view追加7行。独立中に親がHELPERSを4550123へコミットしたと通知。ゲーム内容の変更ではなく基準のコミット化であり、最終実HEADはafter.json参照。
- 対象world_view hash `AB63C95E19285A30167EF259B662442D66916A8009E495ACE910C47152E84544` は最終まで不変。実 `git diff` を読み、反射setup以外の変更がないことを確認した。
- AGENTS.md、tasks/README.md、REFLECTION票、TASK_TEMPLATE.md、PoC3仕様、self/report/freeze、self_compare.gd、compare_results.json、normal_results.jsonと関連共通Water/設定/shaderを読んだ。実装者の報告だけで判定しない。
- 証拠環境はWindows / Godot4.7.2 / Vulkan Forward+ / RTX5070Ti。本独立確認ではGodot/importを実行していない。既存GPU証拠を再利用し、PNG headerの寸法とhashを別途読み取った。
- before.json / after.json、actual_diff.patch、observations.json、results.json、status_before/after.txtが独立証拠。専用test追加やゲーム編集なし。

## 条件別結果

| 条件 | 結果 | 独立に確認した根拠 |
|---|---|---|
| PoC3限定のdeep-copy変更 | PASS | world_viewはsource.env_tuning.duplicate(true)のコピーへwater.reflection_divisor=1を設定してWater.setupへ渡す。元の辞書へ書かず、他版共通JSONのdivisor2を保持。共通Water/Actor/shader/Cardに差分なし |
| 本画面/反射の寸法 | PASS（生PNG監査） | 全7姿勢の本画面PNGは両設定640x360。反射texture PNGはdivisor2が320x180、divisor1が640x360。通常接続PNGも640x360。PNG header値をobservations.jsonへ保存 |
| nearest/輪郭/本画面の維持 | PASS（実ソース/比較証拠） | shaderのreflection samplerはfilter_nearest、reflection viewportはAA/TAAなし。元素材/カード不変、ぼかし追加なし。比較画像で本体の輪郭は維持されている |
| 静止反射の読みやすさ | PASS（画像目視） | d2_still.pngとd1_still.pngを直接開き、contactも確認。divisor1では主人公の顔/葉、cloverの輪郭、boar細部が小さな画素で残り、divisor2の大きな画素塊が軽減 |
| 7姿勢の形と位置 | PASS（抜粋静止画の範囲） | comparison_contact.pngのstill/歩行4コマ/左右転向を実際に閲覧。主人公/boarの反射に極端な潰れや足から大きく離れる変化は見られない。植物は固定。生metadataは本画面足X265→268→270→273→275/Y200、divisor1反射足X同じ/Y160.2022一定。全姿勢のmetadataを抽出 |
| 通常接続と元tuning不変 | PASS（実試験/生結果監査） | normal_connectionは実Session/World、合法な岸(111,55)。source.env_tuningの前後JSON不変と共通divisor2、構築後reflection640x360を自動確認。normal_results.jsonの6 PASSと実コードを照合 |
| 限定負荷値の記録 | PASS（測定の範囲を限定） | 12frameの同期force_draw CPU待ち中央値は両0.358ms、drawcall15/primitive3934。測定コードはTime.get_ticks_usec前後差でありGPU専用timerではない。この区間の観測値としてのみ受理 |
| 対象/保護/旧saveの保全 | PASS | world_view1/自己試験2/保護6の9hashがfreezeと一致し前後不変。project.godot不変。旧PoC/PoC2実save3件はhashだけ読み前後不変 |

画像目視はcomparison_contact.png、d2_still.png、d1_still.png、normal_world_connection.pngを実際に開いて行った。contactは元PNGをnearest2倍で並べた補助sheetであり、元静止PNGも併読した。

通常街区画像は水面・建物・影と接続しているが、主人公付近を木が遮っている。この画像単体で細かい反射形状の合格を主張しない。形の確認は固定fixtureに基づく。全影/遮蔽回帰も未実施。

## 性能と動きの限界

| 反射 | 同期CPU待ち中央値 | min–max | drawcall / primitive |
|---|---:|---:|---:|
| 320x180 | 0.358ms | 0.247–2.427ms | 15 / 3934 |
| 640x360 | 0.358ms | 0.284–0.812ms | 15 / 3934 |

この限定CPU同期区間で重大な悪化は見えない。ただし反射画素数は4倍であり、これをGPU負荷同等、通常fps維持、全map性能合格へ読み替えない。GPU専用時間/他GPU性能はNOT_RUN。

歩行は別々にposeを指定した4コマと左右転向の静止抜粋であり、連続時間のちらつき検出はNOT_RUN。7姿勢に極端な形破綻がないという所見と区別する。仮boarは1方向画像の反転、全敵素材/完成アニメの確認ではない。

自己19比較PASSと通常接続6PASSは異なる実行で、独立8監査項目へ合算していない。parse成功だけをGPU合格にしていない。画像sheet生成時のPillow不在はゲーム不具合ではなく、既存PNGの補助合成方法の変更として扱う。

## NOT_RUNと終了

- NOT_RUN群1: 独立Godot/GPU再走。
- NOT_RUN群2: 連続動作・ちらつきの評価。
- NOT_RUN群3: GPU専用/全map/他GPUの性能。
- NOT_RUN群4: 全照明/雨/角度/水面/素材、広い回帰、物理入力、完成美術/楽しさ。
- ゲーム/他test/docs/票/Gitを編集していない。本独立証拠ディレクトリのみ追加編集。他者差分保全、再委任なし。
- OS入力/カーソル/前面化/未知process停止なし。開始/終了Get-ProcessでGodot0、overrideなし。旧save3不変。Godotを新規起動しておらず、以後も実行しない。
- 共有Godot/import権を親へ返却済み。受入範囲と未確認性能/時間的表示の扱いを親へ返し停止する。
