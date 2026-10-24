# POC3-SPRITE-VIEW 自己確認

初回実行HEAD `6364f290b9bdd9181c21816df370cbb3a98eaf4a`、限定GPU追試HEAD `a63487de7001af9d174929b500ee3a8efe33b9c7`、最終headless訂正確認/凍結HEAD `2e5ad7ef579c4640857e63914d5ea1482512db9b`。共有treeのHEADが親/外部commitで進んだため、対象表示4ファイルの内容hashをcontext.json / visual_context.json / freeze.jsonに記録。WATER等他担当差分は変更しない。stage/commitなし。

## 実装範囲

`scripts/poc2/view/world_view.gd` と新規 `entity_sprite.gd` / `entity_sprite_catalog.gd` / `entity_sprite_state.gd`。ゲーム行動辞書から状態・方向を読む共通表示。boar、clover、carrotへ既存の輪郭線なし仮素材をnative接続し、素材不足の大型植物・helpers・spider・mother・巣はmeshを保持する。大型を小画像の拡大だけで扱わない。描画定義/フレーム/4方向/足anchorと行動を分離し、固定巣等も同APIで差替え可能。

SpriteはBody(display64)、Shadow(shadows-only8)、Effects(Node3D)を分離。既存主人公のreceiver_lightと整合する受光/自己影除外、垂直板・nearest・native1texel=1画面px・足の画素スナップ。非中央X anchor/flipを含め各板から復元した足で影整合を検証する。弾は別entity、Effectsは将来の仕事/Zzz用入口のみで今回新作画/効果は作らない。

後続向けAPI詳細はpreparation/report.md。`world.entities[key]`はNode3D、素材ありEntitySprite・なし従来MeshInstance3D。`sprite_catalog.register(category,kind,definition)`、行動辞書の任意`visual_state` / `visual_direction`、body/shadow/effectsとsnapshot()を利用できる。

親承認の埋没対策として、sprite化した栽培株の占有セルだけ草MultiMeshを表示側で退避しshown_soil/paveも0にする。最終版はmask集合の追加/解除と通常dirty更新で上書きされた対象セルだけを更新し、無変更syncではMultiMeshを更新しない。撤去/mesh復帰は解除セルを既存ground.applyで復元する。WorldState/成熟数/収入/占有・保存に変更なし。dirty-list取得元はworld_viewの既存1か所だけ。

## 検証結果

| 実行 | 結果 | 証拠 |
|---|---|---|
| 初回headless import | exit0 | import.log |
| 定義・状態logic | 11 PASS / 0 FAIL、exit0 | logic_results.json / logic.log |
| 初回GPU構造/撮影 | 15 PASS / 0 FAIL、exit0 | gpu_results.json / gpu.log / context.json |
| 草表示調整後の限定GPU影響追試 | 14 PASS / 0 FAIL、exit0 | visual_followup.json / visual_followup.log / visual_context.json |
| mask集合最適化後headless影響確認 | 3 PASS / 1 FAIL、exit1 | cover_followup.json / cover_followup.log / cover_context.json |
| dirty件数の訂正確認 | 0 PASS / 1 FAIL、exit1 | dirty_followup.json / dirty_observations.json / dirty_followup.log |
| headless CPU観測へ訂正したdirty限定確認 | 1 PASS / 0 FAIL、exit0 | dirty_cpu_followup.json / dirty_cpu_observations.json / dirty_cpu_followup.log |

logicはnative寸法、成長別の既存画像、素材不足fallback、行動辞書読取不変、敵の待機/移動/予兆/攻撃/食害/被弾、helperの待機/移動/攻撃/播種/給水/退避、栽培段階、将来状態/方向入口、方向別フレーム、固定巣差替え入口を確認。未接続状態は合成辞書による入口確認であり、LOCUST/HELPERS実行完成を意味しない。

GPU初回はnative足/影/受光レイヤー、実位置移動・方向/予兆/被弾、非中央anchor+flip、素材交換前後のsession.to_dict/歩行可否/pick不変、死亡除去と最小化維持を確認。初回grass_native.png / windup.png / wall_edge.pngは取得できたが、既存建物と代表株が重なり、草上での植物識別と壁端は画像から十分判定できなかった。取得PASSをその目視PASSへ置き換えない。初回証拠は保持した。

その後world_viewだけに草退避を追加し、logic全体/初回GPU一式を再走せず、表示mask影響に絞って追試した。followupでは周囲建物/wall_viewと主人公本体/影だけを隠して草可視性を分離（受光ライトは残す）。成熟clover/carrot/植付cloverを実配置、ゲームsnapshot不変、mask実transformとshown配列一致、mesh復帰/株撤去時の草復元を確認。visual_observations.jsonに画面足位置と各root表示/非表示の画像差を記録した。

親レビューで毎frame復元/再hideの不要なMultiMesh更新を指摘され、mask集合の差分だけへ最適化した。最適化後のheadlessは無変更syncのground.cell_updates増加0、mesh復帰時の草復元、株撤去時の草復元とゲームsnapshot不変の3条件PASS。dirty条件は試験が更新1件を期待していたが、WorldState.set_stageの成熟境界変更は隣接4セルもdirtyにするため実際は5件だった。件数を実dirty数へ訂正した限定条件でもFAILとなり、headlessではMultiMesh.get_instance_transformが実描画を読めずorigin.y=0を返すことを確認した（既存ground_coverにもheadlessではshown_* CPU mirrorを使う旨の注記がある）。この2つのFAIL/exit1と元試験を保持。ゲームコードをさらに変えず、最終dirty限定条件はCPU観測値とsource dirty件数で確認してPASS、実dirty5/ground更新5、shown_soil/pave0。dummy rendererのtransform読取値0もdirty_cpu_observations.jsonへ併記した。最適化後のGPU全体/logic全体は再走していない。最適化前GPUで実描画を確認し、最適化後は影響条件をheadless確認したという区別を維持する。

## 画像の目視所見

- grass_followup.png: 成熟clover(298,200)、carrot(342,200)、植付clover(265,200)が草上に見え、完全埋没していない。各root非表示との差は126/37/21px。boarは300px。native素材のままで、浮かせるための足高さ追加はない。足元と地面の大きな隙間は見られない。
- windup_followup.png: 同じ仮boarで予兆の暖色tintを確認。未制作の専用動作フレームを作成済みとはしない。
- wall_followup.png: 足元に置いた不透明3D箱がboarの右側を遮り、左側が残る。boar表示差分は300→193px。深度無効化で壁を透過させていない。既存建物全種の遮蔽・壁際全方向までの確認ではない。

以上3画像を実際に開いて確認。640×360 SubViewport GPU描画で、通常窓を復元して撮ったものではない。完成アート/楽しさ/全体ゲーム受入は判定していない。

## 隔離・停止と未確認

CONTENT-01の別sandbox予約と既存Godot0を起動直前に照合。APPDATA/LOCALAPPDATAは本証拠内profileへ隔離（Git除外）。実ユーザーPoC/PoC2保存3ファイルの読取hashは初回前後と最終freezeで一致。保存へ書込みなし。

各起動のoverride.cfgはFileMode.CreateNewで作成し、no_focus=true/mode=1を起動前適用。既存ファイルを上書きしない。GPU開始/終了root.unfocusable・MODE_MINIMIZEDをassertし、try/finallyで自作overrideだけ除去。OS入力/カーソル/前面化/復元なし。最終Godot0件、override無し、表示4ファイル/試験6本とuidのhashをfreeze.jsonへ固定し編集・実行停止。

NOT_RUN: 物理入力、通常窓/全サイズ/全照明、完成4方向アニメ、未提供種のスプライト化、LOCUST/HELPERS行動本接続、仕事効果/Zzz、既存建物全種・全方向遮蔽、反射改善/負荷比較、広いゲーム回帰。反射は後続REFLECTION。独立検証と限定受入は親へ返す。
