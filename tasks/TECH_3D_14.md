# TECH-3D-14 旧ツタと納品ツタのID・成長比較ツール

## 管理欄
- ID: TECH-3D-14
- 状態: 完了
- 担当ツール: codex
- 担当セッション: なし（完了）
- 更新日: 2026-10-18
- 予約中の編集範囲: なし（完了に伴い解除）
- 予約中の共有資源: なし（Godot残プロセスなし、GPU返却済み）
- 最終担当: codex-20261018-vine-compare

## 目的・対象
- C:/godot/greenvader、HEAD99013702+既存多数の未commit試作、共有ツリー。
- 左に既存plant_parts.gd/growth_patch.gdを使う旧ツタ、右に C:/godot/greenvader_asset_deliveries/assets/vines の納品GLBを並べる。ID変更で別の納品ツタを選択、成長0〜100%を同期操作・再生できる独立比較ツール。
- 元納品と既存ゲームは読取りのみ。現在63ID、再読込で追加も拾う。原則GLTFDocumentによる外部GLBのruntime読込で、元フォルダへimportファイルを作らない。パス入力欄/読込エラー表示を備える。
- 納品metadataは根/親子/接続点などを含むが、統一された完成済み成長アニメではない。比較ツール側で組み立てる成長は「推定成長」と明示し、ゲーム側の実成長接続と混同しない。

## 仕様・合格条件
1. 旧ツタは既存コードの実形状/頂点色/枝成長を再使用。小マップ相当の疎密を初期値とし、旧lab密度へ切替可能なら付ける。新たな似た形で代用しない。
2. 納品IDの一覧/前後移動/数値ID入力から63IDを選べる。初期007。追加データの再読込。失敗IDでもアプリを落とさず理由を表示。
3. 同一カメラ仰角30/方位45・照明・元scaleで並べる。640x360 nearest整数倍。共通ズーム、太陽方位/仰角、受け面表示切替。床/壁用の違いを表示し、床部品を強制直立させない。
4. 同期成長slider0〜100、0/25/50/75/100プリセット、再生/停止・先頭へ戻る。停止中不変、ID変更後も選択成長率を維持。0%で植物なし、100%で納品元形状/材質を保持。根元を移動する全体拡大や全素材一律の下から上Yワイプは避ける。
5. 納品は利用できるpath/branches/root/layer情報から根→親幹→枝→葉を示す。データ不足は明示した簡易推定を使い、推定を正式アニメと呼ばない。葉単体/吊り/横走りも適切なroot基準。実装方式は実装者が資料から選択し、難所は親へ相談。
6. 自己確認は全ID読込の短いスモーク1回、代表007/032/047/060/葉単体の成長端点/中間、代表GPU、入力経路を最小限。独立は実装と証拠の確認中心で、全角度・長時間の総当たりなし。

## 分担・制約
- 実装Sol: scripts/vine_compare/、scene、専用bat、launchers/README、tests/vine_compare/self*、evidence/vine-compare/self/。全実装と自己確認をまとめて担当。
- 独立Sol: tests/vine_compare/independent* と evidence/vine-compare/independent/のみ。実装は変更せず失敗を返す。
- Luna: 承認後docs/VINE_COMPARE.md、STATUS/VALIDATION追記。親が作業票と索引を管理。
- 子からの再委任禁止。他者変更の取消・commit・branch変更なし。元納品と既存vegetation/greening/showcaseコードは編集禁止（変更必要なら親へ）。OS入力・前面化・カーソル操作禁止。GPU撮影unfocusable、入力検証はGodot内注入のみ。
- 資料: AGENTS、tasks/README、docs/02_TECH_AND_ART、TECH_3D_13票、旧plant_parts/growth_patch/building_defs、showcase.gdとself_capture、納品metadata。

## 証拠・終了
- source hash/元データ読取り記録、self報告とGPU画像、独立報告を親確認。通常ゲーム/既存素材保全。実装者終了後にGPU権を渡す。
- 成長表示は見た目比較。内部緑化/保存/ゲーム接続/ユーザーの美術評価はNOT_RUN。実装・独立検証・文書が揃い、専用batと操作方法を提示して終了。

## 完了記録（2026-10-18）
- 親は実コード、007完成/低い太陽と060中間GPU、自己・独立報告を確認し、専用比較ツールの限定範囲を受け入れた。
- 自己40 PASS / 0 FAIL / 4 NOT_RUN。初回63行smokeの007統計は直前006を誤記録したため除外。有効62IDと初期/代表007の800三角形で63ID読込を補完確認。将来用testは常時ID選択へ修正済み、修正後の全再走はせず元証拠を保存。
- 独立7 PASS / 0 FAIL / 4 NOT_RUN。再凍結7ソース、既存7、元納品126のhash一致。代表5件の完成三角形数は元GLBと一致、GPU7枚nearest3一致。ゲーム実装とGPU証拠はtest修正前後で不変。
- 証拠: [自己報告](../evidence/vine-compare/self/report.md)、[独立報告](../evidence/vine-compare/independent/report.md)。操作: [比較ガイド](../docs/VINE_COMPARE.md)、[専用bat](../launchers/labs/run_vine_compare.bat)。
- 納品側は推定三角形表示であり正式成長アニメではない。物理入力、全角度/性能、通常ゲーム緑化・保存統合、美術の最終評価は未検証。通常ゲーム/P2保留/正式解像度方針を変更しない。
