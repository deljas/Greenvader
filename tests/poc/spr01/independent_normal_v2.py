"""Independent frozen normal-v2 pixel checks, no Godot or asset mutation."""
from pathlib import Path
import hashlib
import json
from PIL import Image

REPO=Path(__file__).resolve().parents[3]
ROOT=REPO/'assets/concepts/spr01/walk-normal-v2'
OUT=REPO/'evidence/spr01/walk-normal-v2/independent'
STATIC=ROOT.parent/'four-directions-v2'
checks=[]; hashes={}; images={}; notes=[]
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def check(name,ok,detail=None): checks.append(dict(name=name,status='PASS' if ok else 'FAIL',detail=detail))
def components(points):
    pending=set(points); groups=[]
    while pending:
        seen={pending.pop()}; todo=list(seen)
        while todo:
            x,y=todo.pop()
            for dx,dy in [(-1,-1),(0,-1),(1,-1),(-1,0),(1,0),(-1,1),(0,1),(1,1)]:
                q=(x+dx,y+dy)
                if q in pending: pending.remove(q); seen.add(q); todo.append(q)
        groups.append(len(seen))
    return groups
pal={k:tuple(v) for k,v in json.loads((ROOT/'palette.json').read_text()).items()}
manifest=json.loads((ROOT/'manifest.json').read_text()); sheet=Image.open(ROOT/'sheet.png')
contact=Image.open(ROOT/'contact-sheet.png'); gif=Image.open(ROOT/'preview.gif')
for ri,d in enumerate(['down','left','right','up']):
    source=Image.open(STATIC/(d+'.png')); contacts=[]; hand_diffs=[]
    for f,dy in enumerate([0,1,0,1]):
        path=ROOT/f'{d}-{f}.png'; im=Image.open(path); images[d,f]=im; colors=set(im.getdata())
        rows=(ROOT/f'grid-{d}-{f}.txt').read_text().splitlines()
        check(path.name+'_format',im.size==(24,36) and im.mode=='RGBA' and {p[3] for p in colors}=={0,255} and colors<=set(pal.values()))
        check(path.name+'_grid',len(rows)==36 and all(len(row)==24 for row in rows) and list(im.getdata())==[pal[c] for row in rows for c in row])
        bodycolors={pal[k] for k in 'WISEM'}
        top=min(y for y in range(36) for x in range(24) if im.getpixel((x,y)) in bodycolors)
        check(path.name+'_body_1px',top==15+dy and all(im.getpixel((x,y+dy))==source.getpixel((x,y)) for y in range(18,24) for x in range(8,16)),top)
        face={(x,y) for y in range(36) for x in range(24) if im.getpixel((x,y)) in {pal['E'],pal['M']}}
        original_face={(x,y+dy) for y in range(36) for x in range(24) if source.getpixel((x,y)) in {pal['E'],pal['M']}}
        check(path.name+'_face_1px',face==original_face)
        eyes={x:[y for y in range(36) if im.getpixel((x,y))==pal['E']] for x in range(24)}; eyes={x:v for x,v in eyes.items() if v}
        check(path.name+'_eyes',not eyes if d=='up' else len(eyes)==2 and all(len(v)==2 and v[1]==v[0]+1 for v in eyes.values()))
        bbox=im.getbbox(); support=[x for x in range(24) if im.getpixel((x,33))[3]]
        contacts.append(sum(support)/len(support) if support else None)
        check(path.name+'_ground',bool(support) and bbox[3]==34 and 0<bbox[0]<bbox[2]<24 and 0<bbox[1])
        opaque={(x,y) for y in range(36) for x in range(24) if im.getpixel((x,y))[3]}
        groups=components(opaque)
        check(path.name+'_attached',len(groups)==1,groups)
        green={(x,y-dy) for y in range(36) for x in range(24) if im.getpixel((x,y)) in {pal[k] for k in 'LGH'}}
        original_green={(x,y) for y in range(36) for x in range(24) if source.getpixel((x,y)) in {pal[k] for k in 'LGH'}}
        if f: check(path.name+'_relative_leaf_sway',green!=original_green)
        if f==0: check(d+'_idle_bytes',path.read_bytes()==(STATIC/(d+'.png')).read_bytes())
        m=manifest['directions'][ri]['frames'][f]; rect=[24*f,36*ri,24,36]
        check(path.name+'_sheet_manifest',sheet.crop((rect[0],rect[1],rect[0]+24,rect[1]+36)).tobytes()==im.tobytes() and m['rect']==rect and m['anchor_xy']==[12,34] and m['nominal_body_y_offset_px']==dy and m['sha256']==sha(path))
        bad=0
        for y in range(36):
            for x in range(24):
                p=im.getpixel((x,y)); c=p[:3] if p[3] else (39,44,45); ox,oy=80+108*f,32+160*ri
                bad+=contact.crop((ox+x*4,oy+y*4,ox+(x+1)*4,oy+(y+1)*4)).getcolors()!=[(16,c)]
        check(path.name+'_contact',bad==0)
    a,b=images[d,1],images[d,3]
    for xs in [range(1,6),range(16,23)]:
        hand_diffs.append(sum(a.getpixel((x,y))!=b.getpixel((x,y)) for y in range(23,31) for x in xs))
    check(d+'_hands_alternate_at_equal_body_height',all(n>0 for n in hand_diffs),hand_diffs)
    check(d+'_alternating_contact',contacts[1]<12<contacts[3],contacts)
check('metadata',manifest['fps']==8 and manifest['loop']==True and manifest['foot_anchor_xy']==[12,34] and manifest['cycle_ms']==500 and sheet.size==(96,144))
durations=[]; bad=0
for f in range(gif.n_frames):
    gif.seek(f); durations.append(gif.info['duration']); page=gif.convert('RGB')
    for ri,d in enumerate(['down','left','right','up']):
        for s,o in [(6,(16+160*ri,32)),(2,(64+160*ri,296))]:
            for y in range(36):
                for x in range(24):
                    p=images[d,f].getpixel((x,y)); c=p[:3] if p[3] else (39,44,45)
                    bad+=page.crop((o[0]+x*s,o[1]+y*s,o[0]+(x+1)*s,o[1]+(y+1)*s)).getcolors()!=[(s*s,c)]
check('gif_decoded_exact',gif.n_frames==4 and gif.info.get('loop')==0 and durations==[120,130,120,130] and bad==0,dict(durations=durations,bad_cells=bad))
check('no_mirror',all(any(images['left',f].getpixel((23-x,y))!=images['right',f].getpixel((x,y)) for y in range(36) for x in range(24)) for f in range(4)))
runtime=REPO/'assets/sprites/poc/player'
check('runtime_normal_bytes',(runtime/'walk-normal.png').read_bytes()==(ROOT/'sheet.png').read_bytes())
rm=json.loads((runtime/'manifest.json').read_text())
check('runtime_manifest',rm['source_directories']['normal']=='assets/concepts/spr01/walk-normal-v2/' and rm['fps']==8 and rm['foot_anchor']==[12,34])
prior=json.loads((REPO/'evidence/spr01/independent/walk-compare-assets.json').read_text())
for name,h in prior['hashes'].items(): check('preserve_v1/'+name,sha(ROOT.parent/'walk-normal-v1'/name)==h)
baseline=json.loads((REPO/'evidence/spr01/independent/walk-compare-target-before.json').read_text())['expected']
for name,h in baseline.items():
    if name.startswith('scripts/') or name.endswith('/idle.png') or name.endswith('/walk-hop.png'):
        check('preserve_code_idle_hop/'+name,sha(REPO/name)==h)
check('preserve_16',sha(ROOT.parent/'front-pixel-v1/front-16x24.png')=='f188d843f64c3d2c54f1442deff625ddee920d6af14b59c64a8ec422976efffc')
for p in ROOT.iterdir():
    if p.is_file() and p.name!='production-note.md':hashes[p.name]=sha(p)
hashes['runtime/walk-normal.png']=sha(runtime/'walk-normal.png'); hashes['runtime/manifest.json']=sha(runtime/'manifest.json')
report=dict(checks=checks,hashes=hashes,counts={s:sum(c['status']==s for c in checks) for s in ['PASS','FAIL']},independent_gpu_rerun=False)
OUT.mkdir(parents=True,exist_ok=True); (OUT/'assets-results.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print(report['counts'])
for c in checks:
    if c['status']=='FAIL': print(c)
raise SystemExit(1 if report['counts']['FAIL'] else 0)
