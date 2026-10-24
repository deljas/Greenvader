# SPR-01 通常歩行v2採用仕上げ 独立レビュー

- 2026-10-20、共有HEAD `151a53f20255489ef08481e2a353258cd8ac559c`。tasks/SPR_01.md冒頭の採用依頼と実差分・実ファイルを確認。他者差分は保持。
- 範囲はF6比較操作の除去と通常歩行固定。**独立GPU再実行なし**。実装者の結果を独立試験の代用にせず、コード・hashと提供画像を独立に読む限定レビュー。

| 条件 | 結果 | 実確認 |
|---|---|---|
| 比較入力/ボタン/案内/切替関数の除去 | PASS | main/input/uiの実ファイルにF6/KEY_F6/poc_toggle_walk/toggle_walk_mode/walk_button/歩行比較の参照なし。入力登録と分岐、UI生成・文言から除去されている。 |
| 通常歩行v2固定・停止静止維持 | PASS | mainのactor.poseはmode=0を渡し、歩行8fps/停止frame0とマウス4方向の処理を維持。runtime manifestはnormal v2採用・hop参考保持を記載。通常PNGは独立検証済みv2sheetとbyte一致。 |
| actor・素材・設定/保存/照明の保全と凍結 | PASS | 変更対象5件と保全対象11件の実hashが凍結値と一致。保全値は前回の独立基準とも一致し、normal PNGは前回v2sheetのSHA256 `9505f78fa58e6e2afa957f25d51e79134bb60c4bdbb0fb486ec005481da38bfc` を維持。actor/config/save/water/occlusionとidle/hop/normal PNG・import設定に変更なし。 |
| 提供されたGPU歩行/停止画像 | PASS | 実装者撮影のwalking.png・idle.pngを各1回view_image。右上は停止ボタンだけで歩行比較ボタンがなく、HUDにもF6比較案内なし。主人公の歩行姿勢/停止姿勢に目立つ欠けや顔を横断する影は見られない。自己結果は4PASS/0FAILだが、独立担当が再実行した結果として数えない。 |
| 独立実行・物理入力・連続動作 | NOT_RUN | 今回は依頼どおり独立GPUやOS入力を実行していない。F6無作用の実行証拠は実装者側。 |
| 広い回帰・保存/影/全環境/性能/書き出し | NOT_RUN | 今回の限定差分レビューのみ。旧試験の修正や再走なし。 |

**4 PASS / 0 FAIL / 2 NOT_RUN**。採用仕上げの限定差分で問題は見つからなかった。ユーザーの明示採用を記録上の前提とし、AIによる美術の再採否は行わない。最終受入は親が行う。

実hash・前回基準との照合・提供GPU証拠のSHA256は `hashes-and-static.json`。実GPU画像/自己結果は `../self/`。Godotプロセスなしを確認。独立編集は本フォルダの2証拠のみ。ゲーム/素材/共有進捗変更、Godot/import、OS入力/前面化/カーソル操作、再委任、コミットなし。
