# SPR-01 発射v3ゲーム仮組込み 独立検証準備

- 2026-10-20、共有HEAD `151a53f20255489ef08481e2a353258cd8ac559c`。tasks/SPR_01.md最新節、128件保全baselineと4つの変更前原稿を確認。凍結前のためGodotは起動しない。
- 期待時間: 種400ms/release66ms、水800ms/release400ms。入力直後に溜め、発射前は追加入力で再始動しない。発射済みrecoveryは新入力で中断可能。
- 入力時のaim/種選択snapshot、発射時のorigin、移動継続、開始時/発射時の資源・弾上限・無効点確認、消費/音の1回同期を重点確認する。期待値は仕様から取り、実装と同じ式だけを正解にしない。
- pause/menu/viewpointの時間停止、death/load/newgameのpending取消、session.fire即時API互換・保存形式保全、4方向歩行/静止への復帰を主要回帰とする。
- 凍結・Godot停止通知後に実差分/target hashを固定し、専用独立試験を1本程度でlogic+実GPUをまとめて実行。非フォーカス/Hidden、入力はInput.parse_input_eventのみ。実セーブを使わず専用証拠領域でデータを分離する。
- GPUは発射中正面共用、形成FX/飛翔、原寸24×36/640/nearest、固定足元と影コマ同期を実画像/実データで確認。全方向の完成アートとしては受け入れない。
- 編集所有: 本independentフォルダと `tests/independent/spr01_fire_integration.gd`（必要なら専用補助）のみ。実装/assets/docs/票は編集せず、不具合は親へ返す。Godot/importは凍結通知まで実装担当専有。
- 広いゲーム回帰・物理入力・全環境/性能・主観採用はNOT_RUN。再委任・コミット・OS入力送信/前面化/カーソル操作なし。
