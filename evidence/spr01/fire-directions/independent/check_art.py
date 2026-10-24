"""Independent SPR-01 acceptance checks; read-only to product assets."""
from pathlib import Path
import hashlib, json
from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parents[4]
OUT = Path(__file__).resolve().parent
SRC = ROOT / 'assets/concepts/spr01/fire-directions-v1'
OLD = ROOT / 'assets/concepts/spr01/fire-front-v3'
checks = []
def check(name, ok, detail=None):
    checks.append(dict(name=name,status='PASS' if ok else 'FAIL',detail=detail))
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def im(p): return Image.open(p).convert('RGBA')
def pixels(p): return im(p).tobytes()
def components(points):
    points=set(points); out=[]
    while points:
        todo=[points.pop()]; group=[]
        while todo:
            x,y=todo.pop(); group.append((x,y))
            for n in [(x-1,y),(x+1,y),(x,y-1),(x,y+1)]:
                if n in points: points.remove(n); todo.append(n)
        out.append(group)
    return out

m=json.loads((SRC/'manifest.json').read_text(encoding='utf-8-sig'))
palette=json.loads((OLD/'character-palette.json').read_text())
allowed={tuple(v) for v in palette.values()}
eye=tuple(palette['E']); mouth=tuple(palette['M'])
check('native_contract',m['character_size']==[24,36] and m['foot_anchor_xy']==[12,34] and m['directions']==['down','left','right','up'])
for kind,expected,release in [('seed',[66,100,100,134],66),('water',[80,100,100,120,100,120,180],400)]:
    a=m['actions'][kind]
    check(kind+'_timing',a['durations_ms']==expected and a['total_ms']==sum(expected) and a['release_events'][0]['time_ms']==release)
    sheet=im(SRC/a['character_sheet']); fx_sheet=im(SRC/a['formation_sheet'])
    check(kind+'_sheet_size',sheet.size==(len(expected)*24,144) and fx_sheet.size==sheet.size)
    frames={}
    for row,direction in enumerate(m['directions']):
        frames[direction]=[]
        entries=a['frames_by_direction'][direction]
        check(kind+'_'+direction+'_frame_count',len(entries)==len(expected))
        for i,f in enumerate(entries):
            p=SRC/f['character']['file']; picture=im(p); data=list(picture.getdata()); frames[direction].append(picture)
            rect=(i*24,row*36,(i+1)*24,(row+1)*36)
            check(f'{kind}_{direction}_{i}_native_palette_sheet',picture.size==(24,36) and set(data)<=allowed and picture.tobytes()==sheet.crop(rect).tobytes())
            fx=im(SRC/f['formation_fx']['file'])
            check(f'{kind}_{direction}_{i}_formation',fx.size==(24,36) and {v[3] for v in fx.getdata()}<={0,255} and fx.tobytes()==fx_sheet.crop(rect).tobytes())
            eye_points=[(x,y) for y in range(36) for x in range(24) if picture.getpixel((x,y))==eye]
            if direction=='up':
                check(f'{kind}_{direction}_{i}_no_face',not eye_points and mouth not in data)
            elif kind=='seed' or i not in [2,3]:
                groups=components(eye_points)
                normal=len(groups)==2 and all(len(g)==2 and len({q[0] for q in g})==1 and abs(g[0][1]-g[1][1])==1 for g in groups)
                check(f'{kind}_{direction}_{i}_normal_eyes',normal,eye_points)
            else:
                check(f'{kind}_{direction}_{i}_squeezed_eyes',len(eye_points)==6,eye_points)
            if direction=='down':
                original=im(OLD/f'{kind}-character-{i}.png')
                diffs=[(x,y) for y in range(36) for x in range(24) if picture.getpixel((x,y))!=original.getpixel((x,y))]
                check(f'{kind}_down_{i}_preservation',not diffs if kind=='water' else all(7<=x<=16 and 23<=y<=26 for x,y in diffs),diffs)
                if kind=='water':
                    check(f'water_down_{i}_character_bytes_preserved',sha(p)==sha(OLD/f'water-character-{i}.png'))
                    check(f'water_down_{i}_formation_preserved',fx.tobytes()==pixels(OLD/f'water-formation-{i}.png') and sha(SRC/f['formation_fx']['file'])==sha(OLD/f'water-formation-{i}.png'))
        feet=[[(x,y,pic.getpixel((x,y))) for y in [32,33] for x in range(24)] for pic in frames[direction]]
        check(kind+'_'+direction+'_planted_feet',all(x==feet[0] for x in feet))
    check(kind+'_independently_authored_sides',all(ImageOps.mirror(l).tobytes()!=r.tobytes() for l,r in zip(frames['left'],frames['right'])))
    check(kind+'_projectile_preserved',sha(SRC/a['projectile']['file'])==sha(OLD/f'{kind}-projectile.png'))
    for direction,xy in a['release_events'][0]['socket_by_direction'].items():
        check(kind+'_'+direction+'_socket_native',len(xy)==2 and all(isinstance(v,int) for v in xy) and 0<=xy[0]<24 and 0<=xy[1]<36,xy)
runtime=ROOT/'assets/sprites/poc/player/fire-directions-v1'
copies=[p for p in runtime.rglob('*') if p.is_file() and not p.name.endswith('.import')]
check('runtime_copy_identical',bool(copies) and all((SRC/p.relative_to(runtime)).exists() and sha(p)==sha(SRC/p.relative_to(runtime)) for p in copies),len(copies))
baseline=json.loads((OUT.parent/'preserved-before.json').read_text())
bad=[r['path'] for r in baseline if not Path(r['path']).exists() or sha(Path(r['path']))!=r['sha256']]
check('preserved_baseline',not bad,dict(total=len(baseline),mismatches=bad))
result=dict(checks=checks,pass_count=sum(c['status']=='PASS' for c in checks),fail_count=sum(c['status']=='FAIL' for c in checks))
(OUT/'art-results.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({k:v for k,v in result.items() if k!='checks'}))
print(json.dumps([c for c in checks if c['status']=='FAIL'],ensure_ascii=False))
