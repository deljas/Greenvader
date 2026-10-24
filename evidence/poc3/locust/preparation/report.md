# POC3-LOCUST 未接続準備

開始時HEADa72c39f+WORLD凍結差分、記録時の実HEADはhashes.json。既存core/表示/data/Git/資料/票を変更せず、新規simulation/locust_ai.gd・tests/poc3/locust/self_unit.gdと本証拠だけを編集した。ファイルは完成した構文単位で保存し親へ通知。ENEMY側の共有Godot/importとCONTENT sandboxを実行/停止していない。

## 未接続部品/API

- setup(WorldState, navigation): session参照なし。advance(locusts, crops, dt, now)がバッタ群を処理し、草とlocust辞書だけを変える。主人公/植物へdamageするAPIを持たない。
- 定数: 初期6、alive総cap12、基礎HP5、初期基礎報酬1、小巣間隔20秒。spawn_count(alive_from_nest)は初期個体込み生存数から空き最大6を返す。実敵生成/tier倍率/報酬はまだ接続しない。
- 移動14 logic px/s（既存spiderと同じ）、探索はhome半径100logic px=10m、探索失敗時1秒間隔。既存navの敵用経路を使い、対象と経路上のstable地域をライブ状態でも除外。範囲はhomeからの目標範囲であり、経路そのものを半径壁で制限しない。
- 食害対象はgreened stage>=2・target・walkable・非占有。共有予約tile→idで分散。死亡/配列から消失/草消失/占有/安定化時に予約を解放。予約は毎advanceに生存locustの有効なeat_tileから再構成し、保存しない。
- 目標中心から1logic px以内で連続3秒を計時。移動/被弾停止中は進捗をリセット。完了時は既存WorldState.set_stage(EMPTY)のみを呼び、緑地/成熟/収入カウント・dirty・永久給水の解除へ既存経路を使う。完了前の死亡は草を変更しない。
- actorの追加状態はeat_tile(int index/-1)、eat_elapsed、eat_search_at。phaseはidle/chase/eat/stunnedで既存SpriteStateのeat/hitへ渡せる。route/goalは既存navの派生cache。release(actor)は撃破時即時解放用。
- ラフレシアは次の草選択時、locustから30logic px以内の生存成熟株、その株から12logic px以内の非占有草だけを距離score×0.45で優先する。株を目標や攻撃対象にしない。強さの値は既存虫誘引の係数を参考にした仮値。

## 本接続計画

ENEMY-TIERS接続後、combatのlocust固定小巣に初期6匹と同sourceの生存総cap12（初期も数える）を適用する。現combatの生産capは追加生産個体だけを数えるので、そのまま流用しない。20秒間隔で空き最大6を生成し、既存接近/緑化によるactive条件と休眠を保持。全locustをAIへ渡し、通常の主人公/植物攻撃ルーチンへは流さない。

生成時HPはtier.hp(5,tier)、報酬はtier.reward(1,tier,initial)として初期floor/追加0。通常弾5、bazooka、armyは既存敵damage経路で迎撃可能にする。kind whitelist/巣schemaと保存の追加フィールド検証・復元を接続範囲で行う。eat_elapsedは[0,3)・eat_tileは-1か有効indexなどを検証し、予約は復元後に再構築する。JSONの数値がfloatで来るため、ID/enum/tileは数値型（bool除外）→整数性/範囲→int正規化とし、int配列membershipへ直接渡さない。

巣はtown_03の初期開始8m外、最寄り既存小巣14mを保って別方向20m以上へ局所追加する。free_position後の実巣/初期群距離も計測する。現準備では具体配置・既存巣を変更しない。

表示は当面既存mesh＋phase=eatに必要な小さな食事動作だけ。SPRITEのBody/Shadow/Effects分離を利用可能だが、完成画像/階級外見は作らない。緑地を食べた後のland_rate・map detected（他検知源があれば継続）、再生草dry、安定後の侵入禁止は本接続時に代表確認する。

## 試験準備 / NOT_RUN

self_unit.gdは16×16小世界で対象6分散・占有除外、2.9秒維持→3秒完食とカウント/水分0、途中死亡、stunで進捗0から連続食事再開、AI再作成時の進捗再開/予約再構築、占有/消失/個体削除の予約解除、ラフレシア近傍草誘引・株非攻撃、stableの対象/経路除外を各1条件準備。AI再作成は辞書再利用の部品試験であり、実JSON保存の検証ではない。実行はしていない。

本接続時の限定試験は初期6・HP/迎撃、active/休眠と20秒後の空き群生産・総cap12、初期倍率報酬/生産0、食害の検知喪失と別検知継続、再生dry、保存中断復元、eat GPU1代表を追加する。全map100％の新たな長時間走行は行わず、WATERの15×3水帯分離小世界30/30証拠（self/report.md、independent/report.md）を参照し、全224×224はINTEGRATIONへ渡す。

すべてNOT_RUN: Godot/import・構文実行・unit・通常ゲーム・GPU・保存・戦闘・実生産/報酬。静的に型注釈/API/非接続だけを確認、PASSへしない。準備後は編集停止。実接続/実行は親の範囲/資源移譲待ち。OS入力/カーソル/前面化・プロセス停止なし。
