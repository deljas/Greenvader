# 追加コンテンツの通常ゲーム統合手順（引渡し資料）

更新日: 2026-10-24 / 作業票: [CONTENT-01](../tasks/CONTENT_01.md) / 仕様: [CONTENT_CATALOG](CONTENT_CATALOG.md) / 状態: **引渡し版（2026-10-24）**

この資料は、追加コンテンツ（敵21種・栽培植物28種）を通常ゲームへ接続するためにCodex側（PoC3の共通基盤）で必要な変更をまとめたものです。CONTENT-01では、部品と専用確認画面までを作りました。**通常ゲームへは未接続**で、本書の変更は**統合待ち**です。

## 1. 基準と成果物

- 作成時の基準: 共有ツリー C:/godot/greenvader、ブランチ poc/3d-quarter-view、HEAD 9d54a6d（Codexが並行してコミット中）。引渡し時点はHEAD e7d86a5で、成果物はすべて未追跡・未コミットです（4.5節）。追加コンテンツは既存ファイルに依存しない新規パスだけで構成しています。
- 成果物のパス: scripts/content_pack/、data/content_pack/、assets/content_pack/、scenes/content_pack/、tests/content_pack/、evidence/content_pack/、launchers/labs/run_content_lab.bat。
- Godotの実行: 共有ツリーのGodot/importはCodex側（POC3-INPUT）の所有だったため、確認・試験はリポジトリ外の隔離プロジェクト C:/godot/greenvader_content_sandbox/ で行いました（`tests/content_pack/sync_sandbox.sh` で同期）。共有ツリーでの起動確認は統合担当の作業です。
- 統合担当: Codex（PoC3共通基盤の親）。Git index/commitは、両者の親が調整して行います。

## 2. 統合待ちの接続（未記入の項目は実装後に記入）

| # | 共通側の対象 | 必要な変更 | 理由（カタログ） |
|---|---|---|---|
| 1 | セッションの更新ループ | 追加コンテンツの窓口を生成し、ポーズ中を除いて毎tick `advance(dt)` を呼び、返るイベントを適用する | 1.5、1.10 |
| 2 | 保存・復元 | 窓口の `to_dict()` を保存データへ加え、復元時に `from_dict()` | 1.6、1.10 |
| 3 | 価格・返還 | 同種価格の数え方に `price_family` を使う。撤去時の返還にジャガイモの貯蔵を加算。枯死・敵破壊は返還0 | 1.6、1.7、P21 |
| 4 | 成長倍率 | 共通基盤の給水規則（未給水0.5）を接続口へ渡す | 1.5 |
| 5 | 配置判定 | 水面への配置（ハス）、荒地への配置（サボテン、下地を種の段階に） | P10、P14 |
| 6 | マップデータ | 清水の矩形、日陰（または計算規則）、ガラクタ置き場（位置・在庫） | 1.11 |
| 7 | マップ・画面の検知 | 擬態中の敵を検知から除外し、見破り後は通常どおり | 1.8 |
| 8 | 地域安定 | 生存中の追加敵を数え、中立（ミツバチ）は数えない | 1.8 |
| 9 | 巣の規則 | アリ塚を小規模の固定巣として、活動・報酬・階級に接続 | E17 |
| 10 | 戦闘 | 主人公の射撃・バズーカ・たいあたり・水、おたすけ植物の攻撃を、追加敵への被弾として渡す | 1.10 |
| 11 | 敵の狙い | 既存の敵にも、ニンニク（株を見失う）・ラベンダー（虫を遠ざける）・タケ（移動を遮る）を作用させるか | P17〜P19 |
| 12 | 昼夜 | ヒマワリ・ヒカリゴケに昼夜を渡す | P08、P28 |
| 13 | 表示 | 2D表示基盤（POC3-SPRITE-VIEW）へ、仮スプライトの足元基準・表示サイズと状態記号を接続 | 4 |
| 14 | 植物一覧・お気に入り | 28種の解放条件（化石など）と一覧表示 | — |

### 2.1 第2弾（CONTENT-02）で必要な接続

第2弾（動物13種・栽培植物8種、詳細は [CONTENT_CATALOG_2](CONTENT_CATALOG_2.md)）の統合待ちの接続です。第1弾の表（#1〜14）とは別に、カタログ2の5節の項目に対応させています。**第2弾も通常ゲームへは未接続**です。

| # | 共通側の対象 | 必要な変更 | 理由（カタログ2） |
|---|---|---|---|
| 15 | 水の着弾マス | 水やり・スプリンクラーの着弾マスを受け取り、6秒の濡れ、モグラの追い出し、サイの錆、ヘチマの補充に使う。確認画面の仮規則（陸のみ半径15px以内）は確認画面専用 | 1.4、E22、E28、P33 |
| 16 | 敵の向きと旋回、弾の反射 | 敵の向きと旋回上限、正面120°の判定、跳ね返した弾を主人公・おたすけ植物へ当てる | 1.2、E31 |
| 17 | 主人公の気絶、おたすけ植物の一時停止 | 気絶中は主人公の入力を無効にする。臭気・気絶でおたすけ植物の仕事を止める | E23、E32 |
| 18 | マンホールの巣とマンホールへの植物設置 | 栽培植物で塞ぐ制圧と、マンホールのマスへの例外的な設置 | E26 |
| 19 | 地中の敵の検知 | 盛り土の位置で検知する（地中のモグラは射撃・バズーカ・たいあたりが当たらない） | E22 |
| 20 | 動的な日陰、ドクダミの常時判定 | ヒノキの日陰を shade に重ねる。ヒノキが失われると消える | 1.5、P34 |
| 21 | 植物からの播種・給水イベント | タンポポ・ホウセンカの播種、ヘチマの給水を共通基盤の処理で扱う | P30、P33、P36 |
| 22 | 中立ボーナスの初期配置 | ガラスジカの初期配置の抽選（専用乱数、地域あたり最大1頭）と、マップの別記号 | N01 |

- 共通基盤の受け取り側で、票の注意に挙がった反映項目: water_landed、relay_events、hero_stun / hero_slow / helper_stop。統合担当が窓口の実際のイベント名と照合してください。
- ガラスジカの配置は、窓口の place_glass_deer を初期配置時に1回だけ呼びます（5.1節）。

## 3. 関数・イベント・データの詳細

### 3.1 部品と読み込み

- 窓口: `scripts/content_pack/content_pack.gd`（`class_name` なし。`const ContentPack = preload("res://scripts/content_pack/content_pack.gd")`）。`ContentPack.new(host, seed)` で生成します。`pack.crops`（植物）と `pack.enemies`（敵）を持ちます。
- 定義データ: `data/content_pack/crops.json`（28種＋親のクローバー）、`enemies.json`（21種＋付属: マッシュリング子、ミツバチの群れ、アリ塚）、`sprites.json`（画像の size と足元基準 foot。占有・当たり判定とは別）。
- 画像: `assets/content_pack/*.png`（63枚）。`scripts/content_pack/lab/sprite_bank.gd` が `Image.load_from_file` で読むため、`.import` は不要です。
- 位置は既存と同じ論理px（1マス=4px）、マスは `Vector2i` です。

### 3.2 ホスト接続口（`content_host.gd` を継承して実装する）

| 関数 | 共通側で返すもの |
|---|---|
| `in_bounds / is_explored / is_walkable / is_building / is_water / is_blocked(cell)` | 既存の WorldState・配置・探索記憶 |
| `is_clean_water(cell)` / `is_shade(cell)` | 追加するマップ属性（2節の#6） |
| `is_green(cell)` / `grass_stage(cell)` | 緑化段階（種・芽・成長途中・成熟の区別） |
| `growth_multiplier(crop)` | PoC3の給水規則（未給水0.5／給水済み1.0） |
| `price(kind, family_count)` | PoC3の価格式 `ceil(基本×1.05^n)` |
| `is_day()` | 昼夜 |
| `hero()` | `{pos, hp, max_hp, aim}` |
| `helpers()` | おたすけ植物 `[{id, pos, hp, max_hp}]` |
| `pollinators()` | 追加不要（ミツバチの巣は敵側から自動で加わる） |
| `is_stable_cell(cell)` | 安定地域のマス |
| `line_clear(a, b)` | 既存の射撃遮蔽 `blocks_projectile` の否定 |
| `nest_active(pos, kind)` | 既存の巣の活動条件（接近・緑化）。確認画面では「主人公20m以内、または周辺8マスに緑地」の簡易版 |

### 3.3 共通側から呼ぶ関数

- 毎tick: `pack.advance(dt) -> Array[Dictionary]`（ポーズ・マップ・一覧表示中は呼ばない）。
- 植物: `pack.crops.place_crop(kind, cell)`、`check_placement`、`quote(kind)`、`remove_crop(id, "manual")`（返還はイベントの refund）、`production_info(id)`（基礎／補正後の内訳）、`family_count(family)`、`mature_crops()`、`get_crop(id)`、`crop_id_at(cell)`、拾い物の一覧。
- 戦闘: `pack.enemies.hittable_targets()`（当たり判定の候補。飛行中・潜行中は含まれない）→ 当たったら `pack.hit_enemy(id, amount, kind, from_pos)`。範囲は `pack.splash(pos, radius_px, amount, kind)`。kind は `shot / bazooka / tackle / water / helper / spine`。種が地面に落ちたら `pack.enemies.notify_seed(pos)`（擬態の見破り）。
- 出現: `pack.enemies.spawn(kind, pos, "initial"|"produced", {tier, home, ...})`、`spawn_mushling_family`、`spawn_wolf_pack`、`add_junk_pile(pos, stock)`。
- 表示・検知: `detectable_enemies()`（擬態中を除く。マップ・画面の検知に使う）、`hint_marks()`、`slime_cells()`、`gas_clouds()`、`projectile_list()`、`structure_rects()`（巣・アリ塚の占有。主人公の通行阻止は共通側で行う）、`body_blockers()`（コケガメ）。
- 安定判定: `living_count_for_stability()`、`counts_for_stability(id)`。
- 保存: `pack.to_dict()` / `pack.from_dict(d)`（全体を検証してから一括採用。失敗時は何も変えず false）。

### 3.4 出力イベント（共通側で適用する）

| type | 共通側の処理 |
|---|---|
| `seeds{crop_id, amount}` | 共通備蓄へ加算 |
| `seeds_stolen` | 窓口内でウサギのほお袋へ（共通側の処理不要） |
| `crop_removed{reason, refund}` | 返還を加算、現存数・一覧を更新。reason は manual / enemy / poison |
| `crop_placed`, `crop_matured`, `variant{from,to,debug}`, `mint_spread` | 一覧・表示の更新。debug=true は確認画面だけ |
| `ground_seed{cell}` | サボテンを荒地に置いたとき、下地を種の段階へ |
| `ground_stage{cell, stage, cause}`, `growth_pause{cell, seconds}` | 粘液・種の食害による緑化段階の変更と成長停止 |
| `fertile{pos, radius_px}` | 既存の死骸の肥沃化と同じ処理 |
| `hero_damage`, `helper_damage`, `heal` | HPの増減 |
| `hero_pull{to}` | 主人公の移動（障害物で止める判定は共通側） |
| `hero_slow{factor, seconds}` | 主人公の減速 |
| `reward{amount, tier, nest?}` | 階級倍率を掛けて備蓄へ（初期配置の最終撃破時だけ1回発生） |
| `enemy_defeated`, `enemy_damaged`, `junk_pile_*`, `mushling_call`, `fx{kind,...}`, `pickup_collected` | 表示・効果音 |

### 3.5 注意点

- 敵の移動は `enemy_system.gd` の `step_move / can_stand / walk_to / wander` に集めた単純な直進と回避です。統合時は共通の経路探索へ置き換えてください。
- 確認画面の価格・成長倍率・昼夜・巣の活動は、`lab_host.gd` の仮アダプター（PoC3の規則を写したもの）です。本番では共通基盤の実装を使います。
- 隔離実行: 確認・試験は `bash tests/content_pack/sync_sandbox.sh`（同期）→ Godotを `--path C:/godot/greenvader_content_sandbox` で実行 → `sync_sandbox.sh pull`（証拠・生成画像の回収）で行いました。回収前に再同期すると、リポジトリにない生成物が消えます。

## 4. 自動生成ファイルの扱い

- 共有ツリー側のGodot（エディタまたはimport）が起動した際に、`assets/content_pack/*.png.import`（63個）と、`scripts/content_pack`・`tests/content_pack` の `*.gd.uid` が自動生成されました（2026-10-24時点で確認）。CONTENT-01の作業はこれらを生成・削除していません。
- 追加コンテンツは `.import` を前提にせず画像を実行時に読むため、これらがなくても動作します。コミットに含めるかどうかは、統合時に両者の親が決めてください（Godot 4.4以降の慣例では `.uid` はコミット対象）。
- `tests/content_pack/sync_sandbox.sh` の回収（pull）は、隔離先で生成された `.import` / `.uid` を持ち込みません。

## 4.5 検証記録（転記用の事実）

共有の [VALIDATION](VALIDATION.md) と [STATUS](STATUS.md) は他担当の範囲のため、ここに転記用の事実をまとめます。

- **対象**: 共有ツリー C:/godot/greenvader、HEAD e7d86a5時点（成果物はすべて未追跡・未コミット）。
- **凍結マニフェスト**: `evidence/content_pack/self/manifest_stage4.txt`（111件、SHA-256 `f29e2985c681ba4f280781e97585ce6ceb595560245040fba9f25b2d699d17a0`）。
- **実行環境**: Godot 4.7.2。隔離プロジェクト C:/godot/greenvader_content_sandbox のみで実行。実GPUは NVIDIA GeForce RTX 5070 Ti（Vulkan、Forward+）。
- **入力と撮影**: 入力は `Input.parse_input_event` のみ。撮影は `root.unfocusable=true`。OS入力送信・前面化は行っていません。ただしGodotの仕様上、ウィンドウ生成時の初回フォーカスはスクリプトで防げません。
- **実装者の自己検証**（`evidence/content_pack/self/`）: crops_logic 145 PASS、enemies_a 72 PASS、enemies_b 71 PASS、lab_logic 124 PASS、lab_gpu 24 PASS、save_robust 55 PASS。FAIL 0。
- **独立検証**（`evidence/content_pack/independent/`、別呼出しの検証担当）: 自作テストは crops_v 192、enemies_v1 143、enemies_v2 134、lab_v 78、extra_v 7、asset_v 7、gpu_v 7 の計568件、FAIL 0。回帰5本の件数は自己検証と一致。合格条件1〜7・9〜11はPASS。条件8は初回に F1（種類固有キーが欠けた保存を採用し、進行時にエラー）でFAIL。
- **差戻しと修正**: `enemy_system.gd` の保存検証を種類テンプレート照合に変更。`sync_sandbox.sh` が `*.import` / `*.uid` を持ち込まないよう修正。
- **再検証**: robust_v は採用0／拒否87。robust_v2は32 PASS（途中状態の保存復元16回すべて採用、復元後20秒の進行が一致、型違い50件超を拒否）。影響回帰の enemies_v1 143、enemies_v2 134、lab_v 78、enemies_a 72、enemies_b 71、lab_logic 124 はすべてPASS。条件8 PASS。
- **NOT_RUN**: 共有ツリーでの実起動（`run_content_lab.bat` を含む。共有ツリーのGodot/importはCodex側の所有だったため）、ウィンドウ上の整数倍拡大の撮影、物理キーボード・マウス経路、通常ゲームへの統合、長時間の通しプレイ、最終バランス、ユーザーによる美術・楽しさの評価。
- **既知の限界**: 飛翔物・ガス雲の保存の型検証は、独立検証ではコードの読解のみ（実装者の自己検証では確認済み）。保存データの値の範囲（負のHP等）は検査していない（キーと型のみ）。

## 4.6 検証記録（第2弾 CONTENT-02、転記用の事実）

- **対象**: 共有ツリー C:/godot/greenvader、HEAD 047a540 + 未コミット差分（独立検証時点）。第2弾の成果はすべて未コミット。
- **凍結マニフェスト**: `evidence/content_pack/self2/manifest_stage2.txt`（79件）、`manifest_stage3.txt`（242件）。独立検証の最初と最後に sha256 で全件一致。
- **実行環境**: Godot 4.7.2。隔離プロジェクト C:/godot/greenvader_content_sandbox で実行（`sync_sandbox.sh` で同期）。独立検証では pull を使っていない。
- **実GPU**: NVIDIA GeForce RTX 5070 Ti（Vulkan）。ウィンドウは unfocusable。入力はエンジン内入力のみで、OS入力は送っていない。
- **自己確認と独立検証**: 件数は [CONTENT_CATALOG_2](CONTENT_CATALOG_2.md) の10.2節・10.3節と同じ。合格条件1〜10はすべてPASS、FAIL 0（独立検証）。自己確認の FAIL 4件は想定内の古い固定判定（同10.4節）。
- **回帰**: 第1弾の crops 145、enemies_a 72、enemies_b 71、save_robust 55、lab_gpu 24 PASS、lab_logic 123/124（想定内の1件）。
- **NOT_RUN**: 物理キーボード・マウス経路、通常ゲームへの統合、共有ツリーでの起動（統合担当）、ユーザーによる楽しさ・バランス・美術の評価。
- **注意**: `sync_sandbox.sh pull` は `evidence/content_pack/self2` を上書きするため、回収先は `independent2` に限ること。

## 5. 未確認事項

- ニンジンの回復対象（ユーザーの想定はおたすけ植物を含む／第二弾仕様は主人公のみ）。追加コンテンツ側では変更していません。
- 数値はすべて仮値で、最終バランス調整は行っていません。

### 5.1 第2弾（CONTENT-02）分

- 未確認: 物理キーボード・マウス入力（OSを経てGodotへ届く経路）。検証はエンジン内入力のみ。
- 未確認: 通常ゲームへの統合。共有ツリーでの起動確認は統合担当の作業。
- 未評価: 楽しさ・バランス・美術の評価はユーザーの確認事項。
- 統合時の注意（独立検証の観察、合否外）:
  - place_glass_deer を同じ地域キーで2回呼ぶと2頭目が出る。初期配置時に1回だけ呼び、読込後に再実行しない。
  - タイホウエビは待機中に徘徊するため、対象が射程外へ出ると次の予兆が遅れる（位置を固定すると衝撃波の間隔は5.0秒）。
  - コウモリ・ウナギ・フウセンガエル・ガラスジカの画像は下辺に画素が届かない（飛行・水中・半透明の設計）。足元座標は下辺中央。
