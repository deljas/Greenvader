# TECH-3D-08 小マップ歩行・地面緑化・太陽方角

## 管理欄
- ID: TECH-3D-08
- 状態: 完了
- 担当ツール: なし
- 担当セッション: なし
- 更新日: 2026-10-16
- 予約中の編集範囲: なし
- 予約中の共有資源: なし
- 最終担当: codex-20261016-small-map

## 目的・対象・資料
- ユーザーが小マップで歩ける・実際の地面緑化状態が表示に反映される範囲へ進めることを承認。太陽光の方角操作を追加希望。植生バリエーションは十分と了承済み、追加美術作り込みはしない。
- C:/godot/greenvader共有tree、HEAD99013702eaf36db72a64d60d284680fb834f13c5＋既存未コミットART/TECH成果。AGENTS/tasksREADME/TASK_TEMPLATE、docs/00〜04/STATUS/DECISIONS、TECH_3D_07、scripts/world、scripts/play/Walker/Landing/PlayState、vegetation_lab、render_study_3dを参照。

## 割当と禁止
- 親が設計/票/最終受入。Sol実装は新規scripts/greening_map/、scene、bat、tests/greening_map/self*、evidence/greening-map/self/。別Sol独立はtests/greening_map/independent*とevidence/.../independent/。Lunaは上記docs/索引のみ。
- 既存world/play/data、player/main/project設定、vegetation/render study等過去成果はread-only。必要な変更は親へ返す。専用入口を追加する範囲で、通常ゲーム/P2再開や全3D移行は対象外。
- 共有treeで他者差分を戻さず再委任/commit/branch変更禁止。OS入力送信/前面化/カーソル操作禁止。GPUはHidden/unfocusable・Input.parse_input_event等内部注入とviewport取得のみ。所有外プロセスを終了しない。

## 設計と合格条件
1. 専用run_greening_map.batで小さな連続マップを開く。草地/舗装/既存建物を含める（2〜3棟、配置数は裁量）。固定orthogonal quarter camera、640×360 nearest整数拡大・硬影・輪郭なしを既存試作から継承。正式960基準/通常game設定は変更しない。UIに操作と試作であることが分かる短い説明。
2. WASD/矢印で画面方向に仮spriteが歩く。既存仮歩行spriteと影同期方式を再利用、主人公完成アートは作らない。論理移動は連続、表示だけsnap。既存WalkerとWorldStateを再利用し建物足元/水/外周へ侵入しない。地上物と遮蔽を含む実GPU確認。
3. 実WorldState・GrowthSim/SpreadSim（必要ならSimulationDriver/SimClock）を再利用する。各地面セルのstage/growthから共通grass mesh表示へ変換し、表示側がgreening countやstageを書き換えない。seed/sprout/matureの位置対応が読み取れる。全体率sliderだけで増やす疑似連携は不可。小さな初期成熟域から自然拡張、左クリック種/右クリック水で介入可能。
4. 操作は地面座標へ正しく変換しUI上で発火しない。有限種/水の消費/不足判定は既存PlayState+Landing等を再利用。射撃弾道/敵/本番資源循環は対象外、今回の手動操作は射程内地面への直接散布で可。試作用補給ボタンと進行倍率/一時停止は可、調整はlab独自インスタンスのみ。実入力・秒数・制限をUI/記録へ明記。照明角度は今回は見た目のみ、成長日照ルールを新規変更しない。
5. 太陽方位0〜360度をslider/数値で変更でき、影が追随。仰角も既存方式の操作を追加してよい。昼夜自動化/点光源は不要。キャラ影も同じ光に追随する。
6. 自己検証は短いlogic+GPUで一度ずつに集約。内部入力で歩行と衝突/斜め速度、種/水/不足・UI入力抑止・投影ピック、早送りでstageと草表示の連動/自然拡張・対象外保持、太陽2方位・代表nearest一致。論理率と見た目分離を確認。描画前後/移動/光方向PNGを最小限残す。重い全P2回帰や全方向性能等はNOT_RUN。問題修正後は影響のみ。
7. 凍結ソースhash/保全hashと短いreport→別Solによるコード+証拠+代表内部操作の限定独立確認→親の画像/差分確認→Luna記録。独立は自己同式コピーを避け、既存GPUが十分なら再描画不要。新規操作接続は必要な短い独立テストのみ。

## 終了・引継ぎ
- 建物へのツタ/苔の成長接続・保存/ロード・敵/戦闘・本番バランス・全地域100%の再実証は別段階。既存確定仕様を変更しない。
- 2026-10-16 親取得。競合中票/Godotなし。既存WorldState/GrowthSim/SpreadSim/Walker/Landing/PlayStateと3D描画を読み取り接続できると判断。
- 親承認の試作値: 48×40セル・1セル0.4m（19.2×16m）、A/Bの2棟＋水域＋初期成熟域。基壇の可視範囲と建物占有セルを合わせる。射程3mの直接散布、有限資源＋補給ボタン。時間は初期×4、×1/一時停止を操作、既存成長閾値は維持（乾燥成熟60ゲーム秒）。通常ゲームの値変更ではない。
- 2026-10-16 凍結。自己logic最終13 PASS、GPU初回継続5＋最終11の重複除外16 PASS。初回の厳しすぎる移動許容、テスト注入座標変換のFAILを保持し修正。製品マウス処理は変更なし。source-manifest SHA256=5a26c4bb1f73c28bcfeaffaa8890151b81c66bc3415511db0d8cb5c17e8b4f7e、保全103件一致。親は実コードと初期/成長後/太陽135/建物遮蔽GPU画像を確認。実装編集停止・Godot終了、別Solへ限定独立確認を依頼。
- 2026-10-16 独立6 PASS / 0 FAIL / 3 NOT_RUN。headless session1回7項目、rawとGPUの目視/代表nearest3を確認、凍結8件/保全103件/証拠39件一致。親は報告と主要コード/画像を確認し、本小マップの限定技術受入を決定。Lunaへ確認済み記録を依頼。
- 2026-10-16 Luna更新の5文書を親が確認。全子編集停止、Godot終了済み、担当予約解除。小マップ歩行・地面緑化・太陽方位の区切りとして完了。ユーザーの実操作/美術評価は未代行。

## 結果・証拠・次手
- 起動: [run_greening_map.bat](../launchers/labs/run_greening_map.bat)。WASD/矢印、左種/右水（3m、1押下1回）。試作補給、成長×1/×4/停止、太陽方位slider/数値。停止中も歩行/散布可能。仰角52°固定、照明は成長速度に影響しない。
- [自己報告](../evidence/greening-map/self/report.md)、[独立報告](../evidence/greening-map/independent/report.md)。初回FAILと修正理由は自己報告へ保存。親は初期/grown74/sun135/behind実GPU画像を確認。
- 既存地面判定/成長データと新3D表示を接続。地面対象1422、代表記録の緑化12→31→95、成熟12→12→49。表示密度と緑化判定を分離。
- 限界: 仮spriteはunshaded、影板は体厚のない近似。建物pickは保守的AABB。native/物理入力・独立GPU再走・性能・長時間・広範回帰・全地域100%・保存等はNOT_RUN。建物植生成長連動と本番資源循環は未実装。
- 次はユーザーが専用小マップで実操作/見た目を確認。通常ゲーム/P2再開、正式960基準変更、追加美術磨き込み、建物への成長連動へ自動着手しない。
