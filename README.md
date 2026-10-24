# グリーンベーダー

Godot製のWindows向け一人用ゲームです。現在の通常起動対象は第二弾PoC（PoC2）です。PoC3の設計は合意済みですが、PoC3機能の実装は未着手です。通常起動はリポジトリ直下の [`run_game.bat`](run_game.bat) を使います。

## Codex / Claude Code から再開する

両方で `C:/godot/greenvader` を開き、[共通タスク](tasks/README.md) と個別作業票を先に確認してください。状態は各票の `作業中(codex)` / `作業中(claude)` で管理し、他方の担当や編集範囲を無断で取得しません。

- Codex: [AGENTS.md](AGENTS.md)、[開始指示](START_PROMPT.md)。
- Claude Code: [CLAUDE.md](CLAUDE.md)、[設定と起動手順](.claude/README.md)、[開始指示](.claude/START_PROMPT.md)。
- 分担: CodexはAstra / Sol（実装と独立検証は別）/ Luna。Claudeはメイン・設計Opus / Sonnet（実装と独立検証は別）/ Haiku。
- PoC3の仕様と進行は [PoC3仕様](docs/POC3_SPEC.md)、[実行計画](docs/03_DEVELOPMENT_PLAN.md)、[共通タスク一覧](tasks/README.md)を参照してください。履歴保全と起動入口の整理は親が限定技術受入しました。検証範囲と未確認項目は[検証記録](docs/VALIDATION.md)に記録しています。

Claudeはこのフォルダで `claude --model opus` を起動できます。ローカルCLIの存在と設定の検査は、モデルの利用権や実際のエージェント呼び出し成功を保証しません。実行モデルは起動先で確認してください。

## 開発状況

- 現在のプレイ対象：PoC2。PoC3は設計合意済みで、ゲーム機能の実装・統合・独立検証はこれからです。
- 開発環境：Godot `4.7.2.stable.official.ed1daf0bf`。実行ファイルは `C:/godot/Godot_v4.7.2-stable_win64_console.exe`。
- 通常起動の現在の対象は [`scenes/poc2.tscn`](scenes/poc2.tscn) です。現役lab 7件と用途は[起動一覧](launchers/README.md)を参照してください。
- PoC2以前の試作・検証資料は当時の履歴として保持しています。既存履歴の保全は新しい動作検証を意味しません。

## 開発記録

- [進捗と再開手順](docs/STATUS.md)
- [決定記録](docs/DECISIONS.md)
- [検証記録](docs/VALIDATION.md)
- [素材台帳](docs/ASSETS.md)
- [残課題](docs/BACKLOG.md)
- [開発資料の索引と仕様](docs/00_README.md)

開発資料の正本は `docs/` 直下です。仕様、開発段階、検証基準は [企画書](docs/01_GAME_DESIGN.md)、[技術方針とアート仕様](docs/02_TECH_AND_ART.md)、[段階別の開発計画](docs/03_DEVELOPMENT_PLAN.md)、[自律開発の指示書](docs/04_AGENT_BRIEF.md)を参照してください。
