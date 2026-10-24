"""Copy only selected delivered models; source delivery remains read-only."""
from pathlib import Path
import hashlib
import json
import shutil
import struct

ROOT = Path(__file__).resolve().parents[2]
SOURCE = Path('C:/godot/greenvader_asset_deliveries')
TARGET = ROOT / 'assets/models/delivery_showcase'
SELECTED = {'BLD':[7,38,79,123], 'VIN':[7,32,47,60], 'MOS':[3,12,24,35],
            'TRE':[1,27,54,74], 'GND':[9,36,59,77], 'PRP':[1,41,75,121]}
index = {e['asset_id']: e for e in json.loads((SOURCE/'index/assets.json').read_text('utf-8-sig'))}
assets = []
for category, numbers in SELECTED.items():
    for number in numbers:
        asset_id = f'{category}-{number:03d}'
        entry = index[asset_id]
        folder = SOURCE/entry['folder']
        destination = TARGET/asset_id
        destination.mkdir(parents=True, exist_ok=True)
        metadata = json.loads((folder/'metadata.json').read_text('utf-8-sig'))
        glb = folder/entry['glb']
        # glTF embedded image bufferViews need no separate image; retain declared
        # original PNGs as delivery provenance and for any external URI.
        raw = glb.read_bytes()
        chunk_length, chunk_type = struct.unpack_from('<II', raw, 12)
        assert chunk_type == 0x4e4f534a
        document = json.loads(raw[20:20+chunk_length])
        references = metadata.get('external_textures', [])[:]
        references += [im['uri'] for im in document.get('images',[]) if 'uri' in im and not im['uri'].startswith('data:')]
        files = []
        for relative in dict.fromkeys([entry['glb'], 'metadata.json']+references):
            src = (folder/relative).resolve()
            assert src.is_relative_to(folder.resolve())
            dst = destination/relative
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(src,dst)
            sha = hashlib.sha256(src.read_bytes()).hexdigest()
            assert sha == hashlib.sha256(dst.read_bytes()).hexdigest()
            files.append({'source':str(src), 'copy':str(dst.relative_to(ROOT)).replace('\\','/'), 'sha256':sha})
        assets.append({'id':asset_id,'category':category,'name':entry['name'],
                       'scene':f'res://assets/models/delivery_showcase/{asset_id}/{entry["glb"]}',
                       'metadata':f'res://assets/models/delivery_showcase/{asset_id}/metadata.json',
                       'source_folder':str(folder),'files':files})
assert len(assets)==24 and len({a['id'] for a in assets})==24
(TARGET/'manifest.json').write_text(json.dumps({'source':str(SOURCE),'assets':assets},ensure_ascii=False,indent=2)+'\n','utf-8')
print(f'Copied {len(assets)} models, {sum(len(a["files"]) for a in assets)} files; all SHA256 match.')
