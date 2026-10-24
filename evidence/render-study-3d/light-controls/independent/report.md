# TECH-3D-04 独立検証

対象: HEAD `99013702eaf36db72a64d60d284680fb834f13c5` 上の凍結未コミット差分。Windows / オフライン検査は同梱Python/Pillow。提出GPU証拠は Godot 4.7.2 / Vulkan Forward+ / RTX 5070 Ti。**6 PASS / 0 FAIL / 3 NOT_RUN**。最終受入は親へ返す。

作業票、実装/撮影コード、scene/bat、before原文と実際の安全化diffを読み、代表実GPU画像・ログ・JSONを照合した。実装者の15 PASSを独立実行結果として再計上していない。GPU再実行は不要と判断し、独立実行はオフライン画素/JSON/hash検査だけに限定した。

| 確認条件 | 結果 | 方法・確認できた事実 |
|---|---|---|
| 太陽の任意角度UI・端点安全性 | PASS | static＋提出GPU証拠レビュー。slider/SpinBoxは方位0〜360、仰角−90〜90、0.1°刻みで同じhandlerへ接続しno-signal同期。135.7/25.4、315.2/61.2がsnapshotと実画像に反映。UI外の画像差146,119画素。+90は有限/直射ON、−90は有限/直射OFFの記録・画像と明示ラベルを確認。Euler basisと水平normalゼロ時fallbackにより退化を避ける実装。独立エンジン再実測ではない。 |
| 周回点光源・ON/OFF・停止/手動/再開 | PASS | static＋提出内部Control経路/logレビュー。OmniLight3Dは影有効、建物外周の楕円軌道、高さ2.4。停止中angle設定と再開後の角度進行は撮影テストコードとGPUログを照合。45/225/OFFを目視し、UIを除いた範囲で45対225は123,881画素、225対OFFは45,872画素の差。48採取位置も異なる。マーカーはcast OFF。 |
| 光ごとの影板mask分離 | PASS | ソースのworld1/sun2/point4、shadow_caster_mask太陽3/点5を確認。提出point単独45°画像の独立全画素比較で、太陽板OFFは差0、点板OFFは差616画素。値一致だけでなくGPU出力に分離の効果がある。太陽単独側の逆対照は追加していない。 |
| 2影板と歩行状態の同期 | PASS | 共通frame/flip/footから両板を更新するソースを確認。58状態中、周回48状態/4姿勢/反転24件。sun側texture instance ID一致、全位置有限、screen foot整数、両板の同期/有限フラグは全件true。point側の個別IDと各板の生の足元座標はログにないため、その部分はコード＋自己記録フラグのレビューに限定。 |
| UI・画像・整数3倍 | PASS | default/point45のUIとworld、計4組の640×360→1920×1080を独立全画素比較し完全一致。UIはGPU root640をCPUでnearest3倍した提示PNG、world1920は別GPU viewport読取りであることを区別。default/point45の1920 UI、point225、2方位、±90、動画復号contact sheetをview_imageで確認。日本語/数値/状態表示が読め、主要建物とキャラは見える。 |
| 凍結・既存保全・最終ログ | PASS | 凍結77件はmanifestと開始/終了で一致。HEADとmanifest SHAも親指定と一致。既存9件はbeforeが過去の独立hashと一致し、8件は不変、sprite_shadow_labだけ許可された水平normal安全化3行の差分。元原文も前回版hashと一致。GPU終了0、stderr空、最終gpu.logにERRORなし。 |
| 独立GPU/内部UI再実行 | NOT_RUN | 適切な既存GPU証拠があり追加再走なし。UI操作の動作証拠は実コードと提出内部シグナル試験のレビューであり、新しい独立入力試験ではない。 |
| native/初期フォーカス/物理入力 | NOT_RUN | 実GPU root画像を確認したが、nativeウィンドウの撮影・初期フォーカス比較・物理経路は未実施。 |
| 全角度・全光組合せ・実時間性能・連続再生 | NOT_RUN | 代表条件と58状態のみ。動画は48枚/12fpsの提示用4秒で、停止中に角度を進めて採取したもの。ライブ周回のFPS計測・連続動画全フレーム確認ではない。 |

source-manifest SHA-256は `0d1665ac654b6adb36aa1212201a1f561afbf2484e3abc8e84cefbcf3673f521`。条件別結果は `checks.json`、独立画素/JSON検査は `offline-checks.json`、開始/終了hashは `source-start.json` / `source-end.json`。

既存sprite_shadow_labの変更は、垂直光で水平normalがゼロに近い場合にカメラの水平方向をfallbackとする安全化のみ。通常の昼方向では旧式と同じ正規化normalになることをコードから確認した。旧bat/旧シーンの再起動回帰は行っていない。project.godotや既存の材質/geometryは不変。

影板のyawは各光へ向ける美術上の近似であり、身体の厚みを持つ影ではない。表示キャラはunshadedで、キャラ受光は対象外。硬影の残るサンプリングを完全二値とは扱わない。MP4のH.264/yuv420p圧縮にはPNGの全画素保証を適用しない。新しいFAILは発見せず、美術や操作感の最終承認は代行していない。

製品コード・共有docs・票は編集していない。独立報告以外の書込み、OS入力送信・前面化・カーソル移動・Godot起動・再委任・commit/branch操作はなし。セーブは使用していない。終了時Godotプロセス0件を確認。独立担当の編集を停止し、GPU/import資源を親へ返却する。
