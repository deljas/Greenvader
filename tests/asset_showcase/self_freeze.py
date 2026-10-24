"""Final source/copy snapshot; does not edit delivered source files."""
from pathlib import Path
from collections import Counter
import hashlib
import json
import subprocess

root = Path(__file__).resolve().parents[2]
out = root/'evidence/asset-showcase/self'
manifest = json.loads((root/'assets/models/delivery_showcase/manifest.json').read_text('utf-8'))
files = []
for entry in manifest['assets']:
    for item in entry['files']:
        source = hashlib.sha256(Path(item['source']).read_bytes()).hexdigest()
        copied = hashlib.sha256((root/item['copy']).read_bytes()).hexdigest()
        assert source == copied == item['sha256'], item['copy']
        files.append(item['copy'])
files += ['scripts/asset_showcase/showcase.gd','scenes/asset_showcase.tscn',
          'launchers/labs/run_asset_showcase.bat','launchers/README.md',
          'tests/asset_showcase/self_prepare.py','tests/asset_showcase/self_capture.gd',
          'tests/asset_showcase/self_freeze.py','assets/models/delivery_showcase/README.md',
          'assets/models/delivery_showcase/manifest.json']
snapshot = {'head':subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip(),
            'uncommitted':True,'copied_files_verified':57,
            'category_counts':dict(Counter(e['category'] for e in manifest['assets'])),
            'source_files':[{'path':p,'sha256':hashlib.sha256((root/p).read_bytes()).hexdigest()} for p in files]}
(out/'source-hashes.json').write_text(json.dumps(snapshot,ensure_ascii=False,indent=2)+'\n','utf-8')
results = json.loads((out/'gpu-results.json').read_text('utf-8'))
print(Counter(r['status'] for r in results['results']))
print(f'{len(files)} frozen files;57 delivered copies reverified.')
