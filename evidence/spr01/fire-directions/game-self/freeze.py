"""Record this subtask's fixed target and compare the parent's protected baseline."""
from pathlib import Path
import difflib
import hashlib
import json

ROOT = Path(__file__).resolve().parents[4]
OUT = Path(__file__).parent
scripts = [ROOT / "scripts/poc" / name for name in ("poc_actor.gd", "poc_fire_action.gd", "poc_main.gd", "play/poc_play_view.gd")]
targets = scripts + [ROOT / "assets/sprites/poc/player/manifest.json"]
targets += sorted((ROOT / "assets/sprites/poc/player/fire-directions-v1").glob("*"))
targets += sorted((ROOT / "tests").glob("spr01_fire_directions*"))
hashes = {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in targets if p.is_file()}
(OUT / "target-hashes.json").write_text(json.dumps({"head": "151a53f20255489ef08481e2a353258cd8ac559c", "files": hashes}, indent=2) + "\n", encoding="utf-8")
baseline = json.loads((OUT.parent / "preserved-before.json").read_text(encoding="utf-8-sig"))
checks = [{"path": e["path"], "ok": Path(e["path"]).exists() and hashlib.sha256(Path(e["path"]).read_bytes()).hexdigest() == e["sha256"]} for e in baseline]
(OUT / "preserved-check.json").write_text(json.dumps({"total": len(checks), "failures": sum(not e["ok"] for e in checks), "checks": checks}, indent=2) + "\n", encoding="utf-8")
patch = []
for p in scripts:
    before = OUT.parent / "parent-before" / (p.name + ".txt")
    patch.extend(difflib.unified_diff(before.read_text(encoding="utf-8-sig").splitlines(True), p.read_text(encoding="utf-8-sig").splitlines(True), fromfile="before/" + p.relative_to(ROOT).as_posix(), tofile=p.relative_to(ROOT).as_posix()))
(OUT / "directions-change.patch").write_text("".join(patch), encoding="utf-8", newline="\n")
print(f"Frozen {len(hashes)} files; protected {len(checks)} files, {sum(not e['ok'] for e in checks)} mismatches")
