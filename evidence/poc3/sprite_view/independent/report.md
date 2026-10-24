# POC3-SPRITE-VIEW 独立検証

2026-10-24。独立実行は **10 PASS / 0 FAIL、exit 0**。未解決のゲームFAILは確認されなかった。以下は表示基盤に限定した確認であり、最終受入は親が判断する。

## 対象と実行範囲

- 指定・実HEADとも `2e5ad7ef579c4640857e63914d5ea1482512db9b`。表示4ファイルは self/freeze.json と開始時4/4一致、終了時も不変。world_view.gdは未コミット差分、entity_sprite.gd / entity_sprite_catalog.gd / entity_sprite_state.gdは未追跡追加。実diffと新規3ファイル全体を直接読んだ。before.json / after.json / world_view_diff.patch / status_before.txt / status_after.txt参照。
- Windows / Godot `4.7.2.stable.official.ed1daf0bf`、headless、Dummy audio。Godot共有実行権の親割当とCONTENT-01の別sandbox予約を確認。
- AGENTS.md、tasks/README.md、SPRITE票、TASK_TEMPLATE.md、PoC3仕様の表示基盤条件、self/report.md、該当自己試験・生結果・画像を確認した。
- godot-gdscript / godot-gdscript-headless-testingスキルに従い、SceneTree入口、型注釈、失敗件数と非0終了、試験未完走の検出を備えた。テストはSessionやworld_viewをpreloadせず、State/Catalog/Cardだけを実行。並行するPRICINGのcore実装を試験へ取り込んでいない。
- APPDATA/LOCALAPPDATAは本証拠下profileへ隔離。import/GPU再走/通常入口起動なし。override.cfg作成なし、OS入力・カーソル・前面化・ウィンドウ復元なし。

## 独立実行

証拠は `logic.log` / `results.json` / `exit.json`、試験は `tests/poc3/sprite_view/independent_logic.gd`。各条件1回。

| 条件 | 結果 | 確認内容 |
|---|---|---|
| STATE_READ_ONLY_NESTED | PASS | pos/hpに加えて占有owner/sizeと入れ子のwatered/costを持つ辞書を参照し、元データ不変 |
| ENEMY_TELEGRAPH_HIT_ATTACK_EAT | PASS | 予兆→被弾→攻撃→食害の表示状態を独立時系列で確認 |
| HELPER_WATER_FLEE_MOVE | PASS | 給水・移動中退避・通常移動/上向きを確認 |
| CROP_STAGE_TRANSITIONS | PASS | age0植付→成長途中→成熟の表示状態 |
| NATIVE_ART_AND_MISSING_ART_FALLBACK | PASS | boar32x18、clover成長8x8/成熟16x16をnative使用。未提供大型/親玉の定義は空でmesh維持の入口 |
| DIRECTION_ANIMATION_AND_DEFINITION_OWNERSHIP | PASS | 将来方向別フレームの0.75秒/2fpsで第2frame。未提供stateはidleへfallback。登録元辞書変更は登録済anchorへ影響しない |
| ASYMMETRIC_ANCHOR_PIXEL_FOOT | PASS | 独自13x21画像、非中央anchor(2,19)。snapshotの足復元式を期待値に使わず、カメラで投影した板中心に画像pixelのanchor差を加えて検証。足は期待整数pixel(318,184)、地面y=0 |
| FLIP_KEEPS_BODY_SHADOW_GROUND_FOOT | PASS | 左右反転後の画像anchorも同じpixel足。影板上のanchorをローカル→世界変換しrender_foot一致。板の中心位置同士は一致不要 |
| NATIVE_SCALE_NEAREST_SEPARATE_LAYERS | PASS | 640x360、高さ18.5mの1texel比、nearest、本体64/影8、cast off/shadows-only、独立Effects接地点 |
| CARD_DEFINITION_READ_ONLY | PASS | pose/反転で入力表示定義を変更しない |

このheadless検証はCPU変換・状態参照の検証であり、新しい実画面撮影ではない。独自の白いテスト画像はメモリ上のみで作成し、ゲーム素材へ保存していない。

## 実画像と既存証拠の独立レビュー

画像を実際に開き、自己報告の結論だけで判断していない。確認画像3件のhashはafter.jsonへ記録した。自己試験件数と独立件数は合算しない。

| 条件 | 結果 | 証拠・限定範囲 |
|---|---|---|
| 草上の株/敵の識別・接地・640x360 | PASS（既存GPU画像目視） | self/grass_followup.png。成熟clover(298,200)、carrot(342,200)、植付clover(265,200)とboarが見える。草による完全埋没や足下の大きな隙間は見られない。元の小さな仮画像であり完成美術とは扱わない |
| 敵予兆の表示 | PASS（既存GPU画像目視） | self/windup_followup.png。通常boarより暖色へ変化。専用アニメ完成の証拠ではない |
| 壁際の部分遮蔽 | PASS（既存GPU画像目視） | self/wall_followup.png。足元から立つ不透明箱がboarの右側を隠し、左側を残す。view_imageで確認。全建物の証拠ではない |
| 素材交換前後のゲーム判定不変・影分離 | PASS（ソース/生GPU結果レビュー） | self_gpu.gd / gpu_results.jsonのvisual_swap_preserves_save_collision_pick、native足/影、受光layer。Session snapshot/歩行可能/pickの交換前後一致を試験している |
| 草maskが表示だけを操作 | PASS（実差分レビューと既存CPU/GPU証拠） | world_viewの_mark_crop_coverはsprite cropのcell/sizeだけから集合を作る。_apply_crop_coverの書込先はgroundのsoil/pave/shown配列と表示側集合のみ。ゲームWorldState/収入/占有へ書かない。dirty消費はsyncの既存1か所に維持 |
| mask差分化、解除、dirty再適用 | PASS（最終版CPU証拠レビュー） | self/cover_followup.jsonの無変更sync更新0、mesh復帰/撤去で草復元かつsnapshot不変。self/dirty_cpu_followup.json、dirty_cpu_observations.jsonでdirty5→更新5、shown_soil/pave0。最終world hash B710...FB92とcover_context/freezeが一致 |

マスク差分アルゴリズムも直接確認した。無変更対象はskip、新規mask/dirty対象だけhide、解除時に通常dirtyで既に復元済みのセルは再applyしない。dirty外で解除したセルだけground.applyで復元する。これにより無変更syncで毎frameのMultiMesh書込を避ける構成になっている。

画像の版差は残る。GPU追試時のworld hashは `1F02F219E175AE479E0C66F5723A37314BC7805050CE845986CE097BF61FC0AC`、最終版は `B710A047F2BEB61C47C2E088186415880E43AA1C4B4A3C8D8711046ADF51FB92`。違いは草maskの毎frame復元/hideを集合差分へ変更した部分。画像は最適化前の有効GPU証拠、最適化後は上記CPU影響証拠と静的差分レビューで確認。最適化後GPUを実行済みとは扱わない。

初回自己GPU画像は建物重複で不十分なので、取得成功を草上識別/壁端の目視PASSへ置換していない。最適化後の初回3 PASS / 1 FAIL（dirty1件を期待）とdirty訂正0 PASS / 1 FAIL（Dummy renderer transform読取）を保持したままレビュー。WorldState成熟境界は周囲もdirtyにするため5件、headless transform読取は0という観測と、CPU訂正1 PASSが対応している。元FAILを隠すゲーム修正はなく、未解決の描画FAILへ誤分類していない。

## NOT_RUN・保全・停止

- NOT_RUN: 最終mask版の新規GPU撮影、通常窓/全サイズ/全照明、物理入力、全種/全方向/完成アニメ、既存建物全種での遮蔽、LOCUST/HELPERS行動本接続、仕事効果/Zzz、反射改善、負荷比較、保存全回帰、書き出しビルド。
- ゲームコード・設定・素材・他者試験・作業票・docsを編集していない。追加編集は割当のindependent_logic.gdと本証拠ディレクトリのみ。Git index/commit/branch操作なし。他者の並行core差分は戻していない。
- 表示4hash前後一致、project.godot不変、旧PoC/PoC2保存3件はhashのみ読取りで3/3前後一致。保存への書込み・ロードなし。before.json / after.json参照。
- 開始前/終了後Get-ProcessでGodot0、overrideなし。実行終了済み。共有Godot/import権を親へ返す。
