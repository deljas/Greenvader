"""Self-contained exact-ms HTML and nearest native-grid reference previews."""
from pathlib import Path
import hashlib,json
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parent
DATA=json.loads((ROOT/'preview-data.json').read_text())
CP=DATA['palettes']['character'];FP=DATA['palettes']['fx']
FONT=ImageFont.truetype('C:/Windows/Fonts/consola.ttf',13)
VECTORS={'down':(0,1),'left':(-1,0),'right':(1,0),'up':(0,-1)}

def active(a,d,t):return next((f for f in a['frames_by_direction'][d] if f['start_ms']<=t<f['end_ms']),None)
def pixels(im,grid,origin,scale,palette,offset=(0,0)):
 draw=ImageDraw.Draw(im)
 for y,row in enumerate(grid):
  for x,c in enumerate(row):
   if c=='.':continue
   px=origin[0]+(x+offset[0])*scale;py=origin[1]+(y+offset[1])*scale
   draw.rectangle((px,py,px+scale-1,py+scale-1),fill=tuple(palette[c][:3]))
def render(im,action,d,t,origin,scale,flight=True):
 a=DATA['actions'][action];f=active(a,d,t)
 pixels(im,DATA['idle'][d] if f is None else f['character_grid'],origin,scale,CP)
 if f:pixels(im,f['formation_grid'],origin,scale,FP)
 if flight and a['release_ms']<=t<a['release_ms']+120:
  sx,sy=a['socket_by_direction'][d];vx,vy=VECTORS[d];travel=int((t-a['release_ms'])*.24)
  pixels(im,a['projectile_grid'],origin,scale,FP,(sx-4+vx*travel,sy-4+vy*travel))

def main():
 contact=Image.new('RGB',(1016,1440),(39,44,45));draw=ImageDraw.Draw(contact)
 for ar,action in enumerate(('seed','water')):
  for dr,d in enumerate(DATA['directions']):
   y=30+(ar*4+dr)*175
   draw.text((16,y),f'{action.upper()} / {d.upper()}',font=FONT,fill=(255,249,231))
   for i,f in enumerate(DATA['actions'][action]['frames_by_direction'][d]):
    x=180+i*116
    draw.text((x,y),f'F{i} {f["start_ms"]}ms',font=FONT,fill=(244,231,202))
    render(contact,action,d,f['start_ms'],(x,y+25),3,False)
 contact.save(ROOT/'contact-sheet.png')
 palette=[(39,44,45),(255,249,231),(244,231,202)]+[tuple(v[:3]) for p in (CP,FP) for k,v in p.items() if k!='.']
 pal=Image.new('P',(1,1));pal.putpalette([v for rgb in palette for v in rgb]+[0]*(768-3*len(palette)))
 pages=[]
 for t in range(0,4000,20):
  page=Image.new('RGB',(448,800),(39,44,45));pd=ImageDraw.Draw(page)
  pd.text((12,6),f'SEED / WATER     {t:04d}ms / 4000ms',font=FONT,fill=(255,249,231))
  for ri,d in enumerate(DATA['directions']):
   for col,action in enumerate(('seed','water')):
    x=48+224*col;y=44+ri*184
    pd.text((x,y-16),d.upper(),font=FONT,fill=(255,249,231))
    render(page,action,d,t,(x,y),4)
  pages.append(page.quantize(palette=pal,dither=Image.Dither.NONE))
 pages[0].save(ROOT/'comparison.gif',save_all=True,append_images=pages[1:],duration=20,loop=0,optimize=False,disposal=2)
 gif=Image.open(ROOT/'comparison.gif');assert sum(gif.seek(i) or gif.info['duration'] for i in range(gif.n_frames))==4000
 template=(ROOT/'preview-template.html').read_text(encoding='utf-8')
 (ROOT/'comparison.html').write_text(template.replace('__DATA__',json.dumps(DATA,separators=(',',':'))),encoding='utf-8')
 paths=[p for p in ROOT.iterdir() if p.is_file()]
 (ROOT.parents[3]/'evidence/spr01/fire-directions/asset-self/target-hashes.json').write_text(json.dumps({str(p.relative_to(ROOT.parents[3])).replace('\\','/'):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths},indent=2)+'\n',encoding='utf-8')
 print('Preview written: contact-sheet.png, comparison.gif, comparison.html; 4000ms cycle.')

if __name__=='__main__':main()
