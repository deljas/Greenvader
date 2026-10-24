# TECH-3D-10 壁際のスプライト欠け修正

## 管理欄
- ID: TECH-3D-10
- 状態: 完了
- 担当ツール: なし
- 担当セッション: なし
- 更新日: 2026-10-16
- 予約中の編集範囲: なし
- 予約中の共有資源: なし
- 最終担当: codex-20261016-sprite-wall

## 目的・対象・資料
- ユーザー画像で壁際の仮キャラが部分的に壁へ埋まる不具合。表示平面の向きと足元当たり判定を切り分け、同じ小マップで修正。水面反射はユーザー了承済み、地形別緑化表示も保持。
- C:/godot/greenvader共有tree、HEAD99013702eaf36db72a64d60d284680fb834f13c5＋既存未commit成果。AGENTS/tasksREADME/TASK_TEMPLATEと既読docs/00〜04/STATUS/DECISIONS、TECH_3D_08〜09、actor/session/map、Walker、building_defsを参照。

## 割当・禁止
- Sol実装は上記製品限定範囲とwall_clip_self*、evidence/wall-clip/self。別Sol独立はwall_clip_independent*とevidence/wall-clip/independent。Lunaは承認後docs3件/索引、親は本票と受入。
- 他者差分を戻さず、再委任・commit・branch変更禁止。world/play/Walker/data、共通sprite fixture/他lab、ground_view/water_surface、project設定、通常ゲーム、過去証拠/既存テストを変更しない。新bat不要。
- OS入力送信・前面化・カーソル移動は禁止。GodotはHidden+root.unfocusable=true、内部入力/viewport取得のみ。既に開いているユーザーGodotを操作・終了しない。

## 仮説・合格条件
1. 現状display_spriteがcamera.global_basisに全面追随し上部が地面奥へ傾くため、足元が壁外でも上半身が壁へ入る可能性。足元HALF=1論理px=0.1mとsprite幅、建物mesh/論理基壇範囲の関係も調査。修正前を保存し代表壁で再現画像/数値を取る。
2. 基本方針は表示板を地面へ直立させ、camera yaw向きへ向ける。必要なら縦投影の縮みを補正して現在の16×24px見た目を維持する。影板/反射との足元・frame/flip同期も保持。無条件のdepth無効や常に最前面表示は禁止、裏側の遮蔽を維持。
3. 直立化後も横幅/画素snapが壁へ食い込むなら、小マップ専用の足元判定を合理的寸法へ調整可。広大な立入禁止域で隠さず、寸法と根拠を報告。地形/緑化対象・成長/資源ルールは不変。
4. 実GPUでA棟の手前/右壁・角、B棟、建物裏の遮蔽を代表確認。全4frame/左右反転は数値または短い内部操作で確認し、壁を押し続けても貫通しない。水/外周衝突と斜め速度は既存短いlogic回帰1回（OUTだけ今回先へ変えたコピー、旧証拠上書き不可）。既存全GPU回帰は不要。
5. nearest3/画面上のsprite寸法/足元snap、影同期、反射を代表画像と内部値で確認。試験はほどほど、各条件1回、修正時は影響のみ。性能/物理入力/長時間はNOT_RUN。
6. 実差分・凍結hash・保全hash・短いreport→独立はソース/実画像/生データ中心に必要最小→親画像確認→Luna記録→全担当停止・予約解除。

## 引継ぎ
- 2026-10-16 親取得。競合担当票なし。以前の資料と差分状態を継承、共有treeを確認。水面反射と地形別緑化は今回変更しない。
- 2026-10-16 実装凍結。製品はactor.gdの直立yaw板/高さ補正と影の共通高さ、session.HALF=2.8論理px(0.28m)のみ。self logic13PASS、GPU18PASS/0FAIL（角の初回滑走位置は補足固定角確認で置換し履歴保存）。source-manifest SHA256=9d0d43d42f8fb154c158b0875a1e492527b192c5051d2f9c07568571f6fa4c37、保全114件一致。親はbefore/afterA右壁・B右壁・反射画像と実コードを確認。全実装/Godot停止済み、独立へ引継ぎ。
- 2026-10-16 独立5 PASS / 0 FAIL / 3 NOT_RUN。凍結7/保全114/証拠63件一致、代表壁/固定角/遮蔽と姿勢/投影/nearest/反射を実コード・提出GPU・rawで確認。親は[独立報告](../evidence/wall-clip/independent/report.md)、実差分・固定角を含む画像を確認し限定技術受入。Luna記録4文書を確認し、全frame/flipの内部値確認と代表GPU画素計測を区別。リンク/diffcheck通過、全担当停止・Godot終了、予約解除。

## 結果・限界・次の一手
- [既存の小マップ入口](../launchers/labs/run_greening_map.bat)を開き直して壁際を操作確認する。主因はカメラ正対板の傾きで、直立＋投影補正により16×24pxを保つ。横幅/snapに合わせ専用足元判定も調整。
- [修正前](../evidence/wall-clip/self/before_A_right_closeup_6x.png)と[修正後](../evidence/wall-clip/self/after_A_right_closeup_6x.png)、[自己報告](../evidence/wall-clip/self/report.md)。代表A/B右壁で72/168・70/168→168/168、固定角168/168、裏側0/168。全4frame×左右反転の内部姿勢/投影/同期も確認。
- 物理入力、全位置/角度、長時間/性能、全ゲーム回帰はNOT_RUN。小マップ専用修正、共通Walker/地形/成長/水面コードは不変。影は仮sprite輪郭の板による従来近似。新たな美術作り込みや通常ゲーム/P2再開は行わない。
