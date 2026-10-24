# CONTENT-02 独立検証(第2弾) review

対象版: 共有ツリー poc/3d-quarter-view、HEAD 047a540 + 未コミット差分。凍結 evidence/content_pack/self2/manifest_stage3.txt(242件)は検証の最初と最後に sha256sum -c で全件一致。
実行: 隔離プロジェクト C:/godot/greenvader_content_sandbox(sync_sandbox.sh で同期。pull は不使用)。Godot 4.7.2、実GPUは NVIDIA GeForce RTX 5070 Ti(display=Windows、ウィンドウは unfocusable、OS入力なし)。

## 独立テスト(tests/content_pack/independent2/、実装者のテストと部品は共有しない)
| 入口 | 内容 | 結果 |
|---|---|---|
| animals_a.gd | 向き(スカンク・カガミトカゲ)、濡れ・ウナギ、モグラ、カバ | 120 PASS |
| animals_b.gd | コウモリ、イモリ、マンホール網、ガラスジカ、クマ、サイ、エビ、カエル、安定判定、再侵攻禁止 | 157 PASS + NOTE 1 |
| crops_v2.gd | 植物8種、第1弾との関わり(リンゴ、価格系統ほか) | 105 PASS |
| save_v2.gd | 全状態の保存復元(30秒の同一継続)、不正データ拒否60件、ポーズ | 81 PASS |
| sprite_v.gd | 仮スプライト23枚の画像検査 | 140 PASS |
| gpu_v2.gd | 確認画面の入力操作 + 実GPU撮影・足元基準照合 | 192 PASS(headless では操作のみ 96 PASS + 描画 NOT_RUN 2) |

## 回帰(隔離側で再実行)
crops 145/0、enemies_a 72/0、enemies_b 71/0、save_robust 55/0、lab_logic 124件中1 FAIL(「スプライトちょうど63枚」: 現在86枚。第2弾の23枚追加による想定内)。
self2 再実行: enemies2_a 109、crops2_logic 73、save2_enemies 32、save2_logic 19、lab2_logic 187 すべて PASS。enemies2_b の2件(第2段時点の「23種はスプライト未作成」「63枚」固定判定)と common2_logic の1件(第1弾限定の草食タグ判定)は、第3段・第2段の定義追加による古い固定判定の失敗で、想定内。

## 観察(合否外)
1. place_glass_deer を同じ地域キーで2回呼ぶと2頭目が出る(窓口は初期配置時に1回だけ呼ぶ前提。読込後に再実行しないこと)。
2. タイホウエビは待機(cooldown)中に徘徊するため、対象が射程から外れると次の予兆が遅れる(位置を固定すれば衝撃波の間隔は5.0秒)。
3. ガラスジカは半透明(設計どおり)。コウモリ・ウナギ・フウセンガエル・ガラスジカの画像は下辺に画素が届かない(飛行・水中・半透明、足元基準の座標は下辺中央)。

## 画像の確認(目視)
evidence/content_pack/independent2/sprites_contact_sheet.png と gpu/*.png を確認。敵の仮スプライトに葉・花・茎などの植物の要素はない(カガミトカゲ・フウセンガエルは緑だが動物の姿)。輪郭線なし(外周が単色の暗色に偏らない)。実GPU撮影は 640x360 のビューポート画像、整数倍ブロックが一様(nearest)、足元基準のずれ0〜±1px(スプライト画素の完全一致で照合)。
