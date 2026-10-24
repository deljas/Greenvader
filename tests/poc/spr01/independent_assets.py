"""Read-only checks of frozen normal-walk assets; writes only independent evidence."""
from pathlib import Path
import hashlib
import json
import re
from PIL import Image

REPO = Path(__file__).resolve().parents[3]
ROOT = REPO / 'assets/concepts/spr01/walk-normal-v1'
STATIC = ROOT.parent / 'four-directions-v2'
OUT = REPO / 'evidence/spr01/independent/walk-compare-assets.json'
checks = []
hashes = {}

def check(name, ok, detail=None):
    checks.append(dict(name=name, status='PASS' if ok else 'FAIL', detail=detail))

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

palette = {k: tuple(v) for k, v in json.loads((ROOT/'palette.json').read_text()).items()}
manifest = json.loads((ROOT/'manifest.json').read_text())
sheet = Image.open(ROOT/'sheet.png')
contact = Image.open(ROOT/'contact-sheet.png')
gif = Image.open(ROOT/'preview.gif')
imgs = {}
details = []
for row, direction in enumerate(['down','left','right','up']):
    neutral = Image.open(STATIC/(direction+'.png'))
    support_centres = []
    for frame in range(4):
        path = ROOT/f'{direction}-{frame}.png'
        hashes[path.name] = sha(path)
        im = Image.open(path)
        imgs[direction,frame] = im
        colors = set(im.getdata())
        rows = (ROOT/f'grid-{direction}-{frame}.txt').read_text().splitlines()
        check(path.name+'_format', im.size==(24,36) and im.mode=='RGBA' and {p[3] for p in colors}=={0,255} and colors<=set(palette.values()))
        check(path.name+'_grid', len(rows)==36 and all(len(r)==24 for r in rows) and list(im.getdata())==[palette[c] for r in rows for c in r])
        check(path.name+'_body_fixed', all(im.getpixel((x,y))==neutral.getpixel((x,y)) for y in range(15,32) for x in range(24)))
        bbox=im.getbbox()
        check(path.name+'_inside_ground', 0<bbox[0]<bbox[2]<24 and 0<bbox[1]<bbox[3]<36 and bbox[3]==34)
        support=[x for x in range(24) if im.getpixel((x,33))[3]]
        support_centres.append(sum(support)/len(support) if support else None)
        eyes={x: [y for y in range(36) if im.getpixel((x,y))==palette['E']] for x in range(24)}
        eyes={x:ys for x,ys in eyes.items() if ys}
        eye_ok=(not eyes and palette['M'] not in colors) if direction=='up' else len(eyes)==2 and all(len(v)==2 and v[1]==v[0]+1 for v in eyes.values())
        check(path.name+'_eyes', eye_ok)
        item=manifest['directions'][row]['frames'][frame]
        rect=[frame*24,row*36,24,36]
        check(path.name+'_sheet_manifest', sheet.crop((rect[0],rect[1],rect[0]+24,rect[1]+36)).tobytes()==im.tobytes() and item['rect']==rect and item['anchor_xy']==[12,34] and item['sha256']==hashes[path.name])
        for y in range(36):
            for x in range(24):
                p=im.getpixel((x,y)); expected=p[:3] if p[3] else (39,44,45)
                ox,oy=80+frame*108,32+row*160
                assert contact.crop((ox+x*4,oy+y*4,ox+(x+1)*4,oy+(y+1)*4)).getcolors()==[(16,expected)]
        if frame==0:
            check(direction+'_f0_static_bytes', path.read_bytes()==(STATIC/(direction+'.png')).read_bytes())
        else:
            check(path.name+'_leaf_changes', im.crop((0,0,24,15)).tobytes()!=neutral.crop((0,0,24,15)).tobytes())
    check(direction+'_alternating_contact', support_centres[1]<12<support_centres[3], support_centres)
    details.append(dict(direction=direction, support_centres=support_centres))
check('metadata', manifest['fps']==8 and manifest['loop']==True and manifest['cycle_ms']==500 and manifest['foot_anchor_xy']==[12,34] and sheet.size==(96,144))
durations=[]
bad_cells=0
for frame in range(gif.n_frames):
    gif.seek(frame); durations.append(gif.info['duration']); page=gif.convert('RGB')
    for row,d in enumerate(['down','left','right','up']):
        im=imgs[d,frame]
        for scale,origin in [(6,(16+row*160,32)),(2,(64+row*160,296))]:
            for y in range(36):
                for x in range(24):
                    p=im.getpixel((x,y)); expected=p[:3] if p[3] else (39,44,45)
                    box=(origin[0]+x*scale,origin[1]+y*scale,origin[0]+(x+1)*scale,origin[1]+(y+1)*scale)
                    bad_cells+=page.crop(box).getcolors()!=[(scale*scale,expected)]
check('gif_decoded_cells_timing', gif.n_frames==4 and durations==[120,130,120,130] and gif.info.get('loop')==0 and bad_cells==0, dict(durations=durations,bad_cells=bad_cells))
check('no_direction_mirror', all(any(imgs['left',f].getpixel((23-x,y))!=imgs['right',f].getpixel((x,y)) for y in range(36) for x in range(24)) for f in range(4)))
for previous, folder in [('walk-v1-review.md','walk-v1'),('four-directions-v2-review.md','four-directions-v2')]:
    text=(OUT.parent/previous).read_text(encoding='utf-8')
    for name,expected in re.findall(r'\| ([^|]+?) \| `([a-f0-9]{64})` \|',text):
        candidate=ROOT.parent/folder/name
        if candidate.exists():
            check('preserve_'+folder+'/'+name, sha(candidate)==expected)
check('preserve_16', sha(ROOT.parent/'front-pixel-v1/front-16x24.png')=='f188d843f64c3d2c54f1442deff625ddee920d6af14b59c64a8ec422976efffc')
for p in ROOT.iterdir():
    if p.is_file() and p.name!='production-note.md': hashes[p.name]=sha(p)
report=dict(checks=checks, details=details, hashes=hashes, counts={s:sum(c['status']==s for c in checks) for s in ['PASS','FAIL']})
OUT.write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print(json.dumps(report['counts']))
for c in checks:
    if c['status']=='FAIL': print(c)
raise SystemExit(1 if report['counts']['FAIL'] else 0)
