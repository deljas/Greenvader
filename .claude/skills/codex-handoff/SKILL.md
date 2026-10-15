---
name: codex-handoff
description: greenvaderでClaude CodeとCodexの間で作業を引き継ぐ手順。「Codexに引き継ぐ」「Codexへ渡す準備」「Codexから引き継ぐ」「Codexの作業を再開する」と言われたときに使う。作業の凍結、WIPのコミット、作業票の保留と予約の解除、STATUSの更新、Codexへ渡す開始文の作成と、その逆向きの受け取り確認を行う。
---

# Codex ⇄ Claude 引き継ぎ

規則の正本は `AGENTS.md`、`tasks/README.md`（取得・実装・引き継ぎ）、各作業票の管理欄。このスキルは、その手順を毎回同じ順で実行するための段取りで、規則を複製しない。食い違ったら正本に従う。

管理欄の更新には `scripts/ticket_state.py` を使う（使い方は末尾）。Git操作は親（主会話）だけが行い、子エージェントには任せない。

## A. Claude → Codex（渡す）

1. **止める**
   - 実行中の子エージェントを止めるか、完了を待つ。
   - 子に新しい作業を始めさせない。
   - 自分たちが起動したGodotが残っていないことを確認する（`tasklist | grep -i godot`）。
2. **証拠を元に戻す**
   - 回帰の再実行で、他票の確定済み証拠（`evidence/**/checks_info.json` など）が書き換わっていないか、`git diff --stat -- evidence` で確認する。
   - 書き換わっていたら、確定済み証拠だけを `git checkout --` で戻す。現在の票の新しい証拠は残す。
3. **コミットする**
   - 作業途中の差分は、件名に `wip(<票ID>): … (UNVERIFIED)` と書いてコミットする。未検証であることを本文にも明記する。
   - 他者（ユーザー・Codex）による未コミットの変更は、勝手に含めない。ユーザーに確認し、別コミットにする。
   - 作者は `git -c user.name="Claude Code" -c user.email="claude@local.invalid"` で指定する。git設定は変えない。
4. **作業票を保留にする**
   - 作業中だった票（子票、段階票、計画票 AUTO-xxx）をすべて `保留` にし、担当を `なし`、予約を `なし` にする。最終担当にClaudeのセッション名を残す。
   - 子票の末尾に「中断の記録」を書く。書く内容は次のとおり。
     - 対象コミット
     - 未コミット差分の有無
     - 完了したこと、未検証（NOT_RUN）のこと
     - 実行中プロセスの有無
     - 共有資源の返却
     - 再開時の次の一手（番号付き）
     - 未決のユーザー判断
5. **STATUSを更新する**
   - `docs/STATUS.md` の「現在地」と「次の行動」を更新する。保留の票、WIPコミット、引き継ぎ先がやること、未記録の文書の有無を書く。
   - DECISIONS・VALIDATIONなどへの記録が追いついていなければ、そのことをSTATUSに明記する（正本は票の末尾の記録）。
6. **確認する**
   - `grep -n '状態:' tasks/*.md | grep -v '完了\|未着手'` で、作業中が残っていないこと。
   - `git status --short` が空であること。
   - `git log --oneline -5` を確認する。
7. **ユーザーへ渡す**
   - 下の「Codexへの開始文」を埋めて提示する。
   - 未決のユーザー判断と、ユーザー確認待ちを短く並べる。

### Codexへの開始文（テンプレート）

```
このリポジトリをClaude Codeから引き継ぎます。最初に AGENTS.md、tasks/README.md、docs/STATUS.md、docs/DECISIONS.md を読み、作業票の管理欄を確認してください。
- 基準コミット: <hash>（<WIPなら「<票ID> は未検証のWIP」>）。作業ツリーに未コミットの差分はありません。
- Claude側の担当はすべて解除済みです（保留: <票ID一覧>）。
- 続きは <票ID> の「中断の記録」→「再開時の次の一手」から。取得するときは、管理欄を作業中(codex)にし、担当セッションと予約範囲を記入してから着手してください。
- 未決のユーザー判断: <あれば列挙>
- 試験は短く（AGENTS.md「実装と検証」: 早送り、1条件1回、総当たりなし）。実マウス・キーボードの乗っ取りは禁止（毎回の明示承認が必要）。
```

## B. Codex → Claude（受け取る）

1. `CLAUDE.md` の指示どおり、AGENTS.md・tasks/README.md・STATUS・DECISIONS を読む。
2. `git log --oneline -15` と `git status --short` で、Codexのコミットと未コミット差分を確認する。
   - 未コミット差分がある場合は、引き継ぎ不足として扱う。破棄も取得もせず、ユーザーに確認する。
3. 管理欄を確認する（`grep -n '状態:\|担当ツール:\|担当セッション:\|予約中' tasks/*.md`）。
   - `作業中(codex)` やcodexの予約が残っていれば、取得しない。ユーザーにCodexの停止と解除を確認する。
   - 引き継ぐ票が `保留`・担当なしで、中断の記録（対象コミット、次の一手）があることを確認する。
4. 実行中プロセスを確認する（Godot。Codexのプロセスが動いていても、作業を止めているかは表示からは判断できないので、不明ならユーザーに確認する）。
5. 票を取得する。
   - `ticket_state.py claim` で、作業中(claude)・担当セッション・予約範囲・取得時の基準コミットを記入する。
   - 管理欄の変更だけをコミットしてから着手する。
6. 中断の記録の「次の一手」から再開する。差分を再適用しない（共有の作業ツリーのため）。

## scripts/ticket_state.py

```
python -I .claude/skills/codex-handoff/scripts/ticket_state.py hold  <票.md> --last "claude（<セッション名>）" [--note-file <追記するMarkdown>]
python -I .claude/skills/codex-handoff/scripts/ticket_state.py claim <票.md> --session "<セッション名>" --edit "<予約する編集範囲>" --res "<共有資源>" [--base <commit>]
python -I .claude/skills/codex-handoff/scripts/ticket_state.py done  <票.md> --last "claude（<セッション名>）" [--note-file <追記するMarkdown>]
```

- 管理欄の「状態」から「最終担当」の直前までを書き換える。`--note-file` の中身は票の末尾に追記する。
- 日付は実行日。担当ツールは、`claim` ではclaude、`hold`・`done` ではなしになる。
