"""Native grid authorship/export. Existing assets are read-only references."""
from pathlib import Path
import copy, hashlib, json, shutil
from PIL import Image, ImageDraw, ImageFont

ROOT=Path(__file__).resolve().parent
REPO=ROOT.parents[3]
OUT=REPO/'evidence/spr01/fire-directions/asset-self'
FRONT=ROOT.parent/'fire-front-v3'
STATIC=ROOT.parent/'four-directions-v2'
DIRS=['down','left','right','up']
TIMING=json.loads((FRONT/'timing-source.json').read_text())
OLD=json.loads((FRONT/'manifest.json').read_text())
CP=json.loads((FRONT/'character-palette.json').read_text())
FP=json.loads((FRONT/'fx-palette.json').read_text())
BASE={d:(STATIC/f'grid-{d}.txt').read_text().splitlines() for d in DIRS}
EYES={'down':(8,15),'left':(4,9),'right':(14,19)}
MOUTHS={'down':(11,12),'left':(6,),'right':(17,)}
ROOTX={'down':12,'left':11,'right':12,'up':12}
# Per-direction anatomy retains the independently authored leaf shapes and lighting.
BIGSIDE={'left':1,'right':-1,'up':1}
LEAF_MOTION={
 'seed':[(3,2,-1,0),(2,-2,-1,0),(-1,0,1,0),(0,0,0,0)],
 'water':[(-1,-1,0,0),(-2,-2,1,0),(-1,-2,0,0),(-1,-2,0,0),(-2,-1,1,0),(-1,0,2,0),(0,0,0,0)]}

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def blank():return [list('.'*24) for _ in range(36)]
def grid(name):return (FRONT/name).read_text().splitlines()
def write_grid(name,g):
 (ROOT/name).write_text('\n'.join(''.join(r) for r in g)+'\n',encoding='utf-8')
def png(g,path,palette):
 im=Image.new('RGBA',(len(g[0]),len(g)))
 im.putdata([tuple(palette[c]) for row in g for c in row]);im.save(path)
 return im

def authored(direction,action,i):
 dy=TIMING['body_y_offsets'][action][i]
 if direction=='down':
  result=[list(r) for r in grid(f'grid-{action}-character-{i}.txt')]
  if action=='seed' and i==0:
   normal=(ROOT.parent/'fire-front-v2/grid-seed-character-0.txt').read_text().splitlines()
   for y in range(23,27):
    for x in list(range(6,10))+list(range(14,18)):result[y][x]=normal[y][x]
  return result
 source=BASE[direction];result=blank()
 for y,row in enumerate(source[:32]):
  for x,c in enumerate(row):
   if c!='.' and c not in 'LGH':result[y+dy][x]=c
 if dy<0:result[31]=list(source[31])
 result[32],result[33]=list(source[32]),list(source[33])
 # Shift the exposed hand tips one additional native pixel on release.
 if (action=='seed' and i==1) or (action=='water' and i==4):
  for side in (-1,1):
   candidates=[(x,y) for y in range(24+dy,30+dy) for x,c in enumerate(result[y]) if c in 'WIS' and (x<=2 if side<0 else x>=21)]
   if candidates:
    extreme=min(x for x,y in candidates) if side<0 else max(x for x,y in candidates)
    targets=[(x,y) for x,y in candidates if x==extreme]
    for x,y in reversed(targets):result[y+1][x]=result[y][x];result[y][x]='.'
 # Leaves are row-authored from each adopted direction's own grid. No bitmap mirroring.
 big_in,small_in,big_dy,small_dy=LEAF_MOTION[action][i]
 rx=ROOTX[direction];bigside=BIGSIDE[direction]
 for y,row in enumerate(source):
  for x,c in enumerate(row):
   if c not in 'LGH':continue
   side=-1 if x<rx else 1
   big=side==bigside
   inward=big_in if big else small_in
   dx=round(-side*inward*max(0,14-y)/11)
   vy=(big_dy if big else small_dy) if y<11 else 0
   nx=max(1,min(22,x+dx));ny=y+dy+vy
   # Native vertical extrusion keeps the bending blade joined across row changes.
   for join_y in range(min(ny,y+dy),max(ny,y+dy)+1):result[join_y][nx]=c
 # Exact planted roots: independently placed in the static source.
 for x,c in enumerate(source[14]):
  if c in 'LGH':result[14+dy][x]=c
 # Faces retain their frontward three-quarter positions. Back has no expression.
 if direction in EYES:
  state=TIMING['expressions'][action][i]
  closed=action=='water' and state=='squeeze'
  if closed:
   for x in EYES[direction]:
    skin='W' if direction=='left' else 'I'
    result[24+dy][x]=skin;result[25+dy][x]=skin
   l,r=EYES[direction]
   for x,y in [(l-1,24),(l,25),(l-1,26),(r+1,24),(r,25),(r+1,26)]:result[y+dy][x]='E'
  if state=='open-release':
   for x in MOUTHS[direction]:result[26+dy][x]=result[27+dy][x]='M'
 return result

def main():
 OUT.mkdir(parents=True,exist_ok=True)
 for f in ['character-palette.json','fx-palette.json','grid-seed-projectile.txt','grid-water-projectile.txt','seed-projectile.png','water-projectile.png']:
  shutil.copyfile(FRONT/f,ROOT/f)
 for d in DIRS:
  shutil.copyfile(STATIC/f'{d}.png',ROOT/f'idle-{d}.png')
  write_grid(f'grid-idle-{d}.txt',BASE[d])
 manifest={'kind':'four-direction-fire-v1','character_size':[24,36],'foot_anchor_xy':[12,34],'directions':DIRS,'preview_cycle_ms':4000,'actions':{}}
 previews={'directions':DIRS,'palettes':{'character':CP,'fx':FP},'idle':BASE,'actions':{},'cycle_ms':4000}
 checks=[];eye_changes=[]
 for action in ['seed','water']:
  a=copy.deepcopy(OLD['actions'][action]);n=len(a['durations_ms'])
  sheet=Image.new('RGBA',(24*n,144));fxsheet=sheet.copy()
  bydir={};previewdirs={};sockets={}
  for row,d in enumerate(DIRS):
   frames=[];previewframes=[]
   dx=ROOTX[d]-12
   for i,oldframe in enumerate(a['frames']):
    dy=TIMING['body_y_offsets'][action][i]
    char=authored(d,action,i)
    fx=blank()
    for y,line in enumerate(grid(f'grid-{action}-formation-{i}.txt')):
     for x,c in enumerate(line):
      if c!='.':fx[y][x+dx]=c
    cn=f'{action}-{d}-character-{i}.png';fn=f'{action}-{d}-formation-{i}.png'
    write_grid(f'grid-{action}-{d}-character-{i}.txt',char)
    write_grid(f'grid-{action}-{d}-formation-{i}.txt',fx)
    ci=png(char,ROOT/cn,CP);fi=png(fx,ROOT/fn,FP)
    # Preserve exact PNG bytes for untouched front frames, FX and both flying images.
    if d=='down':
     if action=='water' or i>0:shutil.copyfile(FRONT/f'{action}-character-{i}.png',ROOT/cn)
     shutil.copyfile(FRONT/f'{action}-formation-{i}.png',ROOT/fn)
    sheet.paste(ci,(24*i,36*row));fxsheet.paste(fi,(24*i,36*row))
    f=copy.deepcopy(oldframe)
    f['character']={'file':cn,'rect':[24*i,36*row,24,36],'sha256':sha(ROOT/cn)}
    f['formation_fx']={'file':fn,'rect':[24*i,36*row,24,36],'sha256':sha(ROOT/fn)}
    f['socket_xy']=[ROOTX[d],oldframe['socket_xy'][1]]
    f['expression']['eyes']='none-back-view' if d=='up' else ('closed-inward-chevrons-3px-each' if action=='water' and i in (2,3) else 'open-1x2-each')
    if action=='seed' and i==0:f['expression']['state']='normal-eyes-pursed-mouth'
    if d=='up':f['expression']={'state':'back-view','eyes':'none-back-view','mouth':'none-back-view'}
    frames.append(f);previewframes.append({**f,'character_grid':char,'formation_grid':fx})
    assert ci.size==(24,36) and fi.size==(24,36)
    assert {p[3] for p in ci.getdata()}<={0,255}
    assert set(ci.getdata())<=set(map(tuple,CP.values()))
    assert {p[3] for p in fi.getdata()}<={0,255}
    assert set(fi.getdata())<=set(map(tuple,FP.values()))
    assert [''.join(r) for r in char[32:34]]==BASE[d][32:34]
    if d=='up':assert not any(c in 'EM' for r in char for c in r)
    if d in EYES and not(action=='water' and i in (2,3)):
     assert {(x,y) for y,r in enumerate(char) for x,c in enumerate(r) if c=='E'}=={(x,y+dy) for x in EYES[d] for y in (24,25)}
    footruns=[]
    for x in range(24):
     if char[32][x]!='.':
      if x==0 or char[32][x-1]=='.':footruns.append([])
      footruns[-1].append(x)
    assert all(any(char[31][x]!='.' for x in run) for run in footruns),(action,d,i,'foot connection')
    # Every opaque leaf pixel has an eight-neighbour path to its rooted bulb.
    opaque={(x,y) for y,r in enumerate(char) for x,c in enumerate(r) if c!='.'}
    connected={(ROOTX[d],16+dy)};todo=list(connected)
    while todo:
     x,y=todo.pop()
     for vx in (-1,0,1):
      for vy in (-1,0,1):
       p=(x+vx,y+vy)
       if p in opaque and p not in connected:connected.add(p);todo.append(p)
    assert all((x,y) in connected for y,r in enumerate(char) for x,c in enumerate(r) if c in 'LGH'),(action,d,i,'leaf connection')
    checks.append({'action':action,'direction':d,'frame':i,'size_palette_alpha_face_feet':True})
   bydir[d]=frames;previewdirs[d]=previewframes
   release_i=next(i for i,f in enumerate(frames) if f['start_ms']==a['release_events'][0]['time_ms'])
   sockets[d]=frames[release_i]['socket_xy']
  a['frames']=bydir['down'];a['frames_by_direction']=bydir
  a['release_events'][0]['socket_by_direction']=sockets
  a['sheet_size']=[24*n,144]
  sheet.save(ROOT/a['character_sheet']);fxsheet.save(ROOT/a['formation_sheet'])
  manifest['actions'][action]=a
  previews['actions'][action]={'frames_by_direction':previewdirs,'durations_ms':a['durations_ms'],'total_ms':a['total_ms'],'release_ms':a['release_events'][0]['time_ms'],'socket_by_direction':sockets,'projectile_grid':grid(f'grid-{action}-projectile.txt')}
 for i in range(7):
  for layer in ['character','formation']:
   assert (ROOT/f'water-down-{layer}-{i}.png').read_bytes()==(FRONT/f'water-{layer}-{i}.png').read_bytes()
 for i in range(4):
  before=grid(f'grid-seed-character-{i}.txt');after=(ROOT/f'grid-seed-down-character-{i}.txt').read_text().splitlines()
  diff=[(x,y) for y in range(36) for x in range(24) if before[y][x]!=after[y][x]]
  assert all((6<=x<10 or 14<=x<18) and 23<=y<27 for x,y in diff)
  eye_changes.extend(diff)
  assert (ROOT/f'seed-left-character-{i}.png').read_bytes()!=(ROOT/f'seed-right-character-{i}.png').read_bytes()
  left=Image.open(ROOT/f'seed-left-character-{i}.png');right=Image.open(ROOT/f'seed-right-character-{i}.png')
  assert left.transpose(Image.Transpose.FLIP_LEFT_RIGHT).tobytes()!=right.tobytes()
 (ROOT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
 (ROOT/'preview-data.json').write_text(json.dumps(previews,separators=(',',':'))+'\n',encoding='utf-8')
 report={'status':'PASS','character_frames':44,'formation_frames':44,'frame_checks':checks,'front_water_byte_identical':True,'front_seed_changed_pixels':eye_changes,'left_right_not_mirror':True,'timing_ms':{a:{'durations':manifest['actions'][a]['durations_ms'],'release':manifest['actions'][a]['release_events'][0]['time_ms']} for a in manifest['actions']},'godot_import':'NOT_RUN (owned by runtime implementer)','browser_playback':'NOT_RUN','final_art_acceptance':'USER_PENDING'}
 (OUT/'self-check.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
 print(json.dumps({k:v for k,v in report.items() if k!='frame_checks'},indent=2))

if __name__=='__main__':main()
