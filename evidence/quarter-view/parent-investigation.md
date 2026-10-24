# TECH-QV-01 親の現状調査・設計判断

2026-10-15。対象HEAD `99013702eaf36db72a64d60d284680fb834f13c5` と開始時未コミット成果（baseline-existing.json/patch）。技術確認用の選択であり、完成アートや通常ゲーム統合の承認ではない。

## 調査結果

- `scripts/world/world_state.gd`: 整数マスを配列で管理、表示と独立。緑化対象・成長段階・占有・地域状態を保持する。
- `scripts/world/region_view.gd`: 1セル4×4画素、64×64セルを256×256画像へ集約。現在の表示は論理座標と画面上のワールド座標が同じ。単にこの画像を変形すると芽や成熟縁の画素も変形するため、表示アダプターが必要。
- `scripts/player.gd`: 連続座標simulation_position、画面方向Input.get_vectorと96px/s、描画positionだけround。16×16仮花を足元から(-8,-14)に配置。
- `scripts/play/walker.gd`: 論理座標の足元AABB、地形通行属性に対して軸別解決、境界で止めて滑走。物理位置は整数へ丸めない。
- `scripts/main.gd`: actorsのy_sort_enabled、Camera2Dのsmoothingなし、整数表示位置へ追従。地面・影と上物の層は分離されている。
- `scripts/landscape_prop.gd`: 装飾物の中心足元Yとスプライト矩形で背後判定しalpha .42。長い斜め壁の側面にはそのまま一般化しない。
- `project.godot`: 通常ゲームは640×360、1280×720初期ウィンドウ、viewport stretch/integer、Forward+、transform pixel snap。今回は変更しない。
- `scripts/main.gd` の照準・発射や `scripts/play/play_driver.gd` のシミュレーションは従来座標を想定。今回の専用シーンで戦闘等を移植しない。

## 最小方式の選択

2D論理平面(u,v)を維持し、表示のみP(u,v)=(u-v,(u+v)/2)。逆はu=x/2+y、v=y-x/2。これは2:1 dimetricの検証用選択で、参考画像から厳密なカメラ角を復元したものではない。4×4論理セルは外接8×4画素の菱形になる。論理セル、まとまった地面素材、建物画像を別の単位として扱う。

画面方向入力を正規化→逆変換して連続座標を移動→既存Walkerで衝突→Pで表示、表示とカメラを整数画素にする。画面上等速と論理距離等速は同時には満たせない。この試験は前者を優先し、戦闘射程・移動AI・植物距離へは未適用。

建物の衝突footprintと見える基底を同一データから作る。単一中心Yを避け、画面列ごとの前端足元深度に分割。上物への遮蔽対策と衝突する地面基底は区別する。最終素材の屋根・壁・植生・開口部の分割条件は実装と検証結果から記録する。

## 参照した公式資料

- [CanvasItem Y-sort / nearest](https://docs.godotengine.org/en/stable/classes/class_canvasitem.html): Y-sortは子のY順序、texture filterはCanvasItemで指定。
- [Window](https://docs.godotengine.org/en/stable/classes/class_window.html): content_scale_size/mode、unfocusable。
- [複数解像度](https://docs.godotengine.org/en/stable/tutorials/rendering/multiple_resolutions.html): viewport基準と整数拡大。
- [CLI](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html): 実行引数。実装担当はローカル4.7.2の--helpとも照合する。

GPUフレーム取得とnative表示確認は区別する。CPUで原画を拡大しただけの画像を1920×1080実表示の検証とは扱わない。OS入力送信・前面化なし。確認できない物理入力経路はNOT_RUN。
