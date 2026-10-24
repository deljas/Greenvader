# POC3-REFLECTION 比較準備

- 対象読取版: `4d4da323affcd35f4a2b6a6acdfa60175a347dd4`。PRICINGのcore3差分とCONTENTの新規群を保持。
- 所有: `tests/poc3/reflection/` と本証拠領域のみ。ゲーム変更、Godot起動/import、共有資料・作業票・Gitの変更は行っていない。
- 現状の共通waterはdivisor=2、反射320×180。nearest、AA/TAA無効、共有world、cull 1|64、地面/水と影カードは反射対象外。shaderのUV歪曲はなく、world→mirror camera投影。

## 用意した試験

`self_compare.gd`は、既存Water、Actor、EntitySprite/Catalogを固定の広い合成水際に置く。640×360本画面のままdivisor 2→1のみを比較する。主人公、仮boar、成熟clover/carrotを使用し、静止・歩行4コマ・左右転向の同じ7場面を各1回取得。植物は固定し、主人公/boarだけ移動・転向する。boarは既存1方向素材の左右反転であり、完成4方向アートの確認ではない。本画面と反射textureの両方をPNGに残す。ゲーム時計/AIは進めない。

各設定で短い12フレームの1区間のみ、`force_draw(false)`同期呼出にかかったCPU待ち時間の中央値・範囲と全体描画call/primitiveを採る。**GPU専用時間でも通常全マップ性能でもない**。画素数4倍から時間4倍とは推測せず、実測後に重大な悪化を親へ報告する。

最後に実際のSession/Worldを作り、現在マップで合法な水際を検索して通常world_view接続を1枚取得する。`self_run.ps1 -ExpectFullResolution`なら通常側のdivisor=1と640×360も確認する。比較fixtureはゲーム接続の代用にしない。

runnerは隔離APPDATA/LOCALAPPDATA、所有overrideのCreateNew、起動前からno_focus/minimized、開始/終了の状態確認、UPDATE_ALWAYSとforce_draw(false)を用いる。OS入力・前面化・カーソル移動・ウィンドウ復元を行わない。他者overrideは上書きせず、finallyでは作成した内容と一致するoverrideだけ除去する。

## 実施順と停止条件

1. 親のゲーム編集・Godot/import予約通知を待つ（現在実行禁止）。
2. 親が確認したPoC3限定設定overrideだけを実装候補にする。旧版共通設定は保全。
3. 比較試験1回を実行し、parse/fixture不備は元ログを保持して該当箇所だけ修正。全条件総当たりはしない。
4. 画像で粗さ/形/足位置/歩行と転向を確認。divisor1でも形状問題が残った証拠があれば、その時点で投影/向き/接地点の原因と最小案を親へ戻す。カード複製や投影補正は先行しない。
5. 対象版/hash、画像、限定負荷値、PASS/FAIL/NOT_RUNを報告して凍結。独立検証・受入は親が管理。

現時点は**準備のみ、全描画条件NOT_RUN**。ゲーム修正・比較実行・改善合格を示さない。水色/波/素材/美術磨き込み、物理入力、全照明、全角度、通常全マップGPU計測は対象外。
