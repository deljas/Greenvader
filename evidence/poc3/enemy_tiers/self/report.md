# POC3-ENEMY-TIERS 実装・自己確認

- 対象版: HEAD `e7d86a5adedf3a221fe90b88be099a4b530bfb98`（WORLD親コミット）+ ENEMY-TIERSの差分。core/部品3ファイルと専用試験のSHA-256は`freeze.json`、既存coreの実差分は`actual_diff.patch`。新規未接続準備済みの`enemy_tiers.gd`は今回内容変更なしで接続し、同ファイルとhashが新規ソースの正本。
- 環境: Windows、Godot `4.7.2.stable.official.ed1daf0bf`、headless、Dummy audio。APPDATA/LOCALAPPDATAは本ディレクトリ下のignored `profile/`へ隔離。共有Godot/importは親から実行権を受けて実施。

## 変更ファイルと実装

- `scripts/poc2/simulation/combat.gd`: 巣生成時にfree_position補正後の実位置とsession.start_position()で固定tierを確定。規模基本HPへ倍率を適用。初期・追加配下とも親tierを継承し、通常/strongの基本HPへ倍率。母体/主人公が移動しても再計算しない。通常攻撃5（主人公/植物/helper）、boar突進12、mother接触10の加害に固定tier倍率を適用。初期敵6/15・巣30/80/200へ報酬倍率とfloor、後生産配下は0。
- `scripts/poc2/simulation/persistence.gd`: enemy/nestのtier欠落は旧作業PoC3の0として保持。数値型かつ厳密に0/1/2の整数値だけ受理しintへ正規化。種別/strong/巣規模から求めた固定tierのmax_hpとの一致を検証。現在位置では再判定しない。生産元nestが消えた生存配下も受理し、自身のtier/能力を検証。不正値はTiersのassertへ渡す前に原子的拒否。
- `scripts/poc2/simulation/enemy_tiers.gd`: 既存の未接続準備品をそのまま接続。距離18/32m、HP1/1.3/1.7、攻撃1/1.2/1.4、報酬1/1.5/2を集約。今回の準備・接続で部品本体の内容変更なし。
- `tests/poc3/enemy_tiers/`: `self_pure.gd`、`self_integration.gd`、`corrected_combat.gd`（位置補正結果を与えるfixture）、`self_run.ps1`。新規試験のGodot生成`.uid`も同範囲。

速度、予兆・回復時間、生産interval/cap、外見・UIは編集していない。WORLD/PRICINGと他者差分を保持し、sessionやshared docs/票/Git indexを子から変更していない。

## 実行した検証と結果

- import 1回: `import.log`、exit0、ERROR/WARNINGなし。共有追加素材の通常自動importも含むが、CONTENTソースは編集していない。
- pure 1回: `pure.log` / `pure_results.json`、**18 PASS / 0 FAIL**。18/32m直前と等値、ユークリッド距離、階級範囲、基本HP20/40/100/240、攻撃5/12/10、初期報酬6/15/30/80/200と後生産0。試験は手計算期待値を使用。
- 初回統合1回: `integration_initial.log` / `integration_initial_results.json`（原`integration.log` / `integration_results.json`も保持）、**20 PASS / 1 FAIL**。5巣の[tier,max_hp]は[0,40]/[1,52]/[1,130]/[1,130]/[2,408]。13初期配下の継承、補正後配置点の使用、移動mother/主人公後も外側配下HP34、strong中報酬22、mother遠報酬400、後生産0、実加害6/7/16.8/14、live母体保存固定、旧missing tier=0、不正tier/HP拒否がPASS。
- 初回FAILは親消失後の子を含む実JSON保存往復。JSONのtier=0.0がint候補配列[0,1,2]とmembership一致せず、validatorがinvalid_entity_enemiesで拒否した。拒否診断は`save_diagnostic_rejection.log` / `save_diagnostic_rejection_results.json`へ保持。数値型検査後にfloat候補[0.0,1.0,2.0]との厳密一致へ揃えて修正。小数や型を緩和していない。
- 保存1条件の限定追試: `save_followup.log` / `save_followup_results.json`、**1 PASS / 0 FAIL**。実JSON完全snapshot一致、消失親の子tier2/HP34保持。ログにfloat 0.0のint membership=false、正規化後trueを記録。
- validator影響限定追試: `validation_followup.log` / `validation_followup_results.json`、**6 PASS / 0 FAIL**。tier1.5/3/-1/文字列/boolとHP不整合を原子的拒否。
- 診断試験追加時、typed Arrayへ条件式のuntyped Arrayを代入する試験側runtime errorが1回発生（`save_diagnostic_harness_error.log`保持）。typed配列へのassignへ訂正し、自分の管理execセッションだけをstdin割込で終了してから限定追試。未知のプロセスは停止していない。このハーネスエラーをゲームPASSへ算入していない。
- 重複を除く最終有効結果は **39 PASS / 0 FAIL**（pure18 + 統合21）。各条件の最終証拠を`results.json`に記録。全回帰の再走なし。
- `git diff --check`: 対象core2ファイルで成功。初回成功後に変更したゲーム箇所はvalidatorの数値membershipだけで、その影響条件を上記限定追試。

## 証拠・未検証事項・残課題

- 凍結hash/環境/親WORLD等の保護対象hash/実保存hashは`freeze.json`。実ユーザー保存3件は`context.json`の開始前とSHA-256一致。旧PoC/PoC2保存のロード・移行・書込は行っていない。
- GPU再実行・実画面、物理入力、全回帰、全敵長期走行、難易度/楽しさはNOT_RUN。表示変更なしのため親指示どおりGPU再実行なし。速度/予兆/生産/外見に関する編集がないことは実diffで確認。
- 本票に未解決FAILなし。Godotプロセス一覧0、自分の実行セッション終了、override.cfgなし。OS入力・カーソル移動・前面化なし。コミット・stage・ブランチ切替・再委任なし。
- 文書担当へ渡す事実: 固定tier/能力/報酬/保存接続範囲、初回JSON型境界FAILと限定修正の履歴、最終39 PASS、NOT_RUN、旧保存3件保全。子から共有記録は更新せず、編集・Godot実行を停止して独立検証へ返却する。
- 子の自己結果はPoC3全体の受入合格ではない。親の独立証拠確認と限定受入が残る。
