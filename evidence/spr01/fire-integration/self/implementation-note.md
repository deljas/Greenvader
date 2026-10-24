# SPR-01 正面発射v3 ゲーム内仮組込み: 自己確認

対象: 共有HEAD `151a53f20255489ef08481e2a353258cd8ac559c` と既存未コミット差分。`target-hashes.json` に今回の凍結68ファイル、`integration-change.patch` に親beforeコピーからの4script差分を保存。原画/採用済みPNG/設定など親指定保全128件はすべてhash一致（`preserved-check.json`）。docs/票/原画concept/他設定は未編集。

## 実装

- 新規 `scripts/poc/poc_fire_action.gd`: 原画manifestの正確なmsを読み、種400ms/66ms射出、水800ms/400ms射出を実時間のpausable action clockで管理する。入力直後pose0。発射前の追加入力はbusy、時刻を戻さない。射出後recoveryは新actionで中断可能。照準点と選択plant keyを開始時に固定する。
- `poc_session.gd`: can_fireへ既存の資源/上限/停止/戦闘不能の条件を共通化。既存fire即時APIは互換を保ち、任意plant_keyを追加。実射出時に再判定し、成功時だけ既存論理launchと費用を実行。shot_idを表示へ返す。論理origin/range/speed/collision/着弾の水範囲やdamageは変更していない。
- `poc_main.gd`: 通常クリックがaction開始へ入り、release時にsession.fireと音を1度だけ呼ぶ。原点はその時点のプレイヤー位置。移動は継続、見た目だけ一時発射poseが優先。pause/menu/viewpointは時計停止。death signal、成功ロードによるsession交換、newgameでcancel。未発射actionは保存データに含めない。releaseの再判定失敗はidle/walkへ戻し、費用0/実弾0/発射音なし。
- `poc_actor.gd`: 発射中だけ全方向へ正面v3を共用し、終了時に元の4方向idle/walkへ復帰。24×36/anchor(12,34)、nearest/1texel=1内部px、同characterを影板へ同期。形成FXは別24×36カードで原画の各コマを表示する（水のrelease後は透明、種releaseの小粒は保持）。重なり回避のカメラ法線方向0.01texel相当のずらしは投影座標に影響しない。既存自己受影除外lightを保全。
- `poc_play_view.gd`: 既存logical shot idと対応する表示側辞書に発射高さ20pxを保持。種/水は原寸8×8 PNGカードへ差替え、葉間から進行率に応じ地面へ下がる見た目のみ追加。論理shot辞書に描画項目を追加しない。cultivated弾は既存mesh。現フレームのsnap済みcameraで表示を同期する。
- runtime fire-front-v3は原画PNG/sheets/manifest/制作メモのバイトコピー。lossless、mipmapなし、3D自動圧縮なし、alpha-border加工なし。既存idle/walk/hopを保全。通常起動は変更前と同じ `launchers/run_poc.bat`。

## 検証

- Godot 4.7.2、Vulkan Forward+、RTX 5070 Ti。GodotはHiddenで起動、GPU試験はroot.unfocusable=true。OS入力/前面化/カーソル操作なし。右/左クリックだけInput.parse_input_eventで注入した。
- `tests/spr01_fire_logic.gd` をheadlessで1回: **16 PASS / 0 FAIL**。65→66ms、399→400ms、800ms復帰、event一度、busy/回復割込、種/照準/発射時原点snapshot、pause/view suspension、cultivated選択snapshot、資源ゼロ/上限の開始拒否とrelease再判定、death、既存即時API。`logic-results.json` / `logic.log`。
- `tests/spr01_fire_gpu.gd` を実GPUで1回: **11 PASS / 0 FAIL**。右クリックpose0、形成の成長/足元・影同期、400msに形成水玉消失とnative8×8飛翔、音呼出1回、種の弾き粒と移動継続、idle/walk復帰、4照準方向の正面共用、実menu/viewpoint停止、成功load/newgame/deathで未射出破棄。`gpu-results.json` / `gpu.log`。
- release初期の投影socketと飛翔中心はともに(320,180)、足元は(320,200)。論理originは既存プレイヤー位置(354,346)。描画高さが論理originを動かしていないことを確認。
- 原画画素そのものの大きな再試験は既存v3検証を利用。今回copyと保全hash、GPU格子/足元の接続を確認した。
- `water_000/080/180/280/399/400/500/620/800.png`、`seed_000/066/166/266/400.png` は実GPU640×360。`fire-game-contact6x.png` と `fire-game-crop6x.gif` は同じ画像の周辺をnearest6倍表示した比較。実マウス録画ではなく、注入入力後にゲームtickを各時刻へ進めた表示。GIF時間は10ms単位へ近似するがcontroller/manifestは66/400msを維持。
- 自己目視: 葉間で小→大に育つ水玉、閉眼から押出し、8px玉の分離/飛翔、通常姿勢への復帰が読める。キャラの輪郭や格子をぼかさず表示できている。

## 限界と終了

初回importとゲーム起動で既存sandbox user:// / editor設定 / shader-cache書込み警告が出る。PNG importとlogic/GPUはいずれもExit0で完了、script parse/runtime errorなし。saveは予約内self/save-sandboxへ隔離し試験ファイルのみ削除。通常user://物理経路は未確認。

NOT_RUN: 物理マウス/キーボードからOSを経る経路、美術の最終採用/生再生の操作感、性能/全角度/全天候、広い全回帰。actionの66/400msはゲーム更新で到達判定し、実表示は次の描画フレームへ反映される。フレーム未満の物理表示時刻を保証するものではない。

コード凍結、Godot実行中なし。実行/import資源は親経由で独立検証へ移譲できる。コミット/再委任/新しい方向絵制作なし。
