# SPRITE-VIEW 接続準備（未実行）

対象: 着手時HEAD5f7ac13+AREA固定差分。準備終了時は親のAREA commit後 `119efb5fdf5f397e9288748b477aca45038cb56e` + WATER等の共有差分。実装対象4本と自己試験2本のhashはhashes.json。編集は割当view/新規自己試験/証拠だけ。他担当差分は保持、stage/commitなし。

- `world_view.gd`: 読取専用の表示状態を解決して素材定義があれば共通spriteへ、なければ従来meshへ。死亡/削除・化石視界フィルタ・弾・配置previewを保持。1つのdirty-list consumerを増やさない。
- `entity_sprite_catalog.gd`: category:kindごとの表示定義。clipsはstateごとframes/fps/frame_pixels/anchor、任意のdirectionsで4方向。素材不足状態はidle静止画へ代用。PixelArt.boar32×18、cloverの既存sprout8×8/mature16×16、PlayArt.carrot8×8のみ接続。再サンプル/新作画/階級外見変更なし。大型植物は小画像拡大せずmesh維持。helpers/mother/fixed nestsもregisterで差替え可能。
- `entity_sprite_state.gd`: 敵idle/move/windup/attack/hit/eat、helper idle/move/attack/sow/water/flee、crop planted/growing/mature。移動/被弾を表示側だけ追跡し、phase/status/age/matureを読む。将来の行動側はvisual_stateとvisual_directionを任意に供給可能。既存辞書・sessionへ書き戻さない。
- `entity_sprite.gd`: Body(display64)/Shadow(shadows-only8)/Effects(Node3D)を分離。native1texel=1画面px、nearest/alpha discard/輪郭線なし、垂直板、固定足の画素スナップ、材質は受光/深度判定を維持。既存主人公のreceiver_light64/shadow_caster1を共有し自己影を避ける。非中央X anchor/flip時は板ごとの中心を計算し、本体/影から復元した足元一致でsnapshot.shadow_matchesを判定する。

## 後続HELPERS/LOCUST向けAPI

`world.entities[key]`の共通型はNode3D（素材ありはEntitySprite、素材なしは従来MeshInstance3D）。keyは既存のcategory+idを維持。spriteにはbody:Sprite3D、shadow:Sprite3D、effects:Node3D、visual_state、direction、render_foot、snapshot()がある。meshにもvisual_state/visual_directionメタデータを設定する。Effectsは本体/影とは別で足元世界座標へ同期。今回仕事効果/Zzzは作らない。弾は従来shots独立entityを維持する。

`world.sprite_catalog.register(category,kind,definition)`で素材を交換でき、次のsyncでmesh/sprite切替も反映。固定巣にも同じAPI。素材定義はゲーム判定/占有/能力・保存に流さない。

## 検証準備 / NOT_RUN

静的なdiff --checkは問題なし。Godot/import・構文実行・logic/GPU・操作・描画負荷は全NOT_RUN（WATER所有）。共有world_view編集は完了、ここで編集停止し親の実行権移譲待ち。

自己試験は定義/状態/4方向フレーム入口と、隔離profile・起動時no_focus/minimized固定GPUの代表fixtureを準備。ゲームsnapshot/占有・pick不変、native寸法、画素足/非中央anchor/影ペア、草地clover/carrot、boar移動・予兆・被弾、壁端深度、死亡除去を限定確認予定。草に埋没しないことと壁端/影は画像取得後に目視が必要。現段階では確認済みとしない。
