# POC3-CROP-PRICING 実装・自己確認

- 対象版: 実行時の共有HEAD `2e5ad7ef579c4640857e63914d5ea1482512db9b` + PRICING core3ファイル差分。最終凍結時は親のSPRITEコミット`4d4da32`へ進んだが対象3ファイルhashは一致。対象SHA-256と実行時/凍結時HEADは`freeze.json`、PRICING実差分は`actual_diff.patch`。親からゲーム編集開始とGodot実行開始の通知を受けて順番に実施した。
- 環境: Windows、Godot `4.7.2.stable.official.ed1daf0bf`。logicはheadless/Dummy audio。GPUはVulkan 1.4.341 Forward+ / NVIDIA GeForce RTX 5070 Ti、640x360。APPDATA/LOCALAPPDATAは本ディレクトリ下のignored `profile/`へ隔離。

## 変更ファイル・内容

- `scripts/poc2/poc2_session.gd`: `current_cost(kind)`は`plant_stats(kind).count`（同種・hp>0、未成熟を含む）を利用し、cropだけ`ceil(base * 1.05^n)`。helperは従来固定額。int64へ表現できない値は親承認済みのINT64_MAX飽和で負額化を防ぐ。有効保存の残高上限1e9からは買えず、ゲーム仕様として価格上限を新設しない。各株の返還は実支払額の整数除算`cost/5`（正整数なのでfloor）にして高額時のfloat丸めを避ける。
- `scripts/poc2/simulation/plants.gd`: placeごとに現価格を再取得し、支払額をその株のcostに保持。`cost > seeds-ammo`の比較で加算overflowを避ける。失敗設置で残高・現存数は変わらない。死亡・撤去による既存の配列更新を通じて次価格が下がる。helperの未使用弾返還は維持。
- `scripts/poc2/simulation/persistence.gd`: cropは歴史的支払額の有限・正整数・int64表現を検証。現在nや基本額へ支払額を再構築しない。helperのcost==固定基本額は維持。旧作業PoC3の基本額はそのまま有効。
- `tests/poc3/crop_pricing/self_logic.gd`: 手計算期待値による価格・決済・返還・保存・不正値・範囲播種との勘定の限定確認。
- `tests/poc3/crop_pricing/self_gpu.gd`: HUDと一覧の次価格、撤去直後の更新、640画像、開始終了のno_focus/minimized条件を確認。
- `tests/poc3/crop_pricing/self_run.ps1`: 隔離profile、GPU開始前のCreateNewによる安全override、終了時に自分のoverrideだけ除去。Godotが生成した専用試験の`.gd.uid`も本試験に属する。

UIは既にcurrent_costを参照するため編集不要だった。共有docs・作業票・Git・他view/UIには子から変更していない。

## 実行した検証・結果・証拠

- import 1回: `import.log`、exit0、ERROR/WARNINGなし。共有ツリーに追加されていたCONTENT素材の自動importも通常のscanで行われたが、そのソースは編集していない。
- logic 1回: `logic.log` / `logic_results.json`、**23 PASS / 0 FAIL**、exit0。スイカn=0/5/10/20で120/154/196/319。異種独立・死亡除外・未成熟含む。連続配置支払120/126/133、不可/不足時不変、手動返還24と敵返還0、実JSON保存で過去支払133/次価格126/給水状態を保持。不正0/負/小数/int64外/INFを拒否し現状態不変。歴史的支払1234の返還246、旧基本額有効、helper固定額検査と弾返還13。飛行中範囲弾予約1＋clover支払10＋追加播種1で残高0、負残高なし。
- GPU 1回: `gpu.log` / `gpu_results.json`、**9 PASS / 0 FAIL**、exit0。`hud_next_cost.png`はHUDの次価格154、`list_next_cost.png`はスイカ5株・次価格154を640x360実画像で撮影し実装者が目視。撤去後はHUDと一覧が146/4株へ同時更新。nearest整数拡大設定と640内部解像度も確認。
- 合計 **32 PASS / 0 FAIL**、初回FAIL・修正追試なし。全回帰一式は実施していない。`summary.json`に集計。
- `git diff --check`: core3で成功。
- 実ユーザー保存3件は開始前後SHA-256一致（`context.json` / `freeze.json`）。hashだけ取得しロード・書込なし。GPU開始/終了ともno_focus=trueかつnative rootはminimized、OS入力・カーソル移動・前面化・復帰操作なし。

## 未検証事項・残課題・文書担当への情報

- 物理マウス/キーボード経路、全照明/全解像度、経済バランス・混植動機・楽しさ、全回帰はNOT_RUN。
- int64外価格の扱いは表現保護であり新しい価格上限仕様ではない。通常範囲の価格式と基本値は変えていない。
- 本票の未解決FAILなし。共有Godotプロセス0、override.cfgなしを`freeze.json`へ記録。編集・実行停止済みで独立検証可能。
- 文書担当へ渡す事実: 価格・実支払返還・保存の実装済範囲、旧基本額互換、logic23/GPU9 PASS、代表640画像2枚、NOT_RUN。共有STATUS・企画・票の更新は担当へ委ねる。
- コミット・stage・ブランチ切替・再委任なし。子の結果はPoC3全体の受入合格を意味しない。
