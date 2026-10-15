"""Update the management block of a greenvader task ticket (tasks/*.md).

The canonical rules live in tasks/README.md; this only edits the block between
"- 状態:" and "- 最終担当:" and optionally appends a note at the end.
"""
import argparse
import datetime
import pathlib
import sys


def rewrite(path: pathlib.Path, block: str, last: str | None, base: str | None, note: str | None) -> None:
    text = path.read_text(encoding="utf-8")
    start = text.index("- 状態:")
    end = text.index("- 最終担当:")
    text = text[:start] + block + text[end:]
    if last:
        line_end = text.index("\n", text.index("- 最終担当:"))
        text = text[: text.index("- 最終担当:")] + f"- 最終担当: {last}" + text[line_end:]
    if base:
        anchor = text.index("\n", text.index("- 最終担当:")) + 1
        text = text[:anchor] + f"- 取得時の基準: {base}\n" + text[anchor:]
    if note:
        text = text.rstrip("\n") + "\n\n" + note.strip("\n") + "\n"
    path.write_text(text, encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["hold", "claim", "done"])
    parser.add_argument("ticket")
    parser.add_argument("--session", default="")
    parser.add_argument("--edit", default="")
    parser.add_argument("--res", default="")
    parser.add_argument("--base", default="")
    parser.add_argument("--last", default="")
    parser.add_argument("--note-file", default="")
    args = parser.parse_args()

    today = datetime.date.today().isoformat()
    if args.action == "claim":
        if not (args.session and args.edit and args.res):
            print("claim needs --session, --edit and --res", file=sys.stderr)
            return 2
        block = (
            "- 状態: 作業中(claude)\n- 担当ツール: claude\n"
            f"- 担当セッション: {args.session}\n- 更新日: {today}\n"
            f"- 予約中の編集範囲: {args.edit}\n- 予約中の共有資源: {args.res}\n"
        )
    else:
        state = "保留" if args.action == "hold" else "完了"
        block = (
            f"- 状態: {state}\n- 担当ツール: なし\n- 担当セッション: なし\n"
            f"- 更新日: {today}\n- 予約中の編集範囲: なし\n- 予約中の共有資源: なし\n"
        )
    note = pathlib.Path(args.note_file).read_text(encoding="utf-8") if args.note_file else None
    rewrite(pathlib.Path(args.ticket), block, args.last or None, args.base or None, note)
    print(f"{args.ticket}: {args.action}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
