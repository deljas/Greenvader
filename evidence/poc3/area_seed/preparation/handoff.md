# POC3-AREA-SEED 未接続部品の準備結果

対象版: 共有ツリー `C:/godot/greenvader`、HEAD `9d54a6d1795065e6e642fe01543b2c8d2a1f27ee`。INPUTが既存コードとGodot/importを所有。WORLD-LAYOUT前タスクのデータ/証拠は編集していない。これは部品準備であり、AREA-SEEDの実装接続・受入ではない。

変更ファイル: 新規 `scripts/poc2/simulation/seed_area.gd`、本ディレクトリの `test_plan.md`、`handoff.md`、`source_manifest.json`。

## API

```gdscript
const SeedArea: GDScript = preload("res://scripts/poc2/simulation/seed_area.gd")
var preview: Dictionary = SeedArea.plan(state, aim_cell, sow_width, seeds, helpers)
# 着弾時は改めて現在状態を読み、当該弾の固定幅と預かりを使用する。
var impact: Dictionary = SeedArea.plan(state, impact_cell, shot.sow_width, seeds + shot.reserved_seed, helpers)
```

上記は接続例であり、shotフィールドや既存呼出側は今回追加していない。

`plan(world: WorldState, center: Vector2i, width: int, budget: int, helpers: Array[Dictionary] = []) -> Dictionary`。

- 戻り値: `ok: bool`、`reason: String`、`center: Vector2i`、`width: int`、`rect: Rect2i`、`valid/affordable/unaffordable: Array[Vector2i]`、`cost: int`。
- centerは論理pxではなくcell。rectは指定centerを中心とした1/3/5/7の正方形。範囲外のcellはvalidから除外し、rect/center自体はずらさない。
- validは `WorldState.can_plant` を満たし、生存helper現在セルに一致しないcell。can_plantは非対象・非播種地形、既存種/草、occupied footprintを除外する。helperのownerが移動時に解除されても現在posを `Coords.logic_to_cell` で追加除外する。helper入力は現行session形式のhp/posを持つDictionaryで、呼出側は必ず現存helpersを渡す。
- validは距離二乗昇順、同距離はy、x昇順。affordableはその先頭から `min(max(budget,0), valid.size())` 個、unaffordableは残り。同じ順序の新規配列を返す。costはaffordable件数。
- world=nullはinvalid_world、幅1/3/5/7以外はinvalid_widthで空計画。負予算は0。空地がなくても有効入力ならok=true/cost=0。
- WorldState、helpers、残高、RNG、弾、描画に書き込まない。Sessionはpreloadしない。既存Coordsだけを参照し、循環依存を避ける。

## 必要な接続（今回未編集）

1. INPUTで導入するsession.sow_width（初期1）を表示側へ渡す。範囲変更でも同じaim cellを使い、rectを地面へ投影する。既存set_previewは栽培footprint用なので、この計画の有効/不足セルを区別する描画と種アイコン/予定消費数表示を別途接続する。射程で着弾地点をclampするなら、プレビューも同じ実着弾候補cellを使う。
2. 通常seed弾は発射時に1個を残高から預かり、弾ごとの固定幅/預かりを保存する。範囲全体は拘束せず、幅7でも種1で攻撃できることを維持。bazookaとhelperの播種は変更しない。
3. `_shots` の壁→敵/巣→地面の既存判定順を維持。敵/巣なら預かり1を消費して通常ダメージ、範囲播種なし。壁なら預かり1を返却して弾を除去する。
4. 地面着弾時だけ現在state/helpersと「預かり1＋その時点の残高」で再planする。affordableの各セルを `set_stage(STAGE_SEED)` で実際に播種し、成功数Nだけ精算。N>0なら追加 `N-1` を残高から引き、N=0なら預かり1を返す。古いプレビューを着弾計画として使わない。精算と播種を同じ同期処理内で行い、弾を一度だけ除去/決済する。
5. 飛翔弾の幅/預かりをpersistenceに追加し、値の検証と保存復元を確認。飛翔中の他設置・補給で預かりを二重使用しない。

## 検証と未確認

静的レビューのみ: 読取API、中心矩形、can_plant＋現在helper除外、全順序、予算分割、既存コード非接続をソースで照合。構文・実行・挙動のPASSとはしていない。hashとレビュー項目は `source_manifest.json`。

**NOT_RUN:** Godot構文解析/import/起動、計画関数の実呼出・snapshot非変更、4幅/端/混在/予算不足/移動helperの実結果、着弾精算、敵命中、壁返却、飛翔中変化/保存復元、GPUプレビュー・ピクセルパーフェクト/輪郭線、実入力、主要回帰。理由は共有資源のINPUT所有と今回の未接続範囲。

プロセス起動・OS入力・前面化・カーソル操作なし。Git stage/commit/branch操作なし。共有STATUS/企画/票は更新せず、文書担当には未接続部品と接続項目、Godot全項目NOT_RUNを渡す。

準備完了で編集停止。既存combat/session/view/persistenceへの接続とGodot実行は親の再割当後。
