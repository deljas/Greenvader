"""Freeze town-only files and audit protected/source delivery hashes."""
from pathlib import Path
from collections import Counter
import hashlib
import json
import subprocess

root=Path(__file__).resolve().parents[2]
out=root/'evidence/town-lab/self'
baseline=json.loads((out/'protected-baseline.json').read_text('utf-8'))
for e in baseline:
    assert hashlib.sha256((root/e['path']).read_bytes()).hexdigest()==e['sha256'],e['path']
manifest=json.loads((root/'assets/models/town_lab/manifest.json').read_text('utf-8'))
copied=[]
for e in manifest:
    for f in e['files']:
        original=hashlib.sha256(Path(f['source']).read_bytes()).hexdigest()
        local=hashlib.sha256((root/f['copy']).read_bytes()).hexdigest()
        assert original==local==f['sha256'],f['copy']
        copied.append(f)
paths=[]
for directory in ['scripts/town_lab','assets/models/town_lab','tests/town_lab']:
    paths += [p for p in (root/directory).rglob('*') if p.is_file() and '__pycache__' not in str(p)]
paths += [root/'scenes/town_lab.tscn',root/'launchers/labs/run_town_lab.bat',root/'launchers/README.md']
snapshot={'head':subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip(),
          'uncommitted':True,'files':[{'path':str(p.relative_to(root)).replace('\\','/'),
          'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in paths]}
(out/'source-hashes.json').write_text(json.dumps(snapshot,indent=2)+'\n','utf-8')
(out/'preservation.json').write_text(json.dumps({'protected':len(baseline),'source_copies':len(copied),
                                              'mismatches':[]},indent=2)+'\n','utf-8')
results=json.loads((out/'results.json').read_text('utf-8'))
print('Final recorded observations',Counter(c['status'] for c in results['checks']))
print('Protected',len(baseline),'delivery copies',len(copied),'frozen',len(paths))
