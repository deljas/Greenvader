# グリーンベーダー

Godot製のWindows向け一人用ゲームです。現在はP0（環境と画面の基準）の試作段階です。P0-ARTのビジュアル方向はユーザーが了承し、細部の描き込みは停止しています。P0全技術条件の合格やゲームの完成は確認されていません。

## Codex / Claude Code から再開する

両方で `C:/godot/greenvader` を開き、[共通タスク](tasks/README.md) と個別作業票を先に確認してください。状態は各票の `作業中(codex)` / `作業中(claude)` で管理し、他方の担当や編集範囲を無断で取得しません。

- Codex: [AGENTS.md](AGENTS.md)、[開始指示](START_PROMPT.md)。
- Claude Code: [CLAUDE.md](CLAUDE.md)、[設定と起動手順](.claude/README.md)、[開始指示](.claude/START_PROMPT.md)。
- 分担: CodexはAstra / Sol（実装と独立検証は別）/ Luna。Claudeはメイン・設計Opus / Sonnet（実装と独立検証は別）/ Haiku。
- 次のゲーム作業は [P0-VERIFY](tasks/P0_VERIFY.md)。今回の環境整備でゲームの機能追加はしていません。

Claudeはこのフォルダで `claude --model opus` を起動できます。ローカルCLIの存在と設定の検査は、モデルの利用権や実際のエージェント呼び出し成功を保証しません。実行モデルは起動先で確認してください。

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
