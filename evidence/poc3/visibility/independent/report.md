# POC3-VISIBILITY 限定独立検証

**ヘッドレス主要条件 9 PASS / 0 FAIL / 3 NOT_RUN。** 実差分と仕様、提供GPU画像/JSON/起動設定を独立担当が確認した。最終受入は親が行う。

- 依頼基準: aecdf15 + SAVE-BASE + VISIBILITY。実行時には親がSAVE-BASEを `77e3463785e81db598a2ea1279f59cbbbe29ef15` へコミット済みで、独立実行前後のHEADは同じ。今回対象のworld_view.gdは前後とも SHA256 `ABB814238E321A62ABC303634B2FF15F556143D75A3CE482414C7549CBACD17A` で指定値に一致。session/combat/persistenceのhashも前後一致。
- Windows NT 10.0.26200.0、Godot 4.7.2-stable official `ed1daf0bf001b61586d9930840f2f1394092c079`。実行はheadless限定、APPDATA/LOCALAPPDATAと実user_dataは当該証拠内profileへ分離。保存APIを使わず、実saveはアクセスしていない。
- 直前CONTENT-01は第1段階でGodot/import予約なし、既存Godot0件。独立試験は1回のみ。
- 実diffはworld_view._entitiesの距離視界による除外を化石のみに限定した1行置換と説明1行追加。マップ・戦闘・活動・保存・素材・画面設定の変更ではない。実diffと前後hash等は [results.json](results.json) に保持。

| 独立条件 | 結果 | 観測 |
|---|---|---|
| 視認マスクが空でも生存敵を描画対象にする | PASS | visible/known全0でenemyのMeshInstance3Dが生成されvisible=true |
| 同条件で固定巣を描画対象にする | PASS | 固定巣の描画nodeを確認 |
| 同条件で動く親玉を描画対象にする | PASS | motherの描画nodeを確認 |
| 表示だけではゲーム状態を変更しない | PASS | 描画対象更新の前後で全session snapshotが一致 |
| 未視認の化石は既存条件で非表示 | PASS | 同じ空マスクで化石nodeは表示されない |
| 画面表示だけで遠方巣を起動しない | PASS | 主人公600,600・巣140,100/180,100、緑なしのfixtureで描画後にcombatを0.25秒だけ進行。両巣は休眠、敵生産なし |
| 視認した未回収化石は表示する | PASS | 化石セルだけvisibleを設定すると表示nodeを確認 |
| 回収済み・巣報酬化石は表示しない | PASS | found=true、その後nest_id付きの両ケースが既存条件で非表示 |
| 死亡・配列除去で描画nodeが消える | PASS | 敵/親玉のHPを0、固定巣を配列から除去し、全3nodeが登録から消える |
| 独立GPU再実行・物理入力 | NOT_RUN | 追加GPUは親指定で不要。OS入力/前面化/カーソル操作なし |
| 建物遮蔽・マップ情報・広い回帰 | NOT_RUN | 対象外。距離非表示の解消を遮蔽物越し表示や新しいマップ仕様の合格に広げない |
| 全照明・全窓サイズ・書き出し後の動作 | NOT_RUN | 今回は変更範囲の代表条件のみ |

期待は仕様の「通常画面の生存敵・固定巣・親玉を距離視界で消さない」から設定した。既存の通常Sessionからentityの構造だけを取り、独自に位置・ID・休眠状態と全空の視認マスクを設定した。実装の視認式を期待値へ写していない。ヘッドレスでは描画nodeの生成/可視属性を確認しており、実際のカメラ内の画素表示を独立再撮影したことにはしない。

提供されたself/before.pngとafter.pngは独立担当が実際に開いて比較した。beforeでは近側3体のみ、afterでは遠側enemy/fixed nest/motherも出現している。self/before.jsonとafter.jsonで同じ遠側3対象がin_camera=true/old_visible=false、座標も一致し、renderedだけfalse→trueとなっていることを確認。640×360の明瞭な画素を目視した。画面条件は実装差分で変更されていない。画像hashはresults.jsonのcontextに記録。

提供GPU起動の安全証拠は、保存されたstartup_override.cfgのno_focus=true/mode=1、試験スクリプトの起動時/終了時チェック、before/after JSONのstartup_no_focus=true/startup_mode=1/runtime_unfocusable=true/runtime_mode=1、after.logを照合した。最小化を戻さずSubViewportを撮影する手順と一致している。これは提供証拠の確認であり、独立担当がGPU起動時のOSフォーカスを別に観測した結果ではない。beforeにあった空メッシュfixture診断は自己報告通り履歴に残り、afterと独立run.logにはエラーなし。

再現は当該profileへのAPPDATA/LOCALAPPDATA分離後、`Godot_v4.7.2-stable_win64_console.exe --headless --path C:/godot/greenvader --script res://tests/poc3/visibility/independent_visibility.gd`。詳細は [run.log](run.log) とresults.json。

終了時Godot0件、override.cfgなし。ゲームコード・設定・素材・共有進捗・他者変更は未編集。編集は割当試験と当該証拠のみ。再委任/commit/stage/branch/pushなし。Godot/import権を親へ返却し、編集停止。
