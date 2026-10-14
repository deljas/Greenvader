# 検証記録

更新日: 2026-10-14。最終合否はAstraが判断する。この記録は未検証条件を合格にしない。

## 環境・対象

- エンジン: Godot `4.7.2.stable.official.ed1daf0bf`; 実行ファイル `C:/godot/Godot_v4.7.2-stable_win64_console.exe`。
- 初期資料の基準コミット: `16b845fe7550667d7689e252e1b406f790a2d241`。
- P0実装対象コミット: `f7ead6a1117f28b38b742f98921c2f8de05d6fdc`。実装対象ソースのSHA-256一覧は [`evidence/p0/self/source-manifest.json`](../evidence/p0/self/source-manifest.json)。独立静的レビューでコミット対象のソースハッシュ一致を確認。
- 親報告環境: Windows 11 Pro `10.0.26200`、AMD Ryzen 9 7900 12-Core Processor、NVIDIA GeForce RTX 5070 Ti、ドライバー `32.0.16.1088`、可視メモリ `66692428 KiB`。親実行結果からの転記で、別証拠ファイルは未登録。

## 実施済みの限定確認

| 確認 | 結果 | 証拠と範囲 |
|---|---|---|
| 最終版headless import | 実装者報告 PASS | [`evidence/p0/self/import.log`](../evidence/p0/self/import.log)。対象版の読み込み。GUI実画面合格を示さない。 |
| Headless smoke 30フレーム | 実装者報告 PASS | [`evidence/p0/self/smoke.log`](../evidence/p0/self/smoke.log)。 |
| 実装者自己チェック15項目 | 実装者報告 PASS | [`evidence/p0/self/checks.log`](../evidence/p0/self/checks.log)。`failures=0`。独立検証結果ではない。実画面描画・実操作等のNOT_RUNも同ログに記載。 |
| Forward+ 3解像度のviewport transform | 実装者報告 PASS | [1280](../evidence/p0/self/sunny-1280.log)は2倍・原点、[1920](../evidence/p0/self/sunny-1920.log)は3倍・原点、[1366](../evidence/p0/self/sunny-1366.log)は2倍・オフセット(43,24)。実画面外枠の画素を測定した結果ではない。 |
| 内部晴れ・雨・夜画像 | 実装者報告の静止画像確認 | [晴れ](../evidence/p0/self/sunny-1280.png)、[雨](../evidence/p0/self/rain-1280.png)、[夜](../evidence/p0/self/night-1280.png)は640×360内部viewport。カメラ同期修正前に取得。静止構図は変わらないとの報告だが、最終版の動的描画は未確認。 |
| 親によるForward+実画面確認 | 親報告で限定確認 | RTX 5070 Ti上で1280×720ウィンドウを起動。日本語UI、仮花・植物・イノシシ・水辺を目視。`d`単発入力で微小移動を確認。連続・斜め操作や全入力は未確認。雨切替中にユーザー入力検知が返ったためUI操作を停止。ウィンドウは開いたまま。 |
| Godot export templates | 未導入との親報告 | 親の実行結果。書き出し試験は未実施。 |

## P0受入条件

独立検証の準備計画は [`evidence/p0/independent/PLAN.md`](../evidence/p0/independent/PLAN.md)。独立静的レビュー [`evidence/p0/independent/REVIEW.md`](../evidence/p0/independent/REVIEW.md) を親が確認済み。レビューはGodot起動・実行・UI操作を行っていないため、実行を要する条件は引き続きNOT_RUN。実装者自己チェックのPASSを独立検証として扱わない。

| ID | 独立静的所見 | 判定と範囲 |
|---|---|---|
| S01 | `scripts/pixel_art.gd` の種は暗色画素が明るい中心を全周で囲む形。輪郭線なし条件への抵触。 | 静的FAIL。実画面再現はNOT_RUN。親は修正待ちとして受け入れ、ユーザー停止指示のため今回は修正しない。 |
| S02 | pause中も天候UIボタン経由で条件・表示を変更できるコード経路がある。 | 静的FAIL。実操作再現はNOT_RUN。親は修正待ちとして受け入れ、ユーザー停止指示のため今回は修正しない。 |

レビューの限定PASS所見と未実行条件は `REVIEW.md` を参照。レビューは最終受入やP0完了を宣言していない。

未実施または限定確認の代表項目: 実画面での連続・斜め移動、マウス照準とクリック、解像度3種の外枠余白画素、最小サイズへのnative resize、移動中のにじみと画面端カメラ、晴雨夜の最終版動的描画、native Escポーズ。1回の`d`入力を連続操作試験のPASSとしない。個々の条件と手順は検証計画を参照する。

P1〜P5の検証は未開始。保存復元、種・水の循環、地域安定、孤立地を含む厳密な100％緑化、書き出し後の起動などを未確認のまま合格扱いしない。

## 公式資料

P0の参考として親が確認したGodot 4.7資料:

- [複数の解像度への対応](https://docs.godotengine.org/en/4.7/tutorials/rendering/multiple_resolutions.html)
- [2Dライトと影](https://docs.godotengine.org/en/4.7/tutorials/2d/2d_lights_and_shadows.html)
