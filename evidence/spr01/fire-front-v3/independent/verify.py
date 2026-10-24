"""Independent read-only verification of front-fire native layers/timeline/GIF."""
from pathlib import Path
from PIL import Image
import hashlib,json,re,subprocess
REPO=Path(__file__).resolve().parents[4]
ROOT=REPO/'assets/concepts/spr01/fire-front-v3'
OUT=Path(__file__).resolve().parent
checks=[]; hashes={}; samples={}
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def check(name,ok,detail=None):checks.append(dict(name=name,status='PASS' if ok else 'FAIL',detail=detail))
def read_rows(name):return (ROOT/name).read_text().splitlines()
manifest=json.loads((ROOT/'manifest.json').read_text())
data=json.loads((ROOT/'preview-data.json').read_text())
html=(ROOT/'comparison.html').read_text(encoding='utf-8')
embedded=json.loads(re.search(r'<script id="data" type="application/json">(.*?)</script>',html,re.S).group(1))
pal={k:tuple(v) for k,v in json.loads((ROOT/'character-palette.json').read_text()).items()}
fxpal={k:tuple(v) for k,v in json.loads((ROOT/'fx-palette.json').read_text()).items()}
source=Image.open(ROOT.parent/'four-directions-v2/down.png')
check('idle_bytes',(ROOT/'idle.png').read_bytes()==(ROOT.parent/'four-directions-v2/down.png').read_bytes())
check('source_palette',pal=={k:tuple(v) for k,v in json.loads((ROOT.parent/'four-directions-v2/palette.json').read_text()).items()})
expected_times={'seed':([66,100,100,134],66),'water':([80,100,100,120,100,120,180],400)}
images={}
for action,(durations,release) in expected_times.items():
    a=manifest['actions'][action]; total=sum(durations)
    check(action+'_time',a['durations_ms']==durations and a['total_ms']==total and a['release_events'][0]['time_ms']==release and len(a['frames'])==len(durations))
    elapsed=0
    for i,duration in enumerate(durations):
        f=a['frames'][i]; dy=([0,1,0,0] if action=='seed' else [0,0,-1,0,1,1,0])[i]
        check(f'{action}_{i}_boundaries',f['start_ms']==elapsed and f['end_ms']==elapsed+duration and f['duration_ms']==duration and f['body_y_offset_px']==dy)
        for layer,key,palette in [('character','character',pal),('formation','formation_fx',fxpal)]:
            p=ROOT/f'{action}-{layer}-{i}.png'; im=Image.open(p); images[action,layer,i]=im
            rows=read_rows(f'grid-{action}-{layer}-{i}.txt'); colors=set(im.getdata())
            check(p.name+'_pixels',im.size==(24,36) and im.mode=='RGBA' and {v[3] for v in colors}<={0,255} and colors<=set(palette.values()) and len(rows)==36 and all(len(r)==24 for r in rows) and list(im.getdata())==[palette[c] for r in rows for c in r])
            sheet=Image.open(ROOT/a['character_sheet' if layer=='character' else 'formation_sheet'])
            check(p.name+'_manifest_sheet',f[key]['file']==p.name and f[key]['rect']==[24*i,0,24,36] and f[key]['sha256']==sha(p) and sheet.size==(24*len(durations),36) and sheet.crop((24*i,0,24*(i+1),36)).tobytes()==im.tobytes())
            gridfield='character_grid' if layer=='character' else 'formation_grid'
            check(p.name+'_html_grid',data['actions'][action]['frames'][i][gridfield]==rows)
        im=images[action,'character',i]
        expected_face={(x,y+dy):source.getpixel((x,y)) for y in range(36) for x in range(24) if source.getpixel((x,y)) in {pal['E'],pal['M']}}
        actual_face={(x,y):im.getpixel((x,y)) for y in range(36) for x in range(24) if im.getpixel((x,y)) in {pal['E'],pal['M']}}
        closed=(action=='seed' and i==0) or (action=='water' and i in [2,3])
        released=(action=='seed' and i==1) or (action=='water' and i==4)
        eye_pixels={(x,y) for (x,y),c in actual_face.items() if c==pal['E']}
        mouth_pixels={(x,y) for (x,y),c in actual_face.items() if c==pal['M']}
        source_eyes={(x,y) for (x,y),c in expected_face.items() if c==pal['E']}
        if closed:
            left={p for p in eye_pixels if p[0]<12}; right=eye_pixels-left
            face_ok=all(len(g)>=2 and max(x for x,y in g)>min(x for x,y in g) for g in [left,right]) and eye_pixels!=source_eyes and len(mouth_pixels)==1
        elif released:
            face_ok=eye_pixels==source_eyes and len(mouth_pixels)>sum(c==pal['M'] for c in expected_face.values())
        else:face_ok=actual_face==expected_face
        check(f'{action}_{i}_expression_body',face_ok and all(im.getpixel((x,y+dy))==source.getpixel((x,y)) for y in range(18,24) for x in range(8,16)),dict(closed=closed,release_open=released,eye_pixels=len(eye_pixels),mouth_pixels=len(mouth_pixels)))
        check(f'{action}_{i}_feet',all(im.getpixel((x,y))==source.getpixel((x,y)) for y in (32,33) for x in range(24)) and im.getbbox()[3]==34)
        check(f'{action}_{i}_html_time',all(data['actions'][action]['frames'][i][k]==f[k] for k in ['start_ms','end_ms','duration_ms','body_y_offset_px']))
        elapsed+=duration
    projectile=Image.open(ROOT/a['projectile']['file']); images[action,'projectile',0]=projectile
    rows=read_rows(f'grid-{action}-projectile.txt')
    check(action+'_projectile_layer',projectile.size==(8,8) and projectile.mode=='RGBA' and set(projectile.getdata())<=set(fxpal.values()) and list(projectile.getdata())==[fxpal[c] for r in rows for c in r] and a['projectile']['sha256']==sha(ROOT/a['projectile']['file']))
    check(action+'_html_action',data['actions'][action]['release_ms']==release and data['actions'][action]['total_ms']==total and data['actions'][action]['projectile_grid']==rows)
check('water_formation_grows',sum(p[3]>0 for p in images['water','formation',1].getdata())>sum(p[3]>0 for p in images['water','formation',0].getdata()))
check('water_formation_separates',all(images['water','formation',i].getbbox() is None for i in [4,5,6]))
check('anchor_direction',manifest['foot_anchor_xy']==[12,34] and manifest['direction']=='down' and manifest['character_size']==[24,36])
check('html_static',embedded==data and 'imageSmoothingEnabled=false' in html and 'image-rendering:pixelated' in html and 't>=f.start_ms&&t<f.end_ms' in html and 't>=a.release_ms&&t<a.release_ms+data.trajectory.lifetime_ms' in html and 'requestAnimationFrame' in html and '更新周期に依存' in html and '__DATA__' not in html and 'fetch(' not in html)

def expected_panel(action,t):
    a=manifest['actions'][action]
    f=next((i for i,frame in enumerate(a['frames']) if frame['start_ms']<=t<frame['end_ms']),None)
    panel=Image.new('RGBA',(24,52),(39,44,45,255))
    body=Image.open(ROOT/'idle.png') if f is None else images[action,'character',f]
    panel.alpha_composite(body,(0,0))
    if f is not None:panel.alpha_composite(images[action,'formation',f],(0,0))
    ev=a['release_events'][0]; since=t-ev['time_ms']
    if 0<=since<manifest['preview_trajectory']['lifetime_ms']:
        projectile=images[action,'projectile',0]
        px=ev['socket_xy'][0]-4; py=ev['socket_xy'][1]+int(since*manifest['preview_trajectory']['speed_y_px_per_ms'])-4
        # All opaque projectile pixels are below the top boundary; crop to preview area.
        layer=Image.new('RGBA',(24,52)); layer.paste(projectile,(px,py)); panel.alpha_composite(layer)
    return panel.convert('RGB')

gif=Image.open(ROOT/'comparison.gif'); elapsed=0; bad=[]; intervals=[]
for i in range(gif.n_frames):
    gif.seek(i); interval=gif.info['duration']; intervals.append(interval); page=gif.convert('RGB')
    for col,action in enumerate(['seed','water']):
        for scale,t,origin in [(6,elapsed,(48+208*col,48)),(2,elapsed/4,(96+208*col,408))]:
            panel=expected_panel(action,t).resize((24*scale,52*scale),Image.Resampling.NEAREST)
            actual=page.crop((origin[0],origin[1],origin[0]+24*scale,origin[1]+52*scale))
            if panel.tobytes()!=actual.tobytes():bad.append([i,action,scale])
    elapsed+=interval
check('gif_decoded_timeline_pixels',gif.n_frames==200 and intervals==[20]*200 and elapsed==4000 and gif.info.get('loop')==0 and not bad,dict(frames=gif.n_frames,durations_ms=intervals,bad_panels=bad))
check('gif_approximation_declared',manifest['gif']['sampling_step_ms']==20 and manifest['gif']['release_ms']=={'seed':80,'water':400} and manifest['gif']['event_rounding']=='first sample at or after exact event')
# Changed requirements are taken from the v3 task, not copied from producer assertions.
v2=ROOT.parent/'fire-front-v2'
previous_manifest=json.loads((v2/'manifest.json').read_text())
check('seed_strict_time_double',manifest['actions']['seed']['durations_ms']==[n*2 for n in previous_manifest['actions']['seed']['durations_ms']] and manifest['actions']['seed']['release_events'][0]['time_ms']==2*previous_manifest['actions']['seed']['release_events'][0]['time_ms'])
for i in range(4):
    old=Image.open(v2/f'seed-character-{i}.png'); current=images['seed','character',i]
    outside_face=[(x,y) for y in range(36) for x in range(24) if not (6<=x<=17 and 23<=y<=29)]
    check(f'seed_{i}_body_hands_leaves_preserved',all(old.getpixel(p)==current.getpixel(p) for p in outside_face))
    green={pal[k] for k in 'LGH'}
    check(f'seed_{i}_leaves_all_colors_preserved',{(x,y,old.getpixel((x,y))) for y in range(36) for x in range(24) if old.getpixel((x,y)) in green}=={(x,y,current.getpixel((x,y))) for y in range(36) for x in range(24) if current.getpixel((x,y)) in green})
    check(f'seed_{i}_formation_preserved',(ROOT/f'seed-formation-{i}.png').read_bytes()==(v2/f'seed-formation-{i}.png').read_bytes())
for action in ['seed','water']:
    check(action+'_projectile_unchanged',(ROOT/f'{action}-projectile.png').read_bytes()==(v2/f'{action}-projectile.png').read_bytes())
check('preview_trajectory_not_slowed',manifest['preview_trajectory']==previous_manifest['preview_trajectory'])
ball_bboxes=[];ball_areas=[]
for i in range(4):
    ball=images['water','formation',i]; bbox=ball.getbbox()
    ball_bboxes.append([bbox[2]-bbox[0],bbox[3]-bbox[1]])
    ball_areas.append(sum(p[3]>0 for p in ball.getdata()))
check('water_inflate_then_same_large_hold',ball_bboxes==[[2,2],[4,4],[6,6],[6,6]] and ball_areas==[4,12,32,32],dict(bounds=ball_bboxes,areas=ball_areas))
f=manifest['actions']['water']['frames'][3]
check('water_hold_120ms_then_release',f['start_ms']==280 and f['end_ms']==400 and f['duration_ms']==120 and manifest['actions']['water']['release_events'][0]['time_ms']==400)
check('long_preview_includes_slow_recovery_idle',manifest['preview_cycle_ms']==4000 and data['cycle_ms']==4000 and manifest['preview_cycle_ms']/4>800 and 'const s=time/4' in html and 'max="3999"' in html)
for action,count in [('seed',4),('water',7)]:
    for i in range(count):
        im=images[action,'character',i]
        pending={(x,y) for y in range(36) for x in range(24) if im.getpixel((x,y))[3]}
        todo=[next(iter(pending))]; seen=set(todo)
        while todo:
            x,y=todo.pop()
            for dx in [-1,0,1]:
                for dy in [-1,0,1]:
                    q=(x+dx,y+dy)
                    if q in pending and q not in seen:seen.add(q);todo.append(q)
        check(f'{action}_{i}_connected',seen==pending)

preserved=json.loads((OUT.parent/'preserved-before.json').read_text())
for item in preserved:check('preserve/'+item['path'],sha(Path(item['path']))==item['sha256'])
for p in ROOT.iterdir():
    if p.is_file():hashes[p.name]=sha(p)
report=dict(head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=REPO,text=True).strip(),checks=checks,hashes=hashes,counts={s:sum(c['status']==s for c in checks) for s in ['PASS','FAIL']},browser_playback='NOT_RUN',game_integration='NOT_RUN')
(OUT/'results.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print(report['counts'])
for c in checks:
    if c['status']=='FAIL':print(c)
raise SystemExit(1 if report['counts']['FAIL'] else 0)
