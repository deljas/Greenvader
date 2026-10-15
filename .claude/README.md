# Claude Code 共用環境

リポジトリのルート `C:\godot\greenvader` から使うプロジェクト設定です。共通規則は [AGENTS.md](../AGENTS.md)、予約と引継ぎは [tasks/README.md](../tasks/README.md)、Claude固有指示は [CLAUDE.md](../CLAUDE.md) を読みます。

| 担当 | モデル指定 | 定義 | ツール |
|---|---|---|---|
| 主会話・設計統合受入 | opus | `settings.json` | Claudeの通常権限に従う |
| 必要時の設計補助 | opus | `agents/green-designer.md` | Read, Grep, Glob |
| 実装・自己検証 | sonnet | `agents/green-implementer.md` | Read, Grep, Glob, Edit, Write, Bash |
| 別呼出しの独立検証 | sonnet | `agents/green-verifier.md` | Read, Grep, Glob, Edit, Write, Bash |
| 承認済み記録の文書化 | haiku | `agents/green-documenter.md` | Read, Grep, Glob, Edit, Write |

各子で `Agent` を禁止しています。明示したtoolsは機能一覧で、Bash・Edit・Writeの対象パスをOSで隔離するものではありません。編集範囲と共有資源は作業票と運用で守り、検証者は割り当てたテスト/証拠以外を編集しません。設定に自動承認・権限バイパス・hooks・MCPは追加していません。既存のユーザー/組織設定やCLI指定の影響も起動時に確認してください。

## 起動と確認

```powershell
Set-Location C:\godot\greenvader
claude --model opus
```

PATHで見つからない場合のローカル実行ファイルは、親が確認した `C:/Users/tkant/.local/bin/claude.exe`（調査時v2.1.296）です。CLIやモデルの版をこの設定で固定しません。opus/sonnet/haikuはaliasesで、実モデルは接続先・アカウント・上位設定等に依存するため、起動後に `/model` で主会話の選択を確認し、各役の実呼出し時にも実際のモデルと可用性を確認して記録します。

起動後は [START_PROMPT.md](START_PROMPT.md) を渡し、まず作業票とSTATUSを読みます。4つの定義ファイルが存在すること、Claudeが定義を読み込むこと、各モデルが実際に応答することは別々の確認です。今回の整備は静的ファイル検証のみで、Claude起動・認証・モデル呼出し・利用可能性は未検証です。

## 担当と引継ぎ

各 `tasks/*.md` 管理欄を正本にし、親が開始前にタスクID・状態・担当ツール・担当セッション・編集範囲・共有資源を照合します。子はそのIDと範囲を継承し、管理欄を変更しません。`検証待ち` でも担当予約は保持します。

他ツール/他セッションの予約や共有資源と競合する作業は停止します。Codexの担当をClaudeが上書きしません。引継ぎ時は元担当が編集を凍結し、対象コミット・未コミット差分・検証証拠・未完了事項・共有資源の状態を渡します。親が引継ぎを確認して管理欄を更新した後、新担当が内容を読み、共有なら同じ差分を再適用せず作業を続けます。自動ロックや相互監視を実装した設定ではないため、両ツールの親が管理欄と現状を確認する運用が必要です。

共通仕様や親が承認した判断は、同じ内容を別のClaude用仕様書へ複製せず共通資料へ反映します。最新ユーザー指示が優先され、現在のゲーム実装/アート細部停止を、この環境の追加だけで解除しません。

## 公式形式

モデル設定は [Claude公式Model configuration](https://code.claude.com/docs/en/model-config)、プロジェクトのMarkdown/YAML役定義は [Claude公式Subagents](https://code.claude.com/docs/en/sub-agents) に従います。

## Codexとの引き継ぎ

Codex ⇄ Claude の引き継ぎは、プロジェクトスキル [`codex-handoff`](skills/codex-handoff/SKILL.md) の手順で行う（「Codexに引き継ぐ」「Codexから引き継ぐ」で起動）。規則の正本は AGENTS.md と tasks/README.md で、スキルはその実行手順と管理欄更新スクリプトだけを持つ。
