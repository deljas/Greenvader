# SPR-01 四方向発射 runtime 実装・自己確認

対象版: 共有 HEAD `151a53f20255489ef08481e2a353258cd8ac559c` と既存未コミット差分。今回の実装は共有ツリーへ直接反映済み。`target-hashes.json` に凍結206件、`directions-change.patch` に親のbeforeコピーからの4script差分を保存。既存保全204件は全件一致（`preserved-check.json`）。コミット・ブランチ変更・再委任はしていない。

## 変更

- `poc_actor.gd`: 発射中のdown強制を除き、採用済みのマウス基準facingで4方向シートの行を選択する。character/formationは同じ行・コマ、影はcharacterと同じtexture/足元。左右反転は使わない。
- `poc_fire_action.gd`: 新manifestを使用し、方向別release socketの参照APIを追加。既存のms時計、入力時の照準/植物選択snapshot、資源再確認、停止/中断/費用の条件は維持。互換用socket_height_pxも維持。
- `poc_main.gd`: 現フレームのcameraとmouse facingを更新した後で、実発射した弾の表示出口を登録する。左socketは(11,14)、他は(12,14)、anchorは(12,34)。動作中もマウスへ向きを変え、弾の論理targetはクリック時のまま。方向ロックは追加していない。
- `poc_play_view.gd`: shot idごとの表示オフセットを横/高さの2軸へ拡張。横1px差も葉間から出し、飛翔進行率に応じてオフセットを0へ収束させる。logical shot origin/target/range/speed/collision/saveに描画データを入れない。栽培弾meshの処理は維持。
- `assets/sprites/poc/player/fire-directions-v1/`: 凍結した原画PNG98件＋manifestの99ファイルをbyteコピー（`source-copy.json`）。PNG importはlossless/mipmapなし/alpha-border加工なし/自動3D圧縮なし。親manifestへ新出典を追加し、旧frontは履歴として保持。
- session、既存idle/walk、ゲーム設定、射程/費用/水範囲などは変更していない。起動入口は既存 `launchers/run_poc.bat`。

## 検証と結果

- Godot 4.7.2、Vulkan Forward+、RTX 5070 Ti。Hidden起動とroot.unfocusableを使用。OS入力・前面化・カーソル操作はなし。
- import完了、Exit0。既存sandboxのuser://ログ/エディタ設定/シェーダキャッシュ警告は記録したが、script parse/runtime errorはない（`import*.log`, `logic*.log`, `gpu*.log`）。
- 専用logicを1回: **16 PASS / 0 FAIL**。種65→66ms、水399→400ms/800ms、発射一度、busyと戻り動作割込、照準/植物選択snapshotと発射時原点、pause/suspend、ゼロ資源・上限の開始拒否/発射時再確認、戦闘不能、旧session.fire即時API（`logic-results.json`）。前回専用試験を新証拠先へコピーし、今回対象で再実行した。
- 専用実GPUを1回: **26 PASS / 0 FAIL**。left/right/up × 種/水について開始向き、atlas/formation行・影/足元/格子、release出口とlogical origin、通常歩行復帰を確認。追加で溜め中のマウス方向変更と照準snapshot、menu停止を確認（`gpu-results.json`）。
- release時の投影出口と飛翔sprite中心は、左が(319,180)、右/上が(320,180)で一致。すべてlogical originは発射時のsession.positionと同じ。前面の保全/目の画素検証は素材担当の記録に委ね、このGPU試験では新3方向に絞った。
- `seed|water_left|right|up_000|hold|release|flight|walk.png` は実GPU640×360画像。`game-directions-contact4x.png` と `game-directions-phase4x.gif` はその周囲64pxをnearest4倍にした位相比較。GIFは各位相を比較するための一定時間表示で、連続操作録画や実アニメ速度の再現ではない。
- 自己目視で左右の異なる葉姿勢、背面の顔なし、種の開眼、水の閉眼→発射、葉間の水玉と飛翔分離、通常歩行への復帰を確認した。

## 未検証・終了

NOT_RUN: 物理マウス/キーボードのOS経路、連続操作の手触りとユーザーによる最終美術評価、全照明/全天候/性能/書き出し、旧回帰一式。既存発射の保存/ロード/展望など全項目をこの変更で重複再試験していない。今回のclock/当該経路の変更はない。

実装・試験対象を凍結し、Godotプロセス停止を確認。Godot/import所有権は親へ返却する。共有STATUS/企画/票は編集していない。文書担当は本報告の確認済み事実を使い、新方向の最終美術承認はユーザーの判断として残すこと。
