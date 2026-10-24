# MAP-INFO 記憶修正の独立限定追試

**4 PASS / 0 FAIL / 3 NOT_RUN。前回の固定巣の一時検知記憶FAILは、今回の再現条件で解消した。** 初回 [report.md](report.md)、results.json、run/limited_followupログは変更せず保持した。

対象はHEAD `b2420865b900c1f5e91f8fa0827bb48e17c9318c` + MAP-INFO修正。session SHA256は前後とも `42A77E3C8AD63365A9991748A0A67E102E7D15E33BA81E640A585E0451259E52`。他5ゲームファイルも以前の凍結値と前後一致。実diffでは発見記録だけを_remember_discoveriesへ分離しadvance_game最終状態から呼び、revealでも共有している。UI描画、地形走査周期、接近回収、巣起動条件への修正なし。

Windows / Godot 4.7.2、headlessで1回実行。前回と同じ実Camera3D ray由来の画面外地面点を使い、通常Session.walk/advanceで右へ入り左へ戻した。期待は仕様の「発見した固定巣・探索化石の位置を離脱後も記憶する」から設定した。

| 限定条件 | 結果 | 観測 |
|---|---|---|
| 固定巣の一時検知→離脱 | PASS | 初期非表示→一時表示時に即discovered→離脱後も淡色四角 |
| 探索化石の同経路 | PASS | 初期非表示→一時表示時に即discovered→離脱後も骨型 |
| 地形周期・未回収・未起動 | PASS | elapsed0.25 < reveal_at0.55、visible/known配列不変。化石found=false/未解放、巣は休眠、敵生産なし |
| 一時発見した両記憶の保存復元 | PASS | 同じ正常worldを隔離slotへ保存/読込し両記憶アイコン保持。化石未回収・未解放、巣未起動も保持 |

記録は [memory_fix_results.json](memory_fix_results.json)、[memory_fix.log](memory_fix.log)。元の全主要条件/GPUは再走せず、3 NOT_RUN（独立GPU/native入力、広い回帰/長時間、全照明/全サイズ/書き出し）を維持する。この4 PASSを全体の新しい回帰結果とはしない。

直前CONTENT-01は第1段階/共有資源なし、Godot0件。APPDATA/LOCALAPPDATA/user_dataはindependent/profile内、保存先はその中のmemory_fix_checkpoint。実saveアクセスなし、GUI/OS入力/前面化/カーソル操作なし。終了時Godot0件、エラーなし。並行PLANT-UIの非重複UI編集は対象外として保持した。

ゲーム/文書/作業票/Gitは未編集。新しい割当試験と追補証拠のみ追加。Godot/import権を親へ返却し、編集停止。最終受入は親判断。
