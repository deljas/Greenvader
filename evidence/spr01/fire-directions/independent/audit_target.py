from pathlib import Path
import hashlib,json,difflib,subprocess
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parents[4]
OUT=Path(__file__).resolve().parent
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
frozen=json.loads((OUT.parent/'game-self/target-hashes.json').read_text())
bad=[p for p,h in frozen['files'].items() if sha(ROOT/p)!=h]
source=json.loads((ROOT/'evidence/spr01/fire-directions/asset-self/target-hashes.json').read_text())
source_files=source.get('files',source) if isinstance(source,dict) else {}
source_bad=[]
if isinstance(source_files,dict):
    for p,h in source_files.items():
        path=Path(p) if Path(p).is_absolute() else ROOT/p
        if sha(path)!=h:source_bad.append(p)
scripts=['scripts/poc/poc_actor.gd','scripts/poc/poc_fire_action.gd','scripts/poc/poc_main.gd','scripts/poc/play/poc_play_view.gd']
diff=[]
for script in scripts:
    before=(OUT.parent/'parent-before'/(Path(script).name+'.txt')).read_text(encoding='utf-8-sig').splitlines(keepends=True)
    after=(ROOT/script).read_text(encoding='utf-8-sig').splitlines(keepends=True)
    diff.extend(difflib.unified_diff(before,after,fromfile='before/'+script,tofile=script))
(OUT/'reviewed-change.patch').write_text(''.join(diff),encoding='utf-8')
imports=list((ROOT/'assets/sprites/poc/player/fire-directions-v1').glob('*.png.import'))
settings=['compress/mode=0','mipmaps/generate=false','process/fix_alpha_border=false','process/premult_alpha=false','process/size_limit=0','detect_3d/compress_to=0']
import_bad=[p.name for p in imports if not all(x in p.read_text() for x in settings)]
head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
status=subprocess.check_output(['git','status','--short'],cwd=ROOT,text=True)
(OUT/'git-status.txt').write_text(status,encoding='utf-8')
own={p:sha(ROOT/p) for p in frozen['files']}
for p in (ROOT/'assets/concepts/spr01/fire-directions-v1').rglob('*'):
    if p.is_file():own[p.relative_to(ROOT).as_posix()]=sha(p)
(OUT/'target-hashes.json').write_text(json.dumps(dict(head=head,files=own),indent=2),encoding='utf-8')
checks=[dict(name='frozen_runtime_and_code',status='PASS' if not bad else 'FAIL',detail=dict(total=len(frozen['files']),mismatches=bad)),dict(name='frozen_source',status='PASS' if source_files and not source_bad else 'FAIL',detail=dict(total=len(source_files),mismatches=source_bad)),dict(name='native_import_settings',status='PASS' if len(imports)==98 and not import_bad else 'FAIL',detail=dict(total=len(imports),mismatches=import_bad))]
(OUT/'audit-results.json').write_text(json.dumps(dict(head=head,checks=checks,source_manifest_shape=list(source)[:5],source_check_count=len(source_files),source_mismatches=source_bad),indent=2),encoding='utf-8')
names=['water_left_hold','water_right_hold','water_right_release','seed_up_release']
board=Image.new('RGB',(256*4,280),(35,43,43));draw=ImageDraw.Draw(board)
for i,n in enumerate(names):
    picture=Image.open(OUT/(n+'.png')).convert('RGB')
    board.paste(picture.crop((288,150,352,214)).resize((256,256),Image.Resampling.NEAREST),(i*256,24))
    draw.text((i*256+3,5),n,fill='white')
board.save(OUT/'gpu-contact4x.png')
print(json.dumps(checks))
