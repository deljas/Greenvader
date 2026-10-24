# POC3-INPUT 独立限定検証

**9 PASS / 0 FAIL / 3 NOT_RUN。** 対象はHEAD `9d54a6d1795065e6e642fe01543b2c8d2a1f27ee` + INPUTゲーム6ファイル差分。freeze.jsonの6件と実ファイルが前後一致。実diffと新input_latchも読んだ。詳細hash/観測は [results.json](results.json)、原ログは [run.log](run.log)。

Windows NT 10.0.26200.0 / Godot 4.7.2-stable official `ed1daf0bf001b61586d9930840f2f1394092c079`、headlessで1回実行。Viewport.push_inputだけを使用した。入力仕様から操作順と期待を定め、Sessionのfire/water_at/skill呼出しを試験用派生クラスで記録して、そのままsuperを実行した。入力部品の遷移式や戻り値を期待の正解として複製していない。

| 条件 | 結果 | 独立観測 |
|---|---|---|
| Shift左、Shiftを先に離す | PASS | skill1呼出し1回、通常射撃呼出しなし。Shift解放後の保持も通常動作へ変わらず、種/水消費なし |
| Shift右、マウスを先に離す | PASS | skill2呼出し1回、種3消費、水消費なし。Shift解放後も給水なし |
| 左右の通常保持途中でShift | PASS | 両ボタンとも通常動作を停止し、Shiftだけではスキルなし。Shiftを離しただけでは再開せず、ボタン解放後の新クリックで対応する通常動作のみ再開 |
| 設置1press/取消/Shift優先 | PASS | 左保持中も1株だけで選択保持。右取消で給水なし。再選択後のShift左は選択解除してskill1だけ |
| E一覧の停止と閉じた保持漏れ | PASS | 時計停止。行上でShift左を押したままEで閉じ、Shiftを離して世界を進めても戦闘呼出しなし |
| Tabマップとpopup右取消/閉じた保持漏れ | PASS | 世界停止、popup上の右クリックで選択/小画面を取消。右保持のままTabで閉じても給水・射撃なし |
| Escメニューを閉じた保持漏れ | PASS | メニュー上のShift左保持をEscで戻し、Shift解放後も戦闘呼出しなし |
| ホイールの用途分離 | PASS | 通常画面で下端1、上へ3/5/7/7と非循環。マップではzoomだけ変更、一覧では播種幅を変更しない。E/Tabの各開閉はエンジン入力で実施 |
| 幅のJSON保存/不正拒否/旧既定値 | PASS | 幅5を隔離save/loadで復元。2、3.5、文字列5、bool trueを各1回拒否し現行snapshot不変。幅欠落の既存PoC3 snapshotは1へ復元 |
| 独立GPU/native外観/物理入力/音の実聴 | NOT_RUN | 提供画像の独立目視まで。OS入力/前面化/カーソル操作なし |
| 広い回帰/長時間/PLANT一式 | NOT_RUN | 今回の主要境界のみ、以前の一式は再走していない |
| 全サイズ/全照明/書き出し/AREA-SEED効果 | NOT_RUN | 幅は選択値の保存まで。実際の範囲着弾・精算・プレビューは後続 |

self/menu.png、help.png、map.pngを実際に開いて確認した。音量/ミュート付きpauseメニューは640×360内、説明はShift/E/Tab/ホイールの用途と選択値のみの範囲を明記し、マップには閉じるTabボタンがある。文字と画素は明瞭。Q/R/M/N旧分岐の削除、音量とミュートの接続は実diffで確認したが、音の実聴はしていない。

自己初回14 PASS/1 FAIL、保存限定5 PASS、GPU26 PASSは別の証拠として保持し、独立結果へ合算/上書きしていない。初回のJSONfloat幅拒否に対し、実際のJSON往復と不正型拒否を独立で確認した。

起動直前、CONTENT-01が共有Godot/importを使わず別sandboxだけを使う予約を確認。所有不明プロセスの停止はしていない。APPDATA/LOCALAPPDATAと実user_dataはindependent/profileへ隔離し、実ユーザー旧save3件は読取hashだけで前後一致。終了時Godot0件、ログにエラー/警告なし。

ゲーム/文書/票/Gitは未編集、他担当差分を保持。割当試験と証拠のみ追加、再委任/commit/stage/branch/pushなし。Godot/import権を親へ返却し、編集・実行停止。最終受入は親判断。
