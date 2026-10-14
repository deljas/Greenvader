"""One-off ENV-001 static evidence; never executes Claude or Godot."""
import hashlib
import json
import re
import argparse
from pathlib import Path

root = Path(__file__).resolve().parents[3]
out = Path(__file__).resolve().parent
results = []
parser = argparse.ArgumentParser()
parser.add_argument("--phase", choices=["review", "completed"], default="review")
phase = parser.parse_args().phase

def check(condition, label, details=None):
    results.append(dict(result="PASS" if condition else "FAIL", label=label, details=details))

files = [root / name for name in ["AGENTS.md", "TASK_TEMPLATE.md", "README.md", "START_PROMPT.md", "CLAUDE.md", ".gitignore"]]
files += sorted((root / "tasks").glob("*.md"))
files += [root / ".claude/settings.json", root / ".claude/README.md", root / ".claude/START_PROMPT.md"]
files += sorted((root / ".claude/agents").glob("*.md"))
manifest = [{"path": str(p.relative_to(root)), "sha256": hashlib.sha256(p.read_bytes()).hexdigest()} for p in files]
(out / "source-manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")

settings = json.loads((root / ".claude/settings.json").read_text(encoding="utf-8-sig"))
check(settings == {"model": "opus"}, "JSON parses; main opus; no extra permission/hook configuration", settings)

expected = {"green-designer": "opus", "green-implementer": "sonnet", "green-verifier": "sonnet", "green-documenter": "haiku"}
names = []
for p in sorted((root / ".claude/agents").glob("*.md")):
    text = p.read_text(encoding="utf-8-sig")
    match = re.match(r"\A---\r?\n(.*?)\r?\n---\r?\n", text, re.S)
    check(match is not None, p.name + " frontmatter delimiters")
    if not match:
        continue
    # These files use only one-line plain YAML scalar mappings. Validate that
    # exact subset; this is not a general YAML parser or Claude's loader.
    fields = {}
    for line in match[1].splitlines():
        item = re.fullmatch(r"([A-Za-z][A-Za-z0-9]*): ([^\r\n]+)", line)
        if not item:
            raise ValueError("Outside validated YAML scalar subset: " + line)
        key, value = item.groups()
        if key in fields or value[0] in "{}[]&*!|>'\"%@`" or re.search(r":\s|\s#", value):
            raise ValueError("Duplicate or unsupported YAML scalar: " + line)
        fields[key] = value
    check(set(fields) == {"name", "description", "model", "tools", "disallowedTools"}, p.name + " supported plain YAML fields", fields)
    name = fields.get("name")
    names.append(name)
    check(fields.get("model") == expected.get(name) and name in expected, p.name + " requested model")
    tools = {t.strip() for t in fields["tools"].split(",")}
    denied = {t.strip() for t in fields["disallowedTools"].split(",")}
    check("Agent" in denied and "Agent" not in tools, p.name + " denies child delegation")
    if name == "green-designer":
        check(tools == {"Read", "Grep", "Glob"}, "designer tools read-only")
    if name == "green-documenter":
        check("Bash" not in tools and "Bash" in denied, "documenter has no shell")
check(set(names) == set(expected) and len(names) == 4, "four distinct agent names")

task_ids = []
for p in sorted((root / "tasks").glob("*.md")):
    if p.name == "README.md":
        continue
    text = p.read_text(encoding="utf-8-sig")
    fields = dict(re.findall(r"^- ([^:\n]+): (.+)$", text, re.M))
    needed = {"ID", "状態", "担当ツール", "担当セッション", "更新日", "予約中の編集範囲", "予約中の共有資源", "最終担当"}
    check(needed <= set(fields), p.name + " management fields present")
    task_ids.append(fields.get("ID"))
    active = p.name == "ENV-001.md" and phase == "review"
    # The shared workflow retains the owner while a frozen implementation awaits review.
    expected_states = {"作業中(codex)", "検証待ち"} if active else {"完了"} if p.name in {"ENV-001.md", "P0_BASE.md", "P0_ART.md"} else {"未着手"}
    check(fields.get("状態") in expected_states, p.name + " truthful current state", fields.get("状態"))
    if active:
        check(fields.get("担当ツール") == "codex" and fields.get("担当セッション") not in {"なし", None}, p.name + " active owner identified")
    else:
        check(all(fields.get(k) == "なし" for k in {"担当ツール", "担当セッション", "予約中の編集範囲", "予約中の共有資源"}), p.name + " reservations released or unclaimed")
check(len(task_ids) == 9 and len(set(task_ids)) == 9, "one unique task ID per nine task files")

broken = []
for p in files:
    if p.suffix != ".md":
        continue
    for target in re.findall(r"\[[^\]]*\]\(([^)]+)\)", p.read_text(encoding="utf-8-sig")):
        if re.match(r"[a-z]+:", target, re.I) or target.startswith("#"):
            continue
        local = target.split("#", 1)[0].strip("<>")
        if local and not (p.parent / local).exists():
            broken.append({"source": str(p.relative_to(root)), "target": target})
check(not broken, "all local Markdown links resolve", broken)
start_prompt = (root / "START_PROMPT.md").read_text(encoding="utf-8-sig")
check("docs/green-invader/" not in start_prompt, "old nonexistent source path removed from Codex start prompt")

game = json.loads((root / "evidence/p0-art/self/source-manifest.json").read_text(encoding="utf-8-sig"))
game_checks = [{"path": e["Path"], "sha256": hashlib.sha256(Path(e["Path"]).read_bytes()).hexdigest().upper(), "expected": e["Hash"]} for e in game]
check(all(e["sha256"] == e["expected"] for e in game_checks), "all ten frozen P0-ART files preserved", game_checks)
(out / "checks.json").write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
print(json.dumps({"phase": phase, "checks": len(results), "failures": sum(r["result"] == "FAIL" for r in results)}, ensure_ascii=False))
raise SystemExit(1 if any(r["result"] == "FAIL" for r in results) else 0)
