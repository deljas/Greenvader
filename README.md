# グリーンベーダー

Godot製のWindows向け一人用ゲームです。現在はP0（環境と画面の基準）の試作段階です。最初の画面を親が起動して確認し、ユーザーの感想を待つため後続実装を停止しています。P0全条件の合格やゲームの完成は確認されていません。

## 開発状況

- 対象範囲：P0〜P5。P0実装中、P1〜P5未着手。P6以降は今回の開発範囲外です。
- 開発環境：Godot `4.7.2.stable.official.ed1daf0bf`。実行ファイルは `C:/godot/Godot_v4.7.2-stable_win64_console.exe`。
- 640×360、16pxタイル、1280×720初期表示、Forward+を画面試作に暫定採用しました。P0の最終固定ではありません。
- 親がRTX 5070 Ti上でForward+の実画面を起動して確認しました。画面・操作の未確認項目は残っています。
- 実行コマンドと操作は[検証記録](docs/VALIDATION.md)を参照してください。

## 開発記録

- [進捗と再開手順](docs/STATUS.md)
- [決定記録](docs/DECISIONS.md)
- [検証記録](docs/VALIDATION.md)
- [素材台帳](docs/ASSETS.md)
- [残課題](docs/BACKLOG.md)
- [開発資料の索引と仕様](docs/00_README.md)

開発資料の正本は `docs/` 直下です。仕様、開発段階、検証基準は [企画書](docs/01_GAME_DESIGN.md)、[技術方針とアート仕様](docs/02_TECH_AND_ART.md)、[段階別の開発計画](docs/03_DEVELOPMENT_PLAN.md)、[自律開発の指示書](docs/04_AGENT_BRIEF.md)を参照してください。
