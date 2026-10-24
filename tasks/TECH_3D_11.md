# TECH-3D-11 局所緑化による壁面植生成長と水面受影

## 管理欄
- ID: TECH-3D-11
- 状態: 完了
- 担当ツール: なし
- 担当セッション: なし
- 更新日: 2026-10-16
- 予約中の編集範囲: なし
- 予約中の共有資源: なし
- 最終担当: codex-20261016-local-wall-growth

## 目的・採用仕様
- ユーザーは直前の仕様案に同意。建物の足元の地面成長を局所的に読み、近くのツタと壁面コケを時間差で成長させる。今回の到達点は片側の緑化→その側の壁のツタ/コケだけ成長。屋根への接続は次段階。
- 建物全体やマップ全体の緑化率では制御しない。根元/パッチ近くの対象地面を読む。土/舗装は内部成長状態が同じなら同等に扱う。各部品の固定形状/配置と共通資源を使い回す。
- ツタは幹から枝へ接続順に伸び、コケは独立した大小パッチが広がる。地面成熟後にも育つ時間を残す。内部緑化率の対象/分母/進行には加算しない。周囲の緑を失ったら現状保持で成長停止。ゲーム内時間のみ、成長停止/終了中は進めず、太陽操作は成長に影響しない。
- 追加不具合: 水面上にキャラ等の投影影が落ちない。現水shaderがunshadedで受影しない。実光源のshadowを受けつつ反射像を保つ。反射と投影影は別物として確認する。

## 対象・資料・割当
- C:/godot/greenvader共有tree、HEAD99013702eaf36db72a64d60d284680fb834f13c5＋既存未commit成果。AGENTS/tasksREADME/TASK_TEMPLATE、既読docs/00〜04/STATUS/DECISIONS、TECH_3D_09〜10、greening_map/vegetation_labコードを参照。
- Sol実装: 上記製品編集範囲＋wall_growth_self*とevidence/wall-growth/self。別Sol独立: wall_growth_independent*とevidence/wall-growth/independentのみ。Luna: 承認後docs4件/tasks索引。親: 設計/票/受入。
- session/actor/ground_view/world/play/data/共通メッシュ・既存shader・building_defs/project/通常ゲームは保全。旧labのgrowth_patch/surface_layersを拡張する場合はデフォルトの既存lab挙動を保持。scene/新batは不要。新adapterは旧地面草を重複表示せず、屋根のツタ/コケ/新ひびは出さない。
- 他者差分を戻さず再委任/commit/branch変更禁止。OS入力送信/前面化/カーソル操作は禁止。GPUはHidden+unfocusable、内部入力/viewport取得のみ。ユーザーの起動中Godotは操作/終了しない。

## 実装方針・合格条件
1. A/B建物の各根元/壁コケパッチに、足元の基壇外側の近傍セルを対応付ける。建物/水/外周の非対象セルは成長入力にしない。角の近隣が両面へ作用することは可だが遠い壁や別棟へ一括伝播しない。近傍幅/距離は小マップのセル0.4mに合わせて調整可、範囲と理由を記録。
2. 局所の発芽以上の成長量を成長速度へ反映し、独立した視覚用進行値を蓄積する。仮値は成熟地面が揃った時ツタ90ゲーム秒・コケ120〜150ゲーム秒程度を目安（裁量）。既存SimClock.growth_ticked等で実経過時間に同期し、描画refreshや太陽操作では進まない。巨大deltaで成熟後状態を過去全期間へ遡及加算しない。branchは親到達後、開口/壁上端を守る。
3. shared素材・固定パターンを維持し、root単位/patch単位で制御。一方の進行操作が他建物や旧labのMaterialへ漏れない。初期0、局所発芽/成熟、時間遅延、停止/再開、緑消失停止/保持、同状態の土/舗装同等を短いチェックで確認。実session時計と新controllerが接続されて実プレイの成長で更新されることも確認。
4. 水の受影は現太陽の硬いshadow mapを利用。unshadedの代わりに陰影を扱う材質/独自light処理など最小方式で、反射の二重照明や全体真っ黒化を避ける。明るい部分へ影を焼き込まない。キャラ影が岸→水面へ続き、太陽変更で移動することをGPU確認。反射表示ON/OFFとcasterの影ON/OFFを分離して本物の影と証明、nearest640→3維持。
5. 自己確認は新機能中心にまとめたlogic/GPU各1回程度。短い実時計早送り、片側のみ/未緑化面比較、コケとツタの別進行、影付き水面/反射の代表画像。旧lab共通コード変更時は旧デフォルト生成/成長signatureを保存原本と限定比較1回。大規模回帰や長時間/全条件網羅は不要、修正時は影響のみ再確認。旧証拠/既存テストを上書きしない。
6. 原本保存→差分/hashで凍結→独立は主要コード・raw・実GPU中心の限定検証→親画像確認→Luna記録。物理入力/負荷/保存（現在小マップ非対応）/全マップ汎用性/美術最終評価はNOT_RUN。終了時全担当停止・予約解除。

## 引継ぎ
- 2026-10-16 親取得。競合中担当票なし。既存水shaderのunshadedを確認。既存ツタは建物一括progress、コケは共有uniform coverageのため局所制御の互換拡張が必要。
- 親承認済み調整値: 根元/コケ中心を基壇外側0.2mへ投影し、半径0.65m内の対象セル（未緑化も分母へ含む）を平均。発芽以上のgrowth、成熟は1を入力とする。0.5ゲーム秒のgrowth tickごとに入力を蓄積、入力1ならツタ90秒/コケ135秒。入力が小さい場合は速度のみを下げ、到達上限は制限しない。metadataを別配列として旧labのsignatureと既定挙動を保つ。
- 製品凍結・独立検証へ移行。自己logic17/GPU6 PASS、Godot PID27960 exit0・資源返却。親もcontroller/共通拡張/水shader/実clock接続、前面135秒画像と水ON/OFF画像を確認。前面画像は成熟地面を置いた限定fixture。実装者は最終manifest/差分/reportのみ保存、独立は製品と証拠の読み取りを開始しmanifest確定後にhash照合する。

## 確認結果・親受入
- [自己報告](../evidence/wall-growth/self/report.md): logic17/GPU6 PASS、未解消FAIL0。[差分](../evidence/wall-growth/self/implementation.patch)と[凍結manifest](../evidence/wall-growth/self/source-manifest.json)保存済み。manifest SHA256 `6e155b63a50a5410ad6c38fdde4dbaf7cf1812de53d2a60e914ec02dcdbdce07`、親もsource7件を照合し一致。
- [独立報告](../evidence/wall-growth/independent/report.md): 6 PASS / 0 FAIL / 3 NOT_RUN。実差分・5製品コード・raw・実GPU7枚を確認。source7/保全117/証拠39件一致。独立Godot再実行はせず、提出GPUを別の池内領域で計測し投影影42px暗化、太陽変更82px差、nearest3一致。自己57pxと独立42pxは計測領域の違い。
- 親は実差分・主要コード・局所成長と水面影画像・凍結hash・独立証拠を確認し、A/B可視壁面と現太陽1灯の小マップに限定して技術受入。最終美術承認ではない。内部緑化率は不変。成長画像は成熟地面fixtureで自然拡張到達の証拠ではない。
- 水は42%下限の簡易受影で汎用物理水ではない。物理入力/保存/負荷/全マップ・全姿勢・全枝の網羅はNOT_RUN。屋根接続は後続範囲。
- 実装者/独立検証者は編集停止、自己GPU exit0、共有Godot資源返却。Lunaの確認済み文書更新後に親が予約解除する。次は既存launchers/labs/run_greening_map.batでユーザー確認。通常ゲーム統合/P2再開/追加美術磨き込みへ自動着手しない。
- Lunaの5文書更新と編集停止を確認。親は更新文書をレビューし、計測領域と暗化画素数の表現のみ明確化した。記録済み内容に意味の変更なし。全予約を解除して完了。
