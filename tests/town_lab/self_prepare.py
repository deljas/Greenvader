"""Preserve earlier labs, then copy the minimum town model delivery set."""
from pathlib import Path
import hashlib
import json
import shutil
import struct

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT/'evidence/town-lab/self'
OUT.mkdir(parents=True,exist_ok=True)
baseline = OUT/'protected-baseline.json'
if not baseline.exists():
    protected = [ROOT/'project.godot']
    for group in ['greening_map','vegetation_lab','asset_showcase','vine_compare','render_study_3d']:
        protected += list((ROOT/'scripts'/group).rglob('*'))
    protected += [ROOT/'scenes'/f'{s}.tscn' for s in ['greening_map','vegetation_lab','asset_showcase','vine_compare','sprite_shadow_lab']]
    for group in ['ruin_house','delivery_showcase']:
        protected += list((ROOT/'assets/models'/group).rglob('*'))
    baseline.write_text(json.dumps([{'path':str(p.relative_to(ROOT)).replace('\\','/'),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in protected if p.is_file()],indent=2)+'\n','utf-8')
source=Path('C:/godot/greenvader_asset_deliveries')
index={e['asset_id']:e for e in json.loads((source/'index/assets.json').read_text('utf-8-sig'))}
ids=['BLD-007','BLD-019','BLD-038','BLD-046','BLD-079','BLD-091','BLD-123',
     'PRP-001','PRP-005','PRP-012','PRP-017','PRP-034','PRP-041','PRP-075','TRE-001']
entries=[]
for id_ in ids:
    e=index[id_];folder=source/e['folder'];target=ROOT/'assets/models/town_lab'/id_
    target.mkdir(parents=True,exist_ok=True)
    meta=json.loads((folder/'metadata.json').read_text('utf-8-sig'))
    raw=(folder/e['glb']).read_bytes();length,_=struct.unpack_from('<II',raw,12)
    gltf=json.loads(raw[20:20+length]); refs=meta.get('external_textures',[])[:]
    refs += [im['uri'] for im in gltf.get('images',[]) if 'uri' in im and not im['uri'].startswith('data:')]
    files=[]
    for relative in dict.fromkeys([e['glb'],'metadata.json']+refs):
        src=(folder/relative).resolve();assert src.is_relative_to(folder.resolve())
        dst=target/relative;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(src,dst)
        sha=hashlib.sha256(src.read_bytes()).hexdigest();assert hashlib.sha256(dst.read_bytes()).hexdigest()==sha
        files.append({'source':str(src),'copy':str(dst.relative_to(ROOT)).replace('\\','/'),'sha256':sha})
    entries.append({'id':id_,'name':e['name'],'scene':f'res://assets/models/town_lab/{id_}/{e["glb"]}',
                    'metadata':meta,'source':str(folder),'files':files})
(ROOT/'assets/models/town_lab/manifest.json').write_text(json.dumps(entries,ensure_ascii=False,indent=2)+'\n','utf-8')
print('Protected:',len(json.loads(baseline.read_text('utf-8'))),'models:',len(entries),'copied files:',sum(len(e['files']) for e in entries))
