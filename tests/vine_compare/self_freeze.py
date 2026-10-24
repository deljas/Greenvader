"""Freeze comparison-only sources and verify originals remain unchanged."""
from pathlib import Path
from collections import Counter
import hashlib
import json
import subprocess

root = Path(__file__).resolve().parents[2]
out = root/'evidence/vine-compare/self'
preserved = []
for name in ['parent-baseline.json','source-baseline.json']:
    entries = json.loads((root/'evidence/vine-compare'/name).read_text('utf-8-sig'))
    mismatches = []
    for entry in entries:
        path = Path(entry['path'])
        if not path.is_absolute(): path = root/path
        if hashlib.sha256(path.read_bytes()).hexdigest().lower()!=entry['sha256'].lower():
            mismatches.append(entry['path'])
    assert not mismatches, mismatches
    preserved.append({'baseline':name,'count':len(entries),'mismatches':mismatches})
(out/'preservation.json').write_text(json.dumps(preserved,indent=2)+'\n','utf-8')
paths = ['scripts/vine_compare/compare.gd','scripts/vine_compare/path_reveal.gd',
         'scenes/vine_compare.tscn','launchers/labs/run_vine_compare.bat',
         'launchers/README.md','tests/vine_compare/self_capture.gd',
         'tests/vine_compare/self_freeze.py']
snapshot = {'head':subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip(),
            'uncommitted':True,
            'files':[{'path':p,'sha256':hashlib.sha256((root/p).read_bytes()).hexdigest()} for p in paths]}
(out/'source-hashes.json').write_text(json.dumps(snapshot,indent=2)+'\n','utf-8')
results = json.loads((out/'results.json').read_text('utf-8'))
smoke = json.loads((out/'smoke.json').read_text('utf-8'))
print('Checks',Counter(r['status'] for r in results['results']))
print('Smoke',Counter(r['status'] for r in smoke))
print('Preserved',[(p['baseline'],p['count']) for p in preserved])
print('Frozen sources',len(paths))
