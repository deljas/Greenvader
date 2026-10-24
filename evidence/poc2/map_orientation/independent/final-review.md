# POC2-07 境界修正版の独立追試

対象: HEAD `151a53f20255489ef08481e2a353258cd8ac559c` + 最新freeze-manifest.jsonの16 source。
map_ui.gd SHA256 `C55C323463F872F36C1956278872CBB0D1A163E55617668681319C73FF5074A6`。
Windows / Godot 4.7.2 stable / Vulkan Forward+ / NVIDIA GeForce RTX 5070 Ti。

**修正影響の限定追試: 5 PASS / 0 FAIL。初回F1は解消。**

|条件|結果|実測|
|---|---|---|
|最終セルの可視アイコンを選択|PASS|logic=(894,894)、描画中心=(320,232)、逆変換=(896,896)のままでもselected_id=987654。丸めたアイコンのhitを優先。|
|遠い世界外の余白は移動先にしない|PASS|map_rect左上寄りの余白クリックでhome不変、選択解除。|
|通常のアイコン選択・操作ボタン|PASS|4倍で通常helperを選択でき、撤去/種補給ボタンを表示。|
|通常の移動指示|PASS|通行可能・ボタン外fixtureを確認し、指定セル174,172の中心home=(698,690)へ更新。|
|popup入力独占|PASS|補給popup表示中の余白クリックでもhomeと選択を維持。|
|対象版・第一弾保全|PASS|追試前後16/16 sourceが最新freeze一致。第一弾91/91 hash一致。|
|前回の投影/地形/zoom/移動mini等|NOT_RUN（再走なし）|初回18有効PASSのうち今回の分岐修正と無関係な条件は維持。初回報告・ログを上書きしない。|
|物理入力、書き出し後実行、広い回帰、長時間性能、最終体験/美術|NOT_RUN|初回と同じ境界。|

実変更はhandle_clickの世界内判定とアイコンhit判定の順序のみであることをsourceで確認した。独立testはゲーム実装を変更していない。既存PASS全体は再走せず、corner.gdだけ1回実行した。入力はroot.unfocusable=trueとInput.parse_input_eventのみ、通常saveを使わず試験専用save_dirを指定。

final-last-cell-selected.pngを目視し、世界端のアイコンへ選択表示と正立した操作ボタンが出ていることを確認。数値結果はfinal-results.json、ログはfinal-gpu.log、対象照合はfinal-pre-run-hashes.json/final-hash-results.json。独立Godotはexit0で終了。全プロセス確認では通常入口由来の既存PID4776が1件残っていた（18:14:25起動、Godot_v4.7.2-stable_win64.exe --path C:\\godot\\greenvader\\launchers\\.. res://scenes/poc2.tscn）。独立試験の所有物ではないので終了しない。件数をfinal-processes.jsonに記録し、親へ報告した。独立編集と実行を停止し、親へ返却する。最終受入判断は親が行う。
