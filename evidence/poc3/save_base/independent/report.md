# POC3-SAVE-BASE 限定独立検証

対象は HEAD `aecdf159ea46ba058d10ff18f785f4fa15fafde3` + 指定4ゲームファイルの8行置換。実diff、作業票、POC3_SPECの旧保存保全・新規開始方針から確認した。環境は Windows NT 10.0.26200.0 / Godot 4.7.2-stable official `ed1daf0bf001b61586d9930840f2f1394092c079`、headless。対象4ファイルと自己試験2件のhashは提出値に前後とも一致。実diffとhashは [results.json](results.json) のcontextに保存。

結果は **8 PASS / 0 未解決FAIL / 3 NOT_RUN**。初回7 PASS / 1 FAILと、失敗1条件の限定追試1 PASSを区別して保持した。全回帰の再走はしていない。

| 条件 | 結果 | 独立期待と実際 |
|---|---|---|
| 旧進行を自動採用しない新Session | PASS | 旧PoC2の完全なstateに種4321・HP23を設定して旧slot配置後、新Sessionは初期snapshot、種60・HP100のまま |
| 新保存領域の分離 | PASS | 旧slotが存在しても新slotは未作成。既定先はuser://poc3_saves |
| 新保存の復元 | PASS（限定追試） | 種137・HP73・水19・carrot解放を保存。追試で各値、224×224、敵/巣数、時計を直接照合し一致。全snapshotも値差分0。初回のJSON文字列比較FAILは下記 |
| 新しい外包・内側の識別 | PASS | 外包greenvader_poc3_1、state greenvader-poc3/version3を実ファイルから確認 |
| 旧外包形式の拒否 | PASS | 隔離poc2_savesの旧外包を明示loadして拒否。候補sessionなし、現行snapshot不変 |
| 旧内側形式の拒否 | PASS | 現行session.restoreへ旧stateを渡して拒否。現行snapshot不変 |
| 不正payload拒否時に現行を保つ | PASS | 新形式のままHP=-1としたpayloadをwrapperと直接restoreに渡し、ともに拒否。現行snapshot不変 |
| 隔離旧fixtureの保全 | PASS | PoC旧slotの識別用sentinel、完全な旧PoC2 slotとbackupの計3件がbytes/hash不変。PoC2一覧も2件のまま |
| 独立GUI・実入力・版表示の実画面 | NOT_RUN | 今回はheadless限定。窓/titleラベルの置換を静的に確認したのみ。GUI/OS入力/前面化/カーソル操作なし |
| 広い回帰・長時間プレイ | NOT_RUN | 保存分離の主要条件に限定。後続のPoC3状態追加は最終統合で別確認 |
| Windows書き出し後の動作 | NOT_RUN | 今回は配布ビルド対象外 |

初回の新形式roundtripは、全snapshotをJSON文字列として比較したためFAILになった。親へ報告後、既存保存ファイルのloadだけを1回行い、独立した具体値の期待と全snapshotの再帰比較で切り分けた。敵ID/source、巣ID、化石ID/nest_idなどで同じ数値のint/float型表現差があり、文字列は不一致、値差分は0だった。再帰比較は数値を完全一致で比較し、許容誤差は導入していない。ゲーム修正や条件緩和はしていない。初回結果はresults.jsonのchecks/failuresと [run.log](run.log)、追試はroundtrip_followupと [roundtrip_followup.log](roundtrip_followup.log) に保持。未解決のゲームFAILなし。

再現は `Godot_v4.7.2-stable_win64_console.exe --headless --path C:/godot/greenvader --script res://tests/poc3/save_base/independent_save.gd`。APPDATA/LOCALAPPDATAを本証拠内 `profile/{roaming,local}` へ設定することが必須。試験は隔離profileとheadlessを検査してからfixtureを書き込む。追試は同じ起動に `-- --recheck-roundtrip` を追加し、初回の保存済みslotを読む。初回から再現する際は新しい検証用profileを使うこと。

実ユーザーのpoc_saves/slot.json、poc2_saves/slot1.json、slot1.json.bakは読取hashだけ実施し、独立試験前後の一覧・サイズ・SHA256が3件とも一致。試験データはすべて証拠内profileに分離した。実行直前のCONTENT-01は第1段階で共有資源なし、Godot既存0件。終了後もGodot0件。終了ログにリソース残存診断なし。

編集は割当のindependent_save.gdとこの証拠領域のみ。ゲーム・設定・素材・共有進捗・他者変更・実saveは未編集。再委任/commit/stage/branch/pushなし。Godot/import権を親へ返却し、編集停止。最終受入は親判断。
