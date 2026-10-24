# POC3-INTEGRATION: 保存・機能統合・試遊準備

## 管理欄

- ID: POC3-INTEGRATION
- 状態: 完了
- 担当ツール: なし
- 担当セッション: なし
- 更新日: 2026-10-24
- 予約中の編集範囲: なし
- 予約中の共有資源: なし
- 最終担当: codex / codex-20261024-poc3-implementation

## 実施時に具体化する範囲

- 目的: [PoC3仕様](../docs/POC3_SPEC.md)と[実行計画](../docs/03_DEVELOPMENT_PLAN.md)の機能を一つの試遊可能なゲームへ統合し、保存・自己検証・操作案内を揃える。
- 対象版: C:/godot/greenvader共有ツリー。開始時に親がHEAD・未コミット差分・既存保存・予約を確認し、編集ファイルとGodot/import所有を確定する。別PoCのゲーム一式を複製しない。
- 依存: POC3-SOURCE、VISIBILITY、MAP-INFO、WATER-GROWTH、HELPERS、AREA-SEED、PLANT-UI、INPUT、WORLD-LAYOUT、ENEMY-TIERS、LOCUST、CROP-PRICING、SPRITE-VIEW、REFLECTION。保存方式の共通設計は関連機能の着手前に親が調整し、本票末尾まで先送りしない。
- 担当: Solが統合と自己検証、別Solによる最終独立検証はPOC3-VERIFY。Lunaが確認済みのガイド・証拠を記録。親が具体割当・コミット・凍結を管理。子再委任禁止。
- 編集候補: 各機能間の接続、保存復元、起動/ヘルプ、限定統合試験。案内はdocs/POC3_GUIDE.mdを実装後の実挙動に基づき作成。変更の必要が出た機能は担当を明示して修正し、共有ファイルを同時編集しない。
- 体験経路: 新規開始から開拓・種生産・化石解放・植物配置・複数前線・巣制圧・地域安定まで通して進める。224×224セルと中央開始を使用。
- おたすけの確認: アーミー防衛、ガトリンガー播種、スプリンクラー給水/補給の動作と待機・資源不足表示を確認。同一条件の有無比較を限定実施し、仕事量や被害差を証拠化。ゲーム内早送りを使い各条件1回、体験の最終評価を代行しない。
- 重要回帰: 種/水切れで進行不能にしない、生産敵報酬0、安定地域再侵攻なし、全敵排除後に孤立地を含む緑化対象100%へ入力なしで到達、終了中進行なし。
- 保存: PoC3は新規開始を基本とし旧セーブを保全する。旧進行の移行は対象外。給水状態、株の実支払額、化石解放/発見記憶、固定巣発見、資源、敵階級、おたすけ状態、お気に入りなど新旧の必要状態を保存復元する。旧版を誤って上書きしない保存先/版判定を設計する。
- 入力/描画: UIと戦闘の入力漏れ、Shift/長押し/解除を確認。通常画面・マップ・仮2D素材・水面反射を実GPUで代表確認し、640×360・nearest整数拡大・輪郭線なしを維持する。
- 合格条件: 主要機能と上記条件の自己確認証拠があり、独立検証可能な版を凍結する。主要FAIL/NOT_RUNは未完了として扱う。未確認の楽しさ/最終バランス/物理入力経路は明示して試遊へ渡す。
- 証拠: evidence/poc3/integration/に対象コミット/差分hash、条件、PASS/FAIL/NOT_RUN、代表GPU画像を記録。docs/VALIDATION.mdから参照。回帰一式は1回、変更後は影響分だけ再確認。
- 禁止: OS入力・カーソル移動・前面化、所有不明プロセス停止、旧保存削除、完成アート追加、未合意の機能追加、子のcommit/ブランチ切替/push。
- 自律判断: 明白な進行問題に対する仮値調整は理由と前後値を記録して親が判断。確定仕様変更や長時間の総当たり調整はしない。
- 終了条件: 親が差分・自己証拠を確認し、対象版と残項目をPOC3-VERIFYへ渡す。独立検証前にPoC3全体完了とはしない。

## 引き継ぎ

- 2026-10-24: 全体範囲と完了条件をユーザー承認。計画のみ、実装・検証・ガイド作成は未着手。
- 統合時の確認追加: SOURCE/SAVE-BASE以来、通常起動を終了するとObjectDB 37件・resource 20件の残存が報告されている。WATERのheadless起動でも同数（evidence/poc3/water_growth/self/startup.log）。poc2_session.close()は存在するがmainの終了処理は未接続に見えるため、終了・新規開始・読込置換の所有関係を確認する。原因未確定のまま今回機能の回帰と断定せず、統合で既存closeの適切な呼出しと正常終了を代表1回確認する。旧ログを削除して解決扱いにしない。

- 終了処理の追加読取: poc2_main.replace_sessionは旧session.close済み、Persistenceはbuild後失敗candidate.closeと成功時callback移譲/候補system切離しがある。通常mainには_exit_treeがなく、combat/plants→sessionとWorldState.tile_listenerの参照を終了時に解放していない可能性が高い。統合時に通常終了1回で原因を確認し、必要ならmain終了でcloseを呼ぶ限定修正を行う。現時点は読取仮説であり原因確定/修正済みとしない。

- WORLD到達性試験の留保: AStar斜め経路を半幅2のWalkerで各cell中心へ再生すると、北(115,104)→(115,103)と南(115,120)→(115,121)でx=461.9998（中心462より約0.0002pxずれ）が残り次軸へ進まない。self/routes_followup.json参照。実衝突を通した別の四近傍経路4本は到達PASSで配置の通行不能ではない。nav.moveはWalkerを使わず直接補間なのでAI停止は未確認。統合の代表手動相当移動で支障がある場合だけ境界精度を限定修正し、原FAILを消さない。

- 準備取得: dc2033b+LOCUST作業差分を読む。後続HELPERS/REFLECTIONの未接続仕様を前提に、限定統合試験・回帰一式1回の計画だけを準備する。既存機能試験は有効な証拠を再利用し、実行と既存ゲーム修正は全依存の凍結後に親が別途許可する。

- 準備完了: tests/poc3/integration/self_core.gd・self_run.ps1とevidence/poc3/integration/preparation.mdを作成し担当停止。PS構文のみPASS、Godot/import・GDScript・動作はNOT_RUN。100%条件のみ全敵排除/安定後に通常clock→growth/spread/far接続を保った120秒固定刻みを許可し、成長値/播種予算は変えない。短い体験経路は通常Session.advance_game。化石・複数前線・fire/skill攻略・helper複合保存・GPU・正常終了は依存凍結後に接続する。

- 統合開始: HELPERSは4550123で受入済み、REFLECTIONは独立画像/保護監査完了し実行権返却。反射world_view差分をindex固定。全依存のゲーム版を固定し、自己統合一式1回を許可。既知終了/Walker問題は実再現後に限定修正し原ログと影響追試を保持する。

- 自己完了/独立移譲: f8fd003+main終了close/Walker EPS5e-4の2差分。自己core14P1Fの移動原FAILを保持、北南/壁抜け/自由移動4P追試で解消。全38330/38330・島16/16を無入力2401game秒で確認。公開API通し10P、GPU12構造条件、西岸の実歩行反転時系列5撮影条件+親目視。原無効撮影2fixtureとnative exit取得留保を報告に保存。終了残存39/21→警告なし/最後native exit0。旧保存3不変、Godot0/overrideなし。実差分/生結果/画像を親確認、freeze_after.json版を最終独立へ。

- 最終技術受入: f8fd003+INTEGRATION freeze_after.jsonの2ゲーム差分を親が確認。最終独立8PASS/0FAIL/native exit0、18対象hash/旧save3不変、Godot0/overrideなし。機能別独立と統合生証拠を再利用して主要16条件に未解決FAIL/NOT_RUNなし。全38330/38330・孤立16/16自動緑化、公開API通し、保存・入力・正常終了、最終草mask/反射短時系列を限定確認。原失敗と追試は保持。evidence/poc3/independent/report.md参照。物理入力・楽しさ/最終バランス・全描画/他GPU性能・書出しは未評価のまま試遊へ引渡す。P6/追加機能へ進まず停止、pushはユーザー。
