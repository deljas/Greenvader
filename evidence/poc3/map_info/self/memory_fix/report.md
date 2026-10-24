# MAP-INFO 一時検知記憶の修正

- 対象: HEAD b242086 + MAP-INFO差分。今回のゲーム編集は `poc2_session.gd` のみ。他5ゲームファイルは以前の凍結hashと一致、PLANT-UI新規3部品は未変更。
- 原因/修正: 即時のdetectedで表示されても発見値の更新が0.5秒revealを待っていた。軽いentity用 `_remember_discoveries()` を分離し、毎advance_gameの最終状態で記録、revealからも呼ぶ。50k地形走査/reveal間隔、化石接近回収の周期、巣の起動条件、読取専用UIは変更なし。
- 限定自己試験: `self_memory_fix.gd`、headless 1回、6 PASS / 0 FAIL、exit 0。通常Sessionのplayer400,400と独立検証で得たcamera外地面点502.2525,268.228を使用。walk右→advance0.1で一時検知した固定巣/探索化石を直ちに発見として記録し、walk左→advance0.1で離脱後も記憶/アイコンを維持。elapsed0.25 < reveal_at0.55、visible配列不変で地形走査が挟まらなかったことも確認。
- 保存/副作用: 同じ正常worldで隔離save/loadを1回、両記憶の復元と化石未回収/未解放を確認。遠方巣は休眠維持。実ユーザー保存にアクセスせず、APPDATA/LOCALAPPDATAをこの証拠配下profileへ隔離。
- 実行安全/証拠: CONTENT-01共有資源なし/Godot0件を直前確認。GPU/OS入力/前面化/カーソル操作なし。`results.json` に対象session/自己試験SHA256、他5件hash一致、条件結果、終了時Godot0件を記録。`run.log` にエラーなし。
- NOT_RUN: 広いlogic17/GPU9の再走、物理入力、長時間。過去の結果を新hashの全検証結果として読み替えない。独立者の失敗報告と初回mini追補の誤assert FAILは保持。
- 終了: 編集/実行停止。親へ差分・最終hash・6 PASSを返し、独立の限定追試へ引き渡す。PLANT-UI接続は引き続き停止。
