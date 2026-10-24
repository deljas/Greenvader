# POC2-07 独立検証

対象: HEAD `151a53f20255489ef08481e2a353258cd8ac559c` + 親指定freeze-manifest.jsonの16 source。
map_ui.gd SHA256 `769E387DCBDA2832CD396D2B359C8CA6AFA8294AADCF40EE74021D16BA9AC191`。
環境: Windows / Godot 4.7.2 stable / Vulkan Forward+ / NVIDIA GeForce RTX 5070 Ti。

**有効結果: 18 PASS / 1 FAIL。最終受入は親が判断する。**

## 条件別

|条件|結果|証拠・実測|
|---|---|---|
|実Camera3Dとの方向・比率一致|PASS|mini/full/移動miniを4方向比較。一様倍率のみで最大誤差0.000016px未満。実装式を期待値へ転記していない。|
|地形・逆変換・移動中整合|PASS|full132点、zoom132点、移動mini24点で期待セル色との不一致0。ピクセル中心でサンプル。正逆変換誤差0。|
|鮮明さ・正立UI・投影範囲|PASS|GPU640×360画像で菱形地形、円形mini、水平ゲージと正立ボタン、扁平な活動範囲を確認。nearest、内部640×360、1280×720窓の最終2倍transformを実測。|
|2/4倍カーソルアンカー・通常指示先|PASS|アンカー誤差各0px。通行可能かつボタン外のセル174,172へのエンジン入力でhome=(698,690)。|
|世界外の余白クリック|PASS|世界外クリックでhelper.home不変。|
|最終セルの可視アイコン選択|FAIL|下記 F1。丸めたアイコン中心が逆変換では世界外になり、選択を拒否。|
|未知情報・時間停止・popup独占|PASS|記憶地形があっても現在視界を消すと敵/巣/化石の有無による画像差0。地図中clock不変。popup中のクリック/zoomでhomeとzoom不変。|
|論理状態・対象保全|PASS|map操作中terrain/stage不変。開始前freeze16/16一致（pre-run-hashes.json）、第一弾91/91一致。FAIL返却・実装権移譲後のhashは修正再開済map_ui.gdだけ不一致15/16（hash-results.json）。保守版16件比の変更は許可されたmap_ui.gdのみ。修正版は別途再凍結が必要。|
|物理マウス/キーボード|NOT_RUN|OS入力、カーソル、前面化は操作しない。|
|書き出し後実行・広い回帰・長時間性能/楽しさ/最終美術|NOT_RUN|今回の限定マップ検証の範囲外。|
|1倍へ戻すwheelによる再fit・全端クリップ網羅|NOT_RUN|自己証拠とsourceは確認したが、独立試験で当該条件を実行していない。|

## F1: 最終セルの植物を選択できない

- 重大度: 中。見える植物への撤去・補給・移動指示の入口を失う。
- 期待: 有効な世界セル内の植物アイコンの中心をクリックすると選択される。世界外余白への移動指示は引き続き拒否する。
- 実際: helper.pos=(894,894)、zoom1のアイコン中心=(320,232)。クリック逆変換=(896,896)となり、selected_id=-1のまま。
- 最小再現: 全体マップを1倍で開く。検査用helperを最終セル223,223中心へ置く。描画後、そのアイコン中心へInput.parse_input_eventで左クリックする。正式な植物配置可否とは独立したUI境界fixture。
- 対象: scripts/poc2/ui/map_ui.gd の handle_click。_world_contains拒否を_icon_points選択より先に実行している。
- 証拠: affected-gpu.log、results.json の last_cell_icon_remains_selectable、last-cell-icon.png。
- ゲームコードは修正していない。親へ失敗と再現を返した。

## 実行履歴と限界

初回verify.gdでは11有効PASS。移動fixtureがボタンの実寸高さ31pxと重なり、さらにtyped Arrayへの空Array代入でharnessが停止した。初回のfixture/orderの2 FAILは製品結果へ加算しない。initial-gpu.logを保持した。

affected.gdはそのfixtureと未完了部分だけ実行し7 PASS / 1製品FAIL。既存PASS条件は再走していない。typed Arrayは独立テスト内のclear/assignへ修正。移動点は通行可能・ボタン外を事前検証した。OS操作は使用せず、root.unfocusable=trueとエンジン入力のみ。通常saveは使用せず、専用save_dirを指定。独立試験プロセスはexit1で終了。FAIL返却後、親が実装担当へ実行権を戻し、修正・Godot実行を開始したため、終了時点で全Godotなしとは主張しない。他担当の3プロセスには触らず、独立編集を停止した。

画像は full-revealed、selected-zoom4、last-cell-icon、mini-moved を独立目視。低解像度の段差はあるが地図に補間ぼけは見えない。GPU画像そのものは内部640×360で保存し、ネイティブ窓の物理画素撮影ではない。hash明細はhash-results.json。
