# 素材台帳

更新日: 2026-10-18。権利・出典・状態は実装報告と親の承認済み情報に基づく。

## P0画面素材

| 素材 | 出典・編集元 | 用途・状態 |
|---|---|---|
| 花、種、植物、敵、樹木、苔岩、シダ、廃墟、地形、水面、地面影 | 実装者がGDScriptの文字行・整数矩形から作成したnativeラスタ。`scripts/pixel_art.gd`、`scripts/landscape_art.gd`、`scripts/landscape_prop.gd`、`scripts/terrain.gd`。外部画像・画像生成サービスなし。 | P0画面のコード製素材。花は16×16px。4枚のユーザー参考画像は方向の参考のみで、直接転用・切り抜きなし。 |
| 日本語UIフォント | WindowsのYu Gothic / Meiryoを実行時に参照。フォントファイル非同梱。 | UI表示用。外部フォントファイルは配布していない。 |
| 晴雨夜の最終画面画像 | Godot実行時に生成した内部viewport PNG。 | 検証用証拠で、ゲームへ読み込む素材ではない: [晴れ](../evidence/p0-art/self/sunny-1280.png)、[雨](../evidence/p0-art/self/rain-1280.png)、[夜](../evidence/p0-art/self/night-1280.png)。 |
| 親のnative画面画像 | 実行中ウィンドウのスクリーンショット。 | 晴天時の表示証拠: [native-sunny.png](../evidence/p0-art/native-sunny.png)。素材データではない。 |

## 承認状態

ユーザーはP0_ARTの現ビジュアル方向を当面の基準として承認し、細部の追加描き込みをいったん止めるよう希望した。これは方向性への承認であり、最終商品アート、参考画像と同等の完成度、またはゲーム全体の美術承認ではない。追加の細部調整は保留し、必須のピクセル条件と機能検証は維持する。

## P1で追加したコード製素材

P1で追加した素材はすべてGDScriptで生成した。外部素材はない。権利・出典は自作（コード生成）。以下は機能上の仮素材で、輪郭線は付けない。

| 素材 | 出典・編集元 | 用途・状態 |
|---|---|---|
| 4pxタイルの地形・段階（種・芽・成熟・縁）の描画 | GDScript（`scripts/` 配下のP1実装）。芽の位置は、タイルごとに固定乱数で中央2×2pxの4候補から決め、状態に保持する | 1タイル4×4px。種は1pxの点、芽1は1×1px、芽2は縦2×横1px、成熟はタイル全体を緑で塗る。成熟した隣接がない辺の外側1pxを半透明にする。区画ごとの画像として描く |
| 種の供給源 | GDScript（`scripts/` 配下のP1実装） | 安全地帯に置く、破壊されない種の供給源。一定間隔で種の実を落とす |
| 実（種の実・植物の実・回復の実） | GDScript（`scripts/` 配下のP1実装） | 種の実（供給源が落とす）、植物の実（成熟植物が落とす種の実）、回復の実（キウイが落とす）。形と色で区別する。植物の実と供給源の実の色の近さは、P4-02で再確認する |
| にんじん・キウイ（8×8px） | GDScript（`scripts/` 配下のP1実装） | 栽培植物の見た目。2×2タイル（8×8px）を占有する |
| 浅瀬 | 地形ID（GDScript）と地図（`data/region_01.png`） | 歩ける・給水できる・対象外（種と水は植えられない）。川に4本の渡り場として置く |
| 地図PNG（`data/region_01.png`） | `scripts/tools/gen_region_01.gd` で生成 | 1px = 1タイル、512×512タイルの地域の地形マップ。import済みの無劣化テクスチャとして読む |

## ART-01 比較試作素材

専用の草地・樹木比較画面で使う新規画素はGDScriptの描画コードで作成し、画像生成サービスや参考画像の画素転用はしていない。参考画像は目視の方向参考のみ。既存の16×16px花、4×4pxの拾える種、敵素材を再利用し、木は64×84pxで作成した。Bの密度（280房）を最終的に育つ草地の選好としてユーザーが選んだ。成長処理や通常ゲームへの統合は未実装。

現在のr2画像は固定色の下地（草 `#466d46`、土 `#716c60`）を使い、広域の位置依存明暗を除いている。初回版の画像・証拠も履歴として `evidence/art01/self/` に保持。今後の美術試行は画像の編集・生成と比較、採用後に画素調整・ゲーム反映の順で行う。

| 素材・証拠 | 出典・用途・状態 |
|---|---|
| 草地・木の画素 | `scripts/art_study/` のコード製比較試作。通常ゲームには未統合。 |
| 最新r2比較PNG | [B](../evidence/art01/self/r2/B_rich_2x.png)、[全景比較](../evidence/art01/self/r2/AB_field_2x.png)、[細部比較](../evidence/art01/self/r2/AB_detail_4x.png)。CPU合成の検証画像で、実ウィンドウのスクリーンショットやゲーム読込素材ではない。 |
| 初回比較PNG（履歴） | [A](../evidence/art01/self/A_restrained_2x.png)、[B](../evidence/art01/self/B_rich_2x.png)、[全景比較](../evidence/art01/self/AB_field_2x.png)、[細部比較](../evidence/art01/self/AB_detail_4x.png)。初回出力を履歴として保持。 |

## ART-02 廃墟街区コンセプト画像

組込みimage_genで通常光案を生成し、その画像を編集して同構図の夕方案を作成した。ユーザー参考画像3枚は方向の参考のみで、直接転用していない。各画像は1672×941px。生成時の全文プロンプトは [`prompts.txt`](../assets/concepts/art02/prompts.txt) に記録。

| 画像 | 出典・用途・状態 |
|---|---|
| [通常光](../assets/concepts/art02/daylight-v1.png) | 組込みimage_genによる新規生成。廃墟、草・ツタ、通路、水たまり、小さな花を含む構図案。 |
| [夕方](../assets/concepts/art02/sunset-v1.png) | 通常光画像を入力して照明を編集した案。同じ構図を保った夕方表現の比較用。 |

親は両画像を目視し、主要な廃墟・草ツタ・通路・水たまり・花と構図の維持を確認した。照明は画像に合成済みで、独立ライトレイヤーではない。2点とも素材の原案であり、ゲームには読み込んでいない。ART-02画像自体の960×540基準での画素整理、投影、素材分割、当たり判定、遮蔽は未実施。専用小マップでの限定的な技術確認はTECH-QV-01に記録したが、その結果をART-02画像の完成素材化や通常ゲームへの統合と扱わない。

## ART-03 解像度比較画像

親が組込みimage_genでART-02の通常光画像を編集した[原稿](../assets/concepts/art03/pixel-study-master.png)（1672×941px）を元に、同一画像をnearest中心サンプリングで960×540と640×360へ縮小し、各画素を複製して1920×1080へ拡大した。実際の[プロンプト](../assets/concepts/art03/prompt.txt)、[書き出し手順](../assets/concepts/art03/export-comparison.ps1)、[寸法・全画素照合](../assets/concepts/art03/export-checks.json)を保存している。比較書き出しでは両出力の不一致画素数は0。パレット整理や手作業での画素修正はしていない。

| 比較画像 | 内容・状態 |
|---|---|
| [960×540](../assets/concepts/art03/study-960x540.png) / [1080p・2倍表示](../assets/concepts/art03/study-960x540-at-1080p.png) | 同一原稿の960×540縮小比較。ユーザーが今後の制作・内部解像度の採用基準に選定。現行ゲームには未反映。 |
| [640×360](../assets/concepts/art03/study-640x360.png) / [1080p・3倍表示](../assets/concepts/art03/study-640x360-at-1080p.png) | 同一原稿の640×360縮小比較。960案との表示比較用。 |
| [細部比較](../assets/concepts/art03/detail-comparison.png) | 1080p表示画像から同じ矩形 `(720, 630, 600, 360)` を拡大せず切り出し、左に960案・右に640案を配置。 |

親は原稿・両表示画像・細部比較を目視し、主要構図の維持を確認した。ユーザーは960×540を今後の制作・内部解像度の採用基準、1920×1080の2倍表示として選定した。これは解像度を変えた縮小比較であり、格子と色数を手作業で整理した完成ゲーム素材ではない。ゲームへ読み込んでおらず、現行設定は640×360のままである。素材整備後に基準を反映する。他画面サイズの可変/固定・余白方式とタイル/主人公サイズは未決定。ART-02由来の光は画像に合成済みで、独立ライトレイヤーではない。最終的なユーザーの美術評価は未取得。

## ART-04 草地・舗装・小さな廃墟の画像試作

組込みimage_genでART-03の960案を参照編集し、構図案v1を生成。建物を小さく見せるため画角を引く編集を1回行い、v2を作成した。両原稿は1672×941px。実際の[プロンプトv1](../assets/concepts/art04/prompt-v1.txt)・[v2](../assets/concepts/art04/prompt-v2.txt)を保存。ユーザー参考画像は方向参考のみで、画素を直接転用していない。

| 画像 | 出典・用途・状態 |
|---|---|
| [詳細案v1](../assets/concepts/art04/ruin-grass-detail-v1.png) | ART-03の960表示案を入力した組込みimage_genによる画像編集。建物が大きかったため、v2で画角を調整。 |
| [広域案v2](../assets/concepts/art04/ruin-grass-wide-v2.png) | 画角を引いた組込みimage_gen編集。親は小建物1棟、ひび割れた舗装、草の房、壁・屋根のツタ、建物構造の面影、主人公がいないことを目視確認。建物幅は画面の約3割に見えるが、288×256px寸法への厳密適合は確認していない。 |
| [960×540表示](../assets/concepts/art04/scene-960x540.png) / [1080p・2倍表示](../assets/concepts/art04/scene-960x540-at-1080p.png) | v2をnearest中心サンプリングで縮小し、各画素を2倍複製。`export-checks.json`では1080p出力と論理画像の不一致画素数0。処理は[export-preview.ps1](../assets/concepts/art04/export-preview.ps1)、ハッシュは[image-hashes.json](../assets/concepts/art04/image-hashes.json)に記録。 |

この画像は統合された美術原稿で、完成ゲーム素材ではない。2:1角度、地面32×16/64×32px、建物288×256pxは生成プロンプト上の目標で、厳密な格子・色数・画素整理、実レイヤー分割、遮蔽、当たり判定を実装・検証していない。光は地面に広く焼き込まず、局所的な形の陰影は画像内に含む。ゲームコードや設定の変更・実行はない。最終的な美術採用はユーザー未評価。次は草の密度、舗装境界、廃墟の植物被覆を画像で確認する。

## TECH-QV-01 クォータービュー仮素材・制作条件

専用試験マップの地面・建物・低障害物は技術確認用の仮表示。草地・建物の完成素材や画像生成・描き込みは行っていない。主人公表示には既存16×16pxの仮花を再利用。画面画像は[自己検証記録](../evidence/quarter-view/self/report.md)のGPU証拠で、ゲーム読込素材ではない。

| 素材条件 | 試験値・制作時の候補 |
|---|---|
| 地面の表示格子 | 4×4論理単位を8×4px菱形で表示。美術用まとまり候補は16×16論理単位=32×16px、または32×32=64×32px |
| 建物 | footprint 144×144論理単位、高さ112px、外接288×256px。画像左上から南の足元角が原点 `(144,256)`。footprintと原点をメタデータ化 |
| 低障害物 | footprint 48×24論理単位、高さ12px、外接72×48px。見た目の高さと地面衝突を別情報にする |
| 壁・屋根の分割 | 壁と屋根を編集レイヤーで分ける。実行用は各前端足元Yを持つ列または帯に分割し、列/帯単位でsort。試験実装は1px幅列 |
| 独立part | 出入口上枠、門、橋・アーチ、ひさし、張り出し屋根、手前の柵、奥の壁、植生は深度・通行面が異なるため別part/深度/衝突情報を持つ |

通路配置は建物footprintに対しpaving外側余白が左48・右128・上48・下72論理単位、低障害物との最小gapが32単位。制作上の最低寸法保証ではなく今回の試験配置値。通常ゲームへの統合・素材書き出し・複雑な遮蔽と、他解像度対応は未検証。詳細は[TECH-QV-01記録](QUARTER_VIEW_TECH.md)。

## TECH-3D-01 低解像度3D技術試作

専用試作 [`scenes/render_study_3d.tscn`](../scenes/render_study_3d.tscn) は自作meshと[`concrete.gdshader`](../assets/render_study_3d/concrete.gdshader)を使い、外部テクスチャや画像生成画像を使っていない。朝・昼・夕のDirectionalLight3D、2:1地面格子、一階廃墟（凹窓・閉じた錆扉・欠けた平板屋根とパラペット）、瓦礫、独立した小さな草パーツを含む。既定は昼で、当時は `run_render_study_3d.bat` から起動し、1/2/3キーまたは画面ボタンで時間帯を切り替えていました。この入口は削除済みで、保全タグ `poc2-before-poc3` から復元できます。シーンは保持されています。直接起動はGodotへ `--path C:/godot/greenvader res://scenes/render_study_3d.tscn` を渡します。960×540でGPU描画し、別1920×1080 viewportへnearest 2倍表示する記録です。

自己報告・manifest・GPU結果は[`evidence/render-study-3d/self/`](../evidence/render-study-3d/self/report.md)、独立確認は[`evidence/render-study-3d/independent/report.md`](../evidence/render-study-3d/independent/report.md)。保存PNGと根拠の範囲、未検証事項は[検証記録](VALIDATION.md#tech-3d-01-低解像度3dと動的影の試作)を参照。これは画風比較用の技術試作であり、ゲーム素材ではない。通常ゲームに読み込まず、成長状態に応じた植生、通常ゲーム統合、性能、大量描画は未実装・未確認。親は技術成立性を限定受入したが、最終美術評価は未取得。

## TECH-3D-03 仮歩行sprite・投影影の試作

専用fixtureは[`sprite_shadow_fixture.gd`](../scripts/render_study_3d/sprite_shadow_fixture.gd)で作る32×48px・4コマのコード製技術素材。完成主人公アートや通常ゲーム素材ではない。[`walk_full_4s.mp4`](../evidence/render-study-3d/sprite-shadow/self/walk_full_4s.mp4)と[`walk_closeup_4s.mp4`](../evidence/render-study-3d/sprite-shadow/self/walk_closeup_4s.mp4)は各72枚の640 PNGを18fpsで並べた4秒の提示動画。動画圧縮があり、PNGと同じ画素保証や実時間FPS測定を意味しない。独立は5 PASS / 0 FAIL / 3 NOT_RUN、凍結26件・既存6件のhash一致。代表GPU画像、個別フレーム、初回試作と修正版、独立確認は[検証記録](VALIDATION.md#tech-3d-03-歩行スプライトと投影影の同期)と[`evidence/render-study-3d/sprite-shadow/`](../evidence/render-study-3d/sprite-shadow/self/report.md)を参照。

## TECH-3D-04 照明操作用の専用lab

手動確認入口は[`run_light_lab.bat`](../launchers/labs/run_light_lab.bat)。起動後、左パネルで太陽ON・方位・仰角を調整し、点光源ON、自動周回ON/OFF、停止時の角度を試せる。UI付き代表画像は[default 1920](../evidence/render-study-3d/light-controls/self/default_ui_1920.png)、[point-only 45° 1920](../evidence/render-study-3d/light-controls/self/point_only_45_ui_1920.png)、[太陽135°/25° 640](../evidence/render-study-3d/light-controls/self/sun_135_25_ui_640.png)、[315°/61° 640](../evidence/render-study-3d/light-controls/self/sun_315_61_ui_640.png)。UI画像の1920版は640 GPU rootからのCPU nearest 3倍提示で、native撮影ではない。world-onlyの[640](../evidence/render-study-3d/light-controls/self/default_world_640.png)と[1920 GPU readback](../evidence/render-study-3d/light-controls/self/default_world_1920.png)は別viewportで比較した。

[周回点光源の動画](../evidence/render-study-3d/light-controls/self/orbit_controls_4s.mp4)と[復号接触シート](../evidence/render-study-3d/light-controls/self/video_decode_contact.png)は48サンプルを12fpsで並べた4秒の提示物で、実時間FPS計測ではない。試作結果と限界は[TECH-3D-04検証記録](VALIDATION.md#tech-3d-04-太陽角度と周回点光源)を参照。これは専用技術確認であり、通常ゲーム素材・照明設定ではない。

## ART-05 緑化3段階コンセプト

[triptych v1](../assets/concepts/art05/greening-triptych-v1.png)は組込みimage_genで作った2172×724pxの横3面コンセプト画像。[TECH-3D-02の硬影A画像](../evidence/render-study-3d/style/A_hard_shadow_1920.png)を参照入力にし、[最終prompt](../assets/concepts/art05/prompt.txt)と[自己所見](../evidence/art05/self/report.md)を保存。ユーザーはv1をイメージとして十分と判断し、追加美術調整を停止した。独立目視は未実施。画像は合成された参考案で、厳密な格子/3面一致、ピクセルパーフェクト、分離ゲーム素材、GPU描画や成長率を保証しない。v2用promptは残るが生成画像はworkspace未保存・未採用。検証記録は[ART-05](VALIDATION.md#art-05-緑化3段階コンセプト画像)。

## TECH-3D-05 共通植生部品の再利用試作

手動確認は[`run_vegetation_lab.bat`](../launchers/labs/run_vegetation_lab.bat)。同じ草mesh2種・葉群・茎と材質をA低い横長箱/B縦長箱/C円筒レンガ塔＋円錐金属屋根で共有する専用lab。0/50/100%の[成長比較](../evidence/vegetation-lab/self/growth_000_ui_1920.png)、[50%](../evidence/vegetation-lab/self/growth_050_ui_1920.png)、[100%](../evidence/vegetation-lab/self/growth_100_ui_1920.png)と[C近景](../evidence/vegetation-lab/self/C_mature_closeup_ui_1920.png)を保存。UI付き1920画像はGPU root640からのCPU nearest 3倍、world単体1920は別GPU viewport出力。建物定義はsize/surface/openings/corridor/seedを与え、配置数は草298/276/300、ツタ経路6/2/12。これは固定配置成長と共有Resourceの技術fixtureで完成素材や通常ゲーム機能ではない。詳細と限界は[TECH-3D-05検証記録](VALIDATION.md#tech-3d-05-共通植生部品の再利用試作)。

## TECH-3D-06 枝ツタ・苔・ひび模様の追加試作

手動確認入口は[`run_vegetation_lab.bat`](../launchers/labs/run_vegetation_lab.bat)。既存A/B/Cと共通葉・茎を保ち、枝ツタをA/B/Cで10/8/94本表示する。[A屋根近景](../evidence/vegetation-branches/self/A_roof_branches_closeup_ui_1920.png)と[C枝近景](../evidence/vegetation-branches/self/C_branches_closeup_ui_1920.png)を保存。枝は親接続gap 0で親到達後に伸びる。窓・端で停止し自動迂回はしない。Bは窓除外のため実枝が+u方向のみで、配置表面の指定が必要な試作。任意meshへの自動巻付けではない。

苔は植生の成長率から独立した面・node・materialで、ON/OFFと量0〜100を操作できる。ひび模様は低優先の独立表示ON/OFFで、破壊や地形変更は行わない。簡略化されていたA屋根は旧形状（欠けたスラブ・立上り・鉄筋）へ戻し、旧geometry自体は変更していない。証拠画像・限界・検証は[TECH-3D-06記録](VALIDATION.md#tech-3d-06-枝ツタ苔ひび模様の専用試作)と[自己報告](../evidence/vegetation-branches/self/report.md)を参照。これは640×360をnearest 3倍で提示する技術fixtureで、ゲーム素材・最終美術の承認ではない。

## TECH-3D-07 ツタ・苔の形状バリエーション

手動確認は引き続き[`run_vegetation_lab.bat`](../launchers/labs/run_vegetation_lab.bat)。同じ葉・茎のまま直線寄り/蛇行する幹と曲がる枝を混ぜ、開始間隔・位相・枝高さ/長さを固定seedで変化させる。草の乱数列、屋根、UI、ひび、既存起動方法は維持。苔は約1×1/2×2相当の表面パッチを混ぜ、大きいパッチは細分割し開口でclipする。苔の量とON/OFFは独立のまま。曲線も開口前で止まり自動迂回しない。代表画像と限界は[検証記録](VALIDATION.md#tech-3d-07-ツタと苔の軽量バリエーション)および[自己報告](../evidence/vegetation-variation/self/report.md)。これは640×360の専用技術fixtureで、通常ゲーム素材・最終美術の承認ではない。

## TECH-3D-08 地面緑化・歩行・太陽方位の小マップ

手動入口は[`run_greening_map.bat`](../launchers/labs/run_greening_map.bat)。48×40セル（1セル0.4m、全体19.2×16m）のA/B二棟、水域、舗装、初期成熟域を持つ専用小マップ。WASD/矢印で画面方向へ歩き、左クリックで種、右クリックで水を射程3m内へ直接散布（押下ごとに1回）。有限資源は種20・水100から開始し、水辺補給と試作用補給を持つ。成長倍率は初期×4、×1、成長停止から選択でき、停止中も歩行・散布可能。太陽方位0〜360度は見た目の照明だけを変える。640×360 nearest 3倍と既存仮sprite/影同期を使用。保存、敵、本番資源循環、建物ツタ成長連動は範囲外。画像と検証は[TECH-3D-08記録](VALIDATION.md#tech-3d-08-小マップ歩行地面緑化太陽方角)と[自己報告](../evidence/greening-map/self/report.md)。

## TECH-3D-09 舗装の緑化表示と水面反射

起動は既存[`run_greening_map.bat`](../launchers/labs/run_greening_map.bat)。舗装id6では固定ひび経路に沿う1束の半scale草を表示し、成長に応じてひび長を変える。土は従来の3束・RNG・transformを維持。視覚だけの変更で、地形/対象/stage/growth/count・成長速度は不変。水は320×180同world平面の反射cameraとnearest textureを使い、地面・基壇・水自身を反射対象から除く。通常池は反射範囲に構造物が少ないため、A棟前の舗装へ1.4×0.8mの歩行可能・論理水域なしの視覚専用水たまりを追加し、同じ反射textureを共有する。ひびmeshと水shaderは今回の自作コード、草は既存共有部品を使用し、参考画像からの転載や画素抽出はない。比較は[final_comparison](../evidence/terrain-water/self/final_comparison_ui_1920.png)、[反射ON](../evidence/terrain-water/self/normal_reflection_ON_ui_1920.png)、[sun135](../evidence/terrain-water/self/normal_sun135_ui_1920.png)。同成熟状態を並べた比較で、自然成長到達画面ではない。性能コストは未測定、任意の水中形状を切るclip面は未実装。独立[報告](../evidence/terrain-water/independent/report.md)も参照。[検証記録](VALIDATION.md#tech-3d-09-地形別の緑化表示と水面反射)。

## TECH-3D-11 局所壁面成長と水面受影

手動確認入口は既存[`run_greening_map.bat`](../launchers/labs/run_greening_map.bat)。A/B棟の可視前・右壁だけに、対応する根元からツタとコケが別々に成長する。入力は基壇外0.2m、半径0.65m内の対象地面セル平均（未緑化セルを含む）で、成長tickは0.5秒、入力1ではツタ90秒・コケ135秒。部分入力は速度だけ低下し、近傍緑化を失うと進捗を保持して停止する。pause中も停止し、太陽角度とは無関係。内部の緑化対象・分母・進行は変えない。水は現太陽1灯のshadow attenuationを反射色へ適用し、暗部下限42%とする専用表現。屋根成長や汎用物理水・複数光源対応ではない。

自己[報告](../evidence/wall-growth/self/report.md)と独立[報告](../evidence/wall-growth/independent/report.md)を参照。壁面GPU画像は成熟地面を前面に配置した試験fixtureで、自然な拡張で成熟に到達した画像ではない。保存、性能、物理入力、全マップ/姿勢は未検証。共通部品と旧lab既定挙動を維持し、通常ゲーム統合や最終美術承認は別判断。

## TECH-3D-12 建物モデル1棟

[新Aモデル](../assets/models/ruin_house/ruin_house.glb)はGodotのコード生成GLB（82mesh、83node）。AI画像・外部モデル・Blender素材を使わず、窓の凹み/枠/桟、閉じた扉、ひさし、欠け屋根、分割パラペット、鉄筋を個別meshとして保持する。単位m、足元矩形中心原点、主要壁6×4.8×2.8m。全mesh AABBはmin `(-3.175,-0.06,-2.56)`、size `(6.345,3.509645,5.355)`で既存A基壇内。植物/地面/衝突や焼込み照明はモデルに含まない。生成と再importの詳しい手順・metadataは[asset README](../assets/models/ruin_house/README.md)、接続と再利用上の制約は[建物モデルガイド](BUILDING_MODEL_GUIDE.md)。

小マップAは新GLBを通常importして使用し、既存A基壇・論理衝突は維持。共通植生はmetadataの面/開口/ひさし定義に基づき派生するため、任意建物の自動認識には対応しない。最大成長設定でのA/B可視4面の保守的な被覆面積上限は24.3〜36.0%（重複・開口上・壁外の寄与を差し引かない計算）で、実画素率やユーザーの美術評価ではない。独立[報告](../evidence/building-model/independent/report.md)は5 PASS / 0 FAIL / 3 NOT_RUN、凍結16・保全452・証拠44件一致。生成import sidecar 66件は[一覧とhash記録](../evidence/building-model/self/import-sidecars.json)を保存し、削除していない。次の手動確認入口は既存[`run_greening_map.bat`](../launchers/labs/run_greening_map.bat)。

## TECH-3D-13 納品アセットの専用展示

`C:/godot/greenvader_asset_deliveries/assets`から元モデルを改変せず、6カテゴリ各4件・計24件を飛び飛びIDで選び、元縮尺のまま専用展示へ配置した。選択IDはBLD-007/038/079/123、VIN-007/032/047/060、MOS-003/012/024/035、TRE-001/027/054/074、GND-009/036/059/077、PRP-001/041/075/121。展示用コピーはGLB24・metadata24・参照PNG9。出典パスとhashは[manifest](../assets/models/delivery_showcase/manifest.json)に記録し、元ファイルの権利・ライセンス確認済みとは扱わない。

各カテゴリの最終画像は[建物](../evidence/asset-showcase/self/BLD_category_ui_1920.png)、[ツタ](../evidence/asset-showcase/self/VIN_category_ui_1920.png)、[苔](../evidence/asset-showcase/self/MOS_category_ui_1920.png)、[樹木](../evidence/asset-showcase/self/TRE_category_ui_1920.png)、[地面](../evidence/asset-showcase/self/GND_category_ui_1920.png)、[小物](../evidence/asset-showcase/self/PRP_category_ui_1920.png)。起動は[`run_asset_showcase.bat`](../launchers/labs/run_asset_showcase.bat)。床と簡単な受け面だけの展示であり、水面反射、植物成長、衝突、主人公、通常ゲーム統合は未実施。検証の範囲と未検証事項は[TECH-3D-13記録](VALIDATION.md#tech-3d-13-納品アセット展示マップ)。

## TECH-3D-15 小街区・昼夜試作

専用labは納品元から建物7種（BLD-007/019/038/046/079/091/123）、小物7種（PRP-001/005/012/017/034/041/075）、既存樹木（TRE-001）を使用する。15種のGLB・metadata・必要テクスチャ計42ファイルを[`assets/models/town_lab/`](../assets/models/town_lab/README.md)へコピーし、出典とSHA256を[manifest](../assets/models/town_lab/manifest.json)へ記録。親baselineの既存167ファイル、元納品42ファイル、凍結106ファイルは独立SHA256照合ですべて一致した。詳細は[自己報告](../evidence/town-lab/self/report.md)と[独立報告](../evidence/town-lab/independent/report.md)。納品元素材の権利・ライセンス確認済みとは扱わない。

街区は元scaleを維持して実AABBで接地。選定素材による50m四方程度の屋外回遊用で、配置の全体像は[朝](../evidence/town-lab/self/morning_overview_ui_1920.png)、[昼](../evidence/town-lab/self/noon_overview_ui_1920.png)、[夕](../evidence/town-lab/self/evening_overview_ui_1920.png)、[夜](../evidence/town-lab/self/night_overview_ui_1920.png)。水面は[昼の受影](../evidence/town-lab/self/water_day_shadow_ui_1920.png)と[夜の局所灯受影](../evidence/town-lab/self/water_night_lamps_ui_1920.png)、[建物反射](../evidence/town-lab/self/water_building_reflection_ui_1920.png)で確認できる。親は自己38 PASS / 0未解消FAIL / 4 NOT_RUN（初回34 PASS / 2 FAILを保全して修正影響のみ再取得）、独立7 PASS / 0 FAIL / 4 NOT_RUNを確認し、専用labに限定して受入した。使い方は[小街区試作ガイド](TOWN_LAB.md)、検証範囲と限界は[TECH-3D-15記録](VALIDATION.md#tech-3d-15-納品モデルの小街区歩行昼夜試作)。この素材配置は専用lab用で、通常ゲームへの統合を意味しない。

## PoCの音（自作・コード生成）

権利・出典は自作（コード生成）。外部の音声ファイル・外部素材は使用していない（WTH-02の独立検証で外部音声ファイルなしを確認）。実音の聴取はユーザー確認待ちです。

| 素材 | 出典・編集元 | 用途・状態 |
|---|---|---|
| 操作音8種（種・水・設置・拾得・命中・巣破壊・地域安定・全緑化） | `scripts/poc/audio/poc_audio.gd`。AudioStreamWAV（16bit、22.05kHz）をGDScriptで合成。外部素材なし。 | PoCの操作の反応音。種まき・給水・おたすけ植物の設置・拾得・命中・巣破壊・地域安定・全緑化で鳴る。 |
| 環境音（風、雨、緑化率に応じた小鳥） | 同上（コード合成）。 | 常時の環境音。雨は雨音、小鳥は緑化率に応じて鳴る。 |

- ミュートはMで切り替え、設定は `user://poc_ui_settings.json` に保存（ゲームの保存データではない）。
- pause中・展望中・失敗時は無音。音と展望は表示・演出のみで、判定や100％保証には影響しない。

## SPR-01 通常歩行・跳ね歩き比較素材（2026-10-20）

通常歩行の現行試作は[`walk-normal-v2`](../assets/concepts/spr01/walk-normal-v2/preview.gif)です。ユーザーの「跳ねない程度に動きを増やし、1px上下もよい」という方向に沿い、親の試作初期値で胴・顔を `[0,+1,0,+1]px` 下へ変位させ、皮状の手を胴に対して左右交互に±1px動かし、足元接地と葉の相対揺れを保ちます。4方向・各4コマ・24×36px・8fps、foot anchor (12,34)、二値alpha、目1×2px、左右非反転です。前版[`walk-normal-v1`](../assets/concepts/spr01/walk-normal-v1/preview.gif)は胴・顔・手を固定した初回試作の履歴として保持。静止画v2からの表示用コピーは[`assets/sprites/poc/player/`](../assets/sprites/poc/player/manifest.json)にあり、manifestの通常歩行出典はv2です。跳ね歩き素材[`walk-v1`](../assets/concepts/spr01/walk-v1/preview.gif)、採用済み静止画v2、16×24pxの分身用候補は保持しています。素材はnative pixel gridで作成し、imagegenは使用していません。

PoC内の[通常/跳ね比較GIF](../evidence/spr01/walk-compare/self/gpu-comparison.gif)と、v2で更新した通常歩行の自己GPU結果（7 PASS / 0 FAIL）は[`evidence/spr01/walk-normal-v2/self/`](../evidence/spr01/walk-normal-v2/self/results.json)にあります。ユーザー採用後、実装担当は通常歩行v2へ固定し、F6/右上ボタンと比較案内を除去しました。採用仕上げの実装担当自己GPU確認は4 PASS / 0 FAIL（[結果](../evidence/spr01/walk-adopt/self/results.json)）、独立差分/提供GPU画像確認は4 PASS / 0 FAIL / 2 NOT_RUN（[報告](../evidence/spr01/walk-adopt/independent/review.md)）。独立GPU再実行・広い回帰はありません。v2の独立素材/提示画像確認7 PASS / 0 FAIL / 3 NOT_RUNは素材採用前の[別レビュー](../evidence/spr01/walk-normal-v2/independent/review.md)。以前の5 PASS / 0 FAIL / 2 NOT_RUN素材確認と11 PASS / 0 FAIL / 5 NOT_RUN GPU統合集計はv1までを対象にした[過去の報告](../evidence/spr01/independent/walk-compare-review.md)。ユーザーは通常歩行v2を採用済みです。

## SPR-01 正面の種・水発射アニメ試作（2026-10-20）

ユーザー依頼に沿って、正面だけの比較用素材を[`fire-front-v1`](../assets/concepts/spr01/fire-front-v1/)に作成しました。[比較GIF](../assets/concepts/spr01/fire-front-v1/comparison.gif)、[正確な時刻を操作できるHTML](../assets/concepts/spr01/fire-front-v1/comparison.html)、[全コマ一覧](../assets/concepts/spr01/fire-front-v1/contact-sheet.png)、[manifest](../assets/concepts/spr01/fire-front-v1/manifest.json)、[制作記録](../assets/concepts/spr01/fire-front-v1/production-note.md)を参照。原寸PNGと文字グリッドも同フォルダーにあります。

主人公は24×36px・anchor (12,34)・元の8色二値alpha・非対称の双葉・縦2pxの両眼を維持し、idleは変更していません。種は4コマ・合計200ms・33ms発射、水は5コマ・合計250ms・50ms発射です。形成FXと飛翔弾は主人公素材から分離しています。GIFでは20ms刻みに近似表示されるため発射境界は40/60ms相当ですが、manifestの正確な33/50msは維持。HTMLの時刻区分も正確なms指定で、実際の画面更新はブラウザー周期に依存します。

試作の動き・コマ長・発射時刻はユーザーが今回の制作条件として了承済みです。一方、素材はゲーム未組込みで、ゲーム内実装を意味しません。比較用飛翔表現の弾道・速度・色細部と最終美術評価は未決定です。制作担当の検査記録は[自己検査JSON](../evidence/spr01/fire-front-v1/self/self-check.json)、[HTML検査JSON](../evidence/spr01/fire-front-v1/self/html-check.json)および[制作記録](../assets/concepts/spr01/fire-front-v1/production-note.md)を参照。独立確認は7 PASS / 0 FAIL / 3 NOT_RUN（[報告](../evidence/spr01/fire-front-v1/independent/review.md)）で、241個別照合、保全137件と最終凍結成果59件のhash一致を確認。連続再生/実速の印象とゲーム統合は未確認です。親は試作提示の限定技術受入を行いましたが、ユーザーによる最終美術評価は未了です。

### 正面発射アニメv2（2026-10-20、比較試作）

ユーザーの修正指示に沿い、種の発射反動を更新し、水の膨張を長めにした比較案を[`fire-front-v2`](../assets/concepts/spr01/fire-front-v2/)に制作。[比較GIF](../assets/concepts/spr01/fire-front-v2/comparison.gif)、[操作可能なHTML](../assets/concepts/spr01/fire-front-v2/comparison.html)、[全コマ一覧](../assets/concepts/spr01/fire-front-v2/contact-sheet.png)、[manifest](../assets/concepts/spr01/fire-front-v2/manifest.json)、[制作記録](../assets/concepts/spr01/fire-front-v2/production-note.md)。v1およびruntime/ゲーム素材は変更せず保持しています。

種は4コマ `[33,50,50,67]ms`・200ms・発射33msを維持。発射コマでは胴/顔/手を1px下げ、手の最外側1pxをさらに1px下げて合計2px、足は固定し、葉は相対形状を保って胴に追従します。水は膨張を見比べる親の試作初期値として6コマ `[40,60,50,60,80,110]ms`・400ms・発射150msを使用。形成は2×2→4×4→6×6px（不透明画素4→12→32）、胴/顔変位 `[0,0,-1,+1,+1,0]px`、足は接地し上へ伸びる姿勢では下胴を接続しています。水の時間・寸法等は最終採用仕様ではありません。

比較GIFは20ms刻み・2秒ループで、上段6倍実速、下段1/4速を2倍表示。発射位置はGIF上で種40ms/水160msへ近似されますが、manifest/HTMLの正確な33/150msは維持。制作担当の自己確認とhashは[自己検査記録](../evidence/spr01/fire-front-v2/self/self-check.json)、[HTML検査](../evidence/spr01/fire-front-v2/self/html-check.json)、[hash記録](../evidence/spr01/fire-front-v2/self/target-hashes.json)を参照。独立確認は7 PASS / 0 FAIL / 3 NOT_RUN（[報告](../evidence/spr01/fire-front-v2/independent/review.md)）で、275個別照合、保全138件および凍結成果63件のhash一致を確認。連続再生・実速の印象・ゲーム統合・美術採用は未確認。親は比較試作として限定受入。ゲーム内の水範囲は後日検討です。

### 正面発射アニメv3（2026-10-20、比較試作）

ユーザーの速度と表情の方向を受けて、比較試作[`fire-front-v3`](../assets/concepts/spr01/fire-front-v3/)を制作・凍結しました。[比較GIF](../assets/concepts/spr01/fire-front-v3/comparison.gif)、[HTML](../assets/concepts/spr01/fire-front-v3/comparison.html)、[全コマ一覧](../assets/concepts/spr01/fire-front-v3/contact-sheet.png)、[manifest](../assets/concepts/spr01/fire-front-v3/manifest.json)、[制作メモ](../assets/concepts/spr01/fire-front-v3/production-note.md)。キャラクター、形成FX、飛翔弾は別素材。飛翔PNG/速度はv2を保ち、今回の半速化はキャラクター動作時間に適用しています。v1/v2とゲーム/runtime素材は保持。

種はv2の姿勢・体/手先/非対称葉の動きを保ち、目の閉じ/開きと口のすぼめ/開きを加えて `[66,100,100,134]ms`・計400ms・発射66ms（v2の厳密な2倍）にしました。水は比較用の親初期値として7コマ `[80,100,100,120,100,120,180]ms`・計800ms・発射400ms。形成水玉を2→4→6pxへ膨張、6px大玉を120ms保持。胴の上下変位は `[0,0,-1,0,1,1,0]px`、足は固定です。水の時間・表情・姿勢は最終採用ではありません。明示された表情変更のため、閉眼コマのみ縦2px開眼形状の例外とし、通常開眼/idleは維持。

比較GIFは20ms刻み・4000msループ。上段6倍、下段4倍スロー。GIF上のreleaseは種80ms/水400msへ近似されますが、manifest/HTMLの正確な66/400msを維持。自己確認の記録は[素材検査](../evidence/spr01/fire-front-v3/self/self-check.json)、[HTML検査](../evidence/spr01/fire-front-v3/self/html-check.json)、凍結hash一覧は[対象hash](../evidence/spr01/fire-front-v3/self/target-hashes.json)。独立確認は7 PASS / 0 FAIL / 3 NOT_RUN（[報告](../evidence/spr01/fire-front-v3/independent/review.md)）で、355個別照合、旧201件・凍結67件hash一致。親は比較試作として限定受入。実速の印象、ブラウザー連続再生、ゲーム統合、最終美術採用は未確認。ゲームの水範囲等は後日検討し、今回変更していません。

### 正面発射v3の試遊用ゲーム仮組込み（2026-10-20、4方向版へ更新前）

ユーザー希望により正面v3の発射表示を全照準方向へ仮接続。通常idle/歩行は採用済みの4方向素材を継続し、種/水を発射中だけ正面キャラを使います。runtimeのsource copyは[`assets/sprites/poc/player/fire-front-v3/`](../assets/sprites/poc/player/fire-front-v3/)。元の発射素材と独立した形成FX/飛翔弾を表示し、頭の葉の間から出る構成です。自己logic/GPU表示確認、GPU位相画像、hash確認は[fire-integration証拠](../evidence/spr01/fire-integration/self/)に保存。実装メモは[implementation-note.md](../evidence/spr01/fire-integration/self/implementation-note.md)、68ファイルの[対象hash](../evidence/spr01/fire-integration/self/target-hashes.json)、保全128件の[確認](../evidence/spr01/fire-integration/self/preserved-check.json)。独立レビューはR1 23 PASS / 2 FAIL、修正対象外の試験期待値誤りを直したR2は2 PASS / 0 FAIL（[報告](../evidence/spr01/fire-integration/independent/review.md)、[追試](../evidence/spr01/fire-integration/independent/selection-followup.json)）。製品修正なく未解決FAILなし。初回失敗は栽培種が発射時に袋の種を消費するという試験側期待の誤りで、現行は発射時予約・着地成功時消費です。この試遊用仮組込みは、水の範囲・速度・消費額・操作感・最終美術採用の確定ではありません。

### 発射4方向v1（2026-10-20、試遊用仮組込み）

ユーザーの「種は通常の目、水は現状のまま、残りの方向も制作」の判断を受け、[比較素材](../assets/concepts/spr01/fire-directions-v1/)を制作し、[runtimeコピー](../assets/sprites/poc/player/fire-directions-v1/)へ収録しました。主人公24×36px、anchor(12,34)、down/left/right/up。種は96×144pxの4コマ×4方向、水は168×144pxの7コマ×4方向です。左右は独立作画で反転せず、上は顔なし。種は全コマ通常眼。水の正面キャラクター/形成FXと飛翔弾はv3とbyte一致です。発射タイミングは種66ms/計400ms、水400ms/計800ms。出口socketは左(11,14)、他方向(12,14)で、表示位置に適用します。

制作自己確認では44キャラクターコマと44形成FXコマの寸法/パレット/alpha/顔/足、正面水のbyte一致、正面種の6画素の目だけの変更、左右非反転を確認。保全204件は一致しています（[自己検査](../evidence/spr01/fire-directions/asset-self/self-check.json)、[保全](../evidence/spr01/fire-directions/asset-self/preserved-check.json)、[hash](../evidence/spr01/fire-directions/asset-self/target-hashes.json)）。比較用の[HTML](../assets/concepts/spr01/fire-directions-v1/comparison.html)、[GIF](../assets/concepts/spr01/fire-directions-v1/comparison.gif)、[contact sheet](../assets/concepts/spr01/fire-directions-v1/contact-sheet.png)、[制作メモ](../assets/concepts/spr01/fire-directions-v1/production-note.md)を保持。自己GPU確認は26 PASS。独立確認は集約12 PASS / 0 FAIL / 4 NOT_RUN（[レビュー](../evidence/spr01/fire-directions/independent/review.md)）。凍結source203/203、runtime/code206/206、旧保全204/204、runtime copy99件一致を確認しました。親は独立レビュー・実差分・素材contact sheet・自己および独立GPU画像を確認し、今回の制作/組込みを限定技術受入しました。新方向の美術と実速操作感はユーザー判断です。
