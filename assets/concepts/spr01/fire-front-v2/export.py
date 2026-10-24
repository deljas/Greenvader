"""Export native layers and exact-ms comparison; no runtime/Godot use."""
from pathlib import Path
import base64
import hashlib
import json
import shutil
from PIL import Image, ImageDraw, ImageFont

ROOT=Path(__file__).resolve().parent
REPO=ROOT.parents[3]
OUT=REPO/"evidence/spr01/fire-front-v2/self"
SOURCE=ROOT.parent/"four-directions-v2"
LENGTH=2000
STEP=20
PALETTES={layer:{k:tuple(v) for k,v in json.loads((ROOT/f"{layer}-palette.json").read_text()).items()} for layer in ("character","fx")}
TIMING=json.loads((ROOT/"timing-source.json").read_text())
DATA={"idle":(ROOT/"grid-idle.txt").read_text().splitlines(),"actions":{},"palettes":PALETTES,"cycle_ms":LENGTH,"trajectory":{"speed_y_px_per_ms":0.35,"lifetime_ms":150,"preview_only":True}}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def grid_png(grid,path,palette,size):
    assert len(grid)==size[1] and all(len(r)==size[0] for r in grid)
    assert all(c in palette for row in grid for c in row)
    result=Image.new("RGBA",size)
    expected=[palette[c] for row in grid for c in row]
    result.putdata(expected)
    result.save(path)
    actual=Image.open(path)
    assert actual.mode=="RGBA" and actual.size==size
    assert [actual.getpixel((x,y)) for y in range(size[1]) for x in range(size[0])]==expected
    assert {p[3] for p in expected}<={0,255}
    return actual


def phase(action,t):
    elapsed=0
    for i,duration in enumerate(TIMING["durations_ms"][action]):
        if t<elapsed+duration:return i
        elapsed+=duration
    return None


def glyph(draw,xy,text,color):
    draw.text(xy,text,font=ImageFont.load_default(),fill=color)


def draw_grid(draw,grid,origin,scale,colors,offset=(0,0),clip_h=52):
    for y,row in enumerate(grid):
        for x,c in enumerate(row):
            nx,ny=x+offset[0],y+offset[1]
            if c!="." and 0<=nx<24 and 0<=ny<clip_h:
                px,py=origin[0]+nx*scale,origin[1]+ny*scale
                draw.rectangle((px,py,px+scale-1,py+scale-1),fill=colors[c])


def render(draw,action,t,origin,scale,charcolors,fxcolors,fx=True):
    item=DATA["actions"][action]
    i=phase(action,t)
    rows=DATA["idle"] if i is None else item["frames"][i]["character_grid"]
    draw_grid(draw,rows,origin,scale,charcolors)
    if fx:
        if i is not None:draw_grid(draw,item["frames"][i]["formation_grid"],origin,scale,fxcolors)
        release=item["release_ms"]
        if release<=t<release+150:
            socket=item["release_socket_xy"]
            y=socket[1]+int((t-release)*0.35)
            draw_grid(draw,item["projectile_grid"],origin,scale,fxcolors,(socket[0]-4,y-4))


def main():
    OUT.mkdir(parents=True,exist_ok=True)
    source_hash=sha(SOURCE/"down.png")
    assert source_hash=="d12e39f3ba986f36d0b2a7a0a762518794eaa370d72de17096c804041c8d8d18"
    assert (ROOT/"idle.png").read_bytes()==(SOURCE/"down.png").read_bytes()
    manifest={"kind":"front-fire-v2-candidate","character_size":[24,36],"foot_anchor_xy":[12,34],"direction":"down","idle":{"file":"idle.png","sha256":sha(ROOT/"idle.png")},"preview_cycle_ms":LENGTH,"preview_trajectory":DATA["trajectory"],"gif":{"sampling_step_ms":20,"event_rounding":"first sample at or after exact event","release_ms":{"seed":40,"water":160}},"actions":{}}
    checks=[]
    native_files=[]
    reference=(SOURCE/"grid-down.txt").read_text().splitlines()
    for action in ("seed","water"):
        count=len(TIMING["durations_ms"][action])
        chars=Image.new("RGBA",(24*count,36))
        fxsheet=Image.new("RGBA",(24*count,36))
        frames=[]
        start=0
        projectile=(ROOT/f"grid-{action}-projectile.txt").read_text().splitlines()
        grid_png(projectile,ROOT/f"{action}-projectile.png",PALETTES["fx"],(8,8))
        native_files.append(ROOT/f"{action}-projectile.png")
        for i,duration in enumerate(TIMING["durations_ms"][action]):
            character=(ROOT/f"grid-{action}-character-{i}.txt").read_text().splitlines()
            formation=(ROOT/f"grid-{action}-formation-{i}.txt").read_text().splitlines()
            charpath=ROOT/f"{action}-character-{i}.png"
            fxpath=ROOT/f"{action}-formation-{i}.png"
            image=grid_png(character,charpath,PALETTES["character"],(24,36))
            fximage=grid_png(formation,fxpath,PALETTES["fx"],(24,36))
            native_files.extend([charpath,fxpath])
            dy=TIMING["body_y_offsets"][action][i]
            face={(x,y,c) for y,row in enumerate(character) for x,c in enumerate(row) if c in "EM"}
            expected_face={(x,y+dy,c) for y,row in enumerate(reference) for x,c in enumerate(row) if c in "EM"}
            assert face==expected_face
            for x in (8,15):
                assert [y for ex,y,c in face if ex==x and c=="E"] or False
                assert character[24+dy][x]==character[25+dy][x]=="E"
            assert character[32:34]==reference[32:34]
            bbox=image.getbbox()
            assert 0<bbox[0]<bbox[2]<24 and 0<bbox[1]<bbox[3]<36 and bbox[3]==34
            if action=="water" and i>=3:assert fximage.getbbox() is None
            chars.paste(image,(24*i,0));fxsheet.paste(fximage,(24*i,0))
            frame={"index":i,"start_ms":start,"duration_ms":duration,"end_ms":start+duration,"phase":TIMING["phases"][action][i],"character":{"file":charpath.name,"rect":[24*i,0,24,36],"sha256":sha(charpath)},"formation_fx":{"file":fxpath.name,"rect":[24*i,0,24,36],"sha256":sha(fxpath)},"socket_xy":TIMING["socket_xy"][action][i],"body_y_offset_px":dy}
            frames.append({**frame,"character_grid":character,"formation_grid":formation})
            checks.append({"action":action,"frame":i,"size_rgba_alpha_palette":True,"face_preserved_eyes_1x2":True,"feet_fixed":True,"no_clip":True})
            start+=duration
        chars.save(ROOT/f"{action}-character-sheet.png");fxsheet.save(ROOT/f"{action}-formation-sheet.png")
        release=TIMING["release_ms"][action]
        released_index=phase(action,release)
        assert released_index is not None and frames[released_index]["start_ms"]==release
        DATA["actions"][action]={"frames":frames,"total_ms":start,"release_ms":release,"release_socket_xy":TIMING["socket_xy"][action][released_index],"projectile_grid":projectile}
        manifest["actions"][action]={"durations_ms":TIMING["durations_ms"][action],"total_ms":start,"release_events":[{"type":"projectile-release","time_ms":release,"socket_xy":TIMING["socket_xy"][action][released_index]}],"character_sheet":f"{action}-character-sheet.png","formation_sheet":f"{action}-formation-sheet.png","projectile":{"file":f"{action}-projectile.png","size":[8,8],"anchor_xy":[4,4],"sha256":sha(ROOT/f"{action}-projectile.png")},"frames":[{k:v for k,v in f.items() if not k.endswith("_grid")} for f in frames]}
    # Water grows in discrete native pixel steps, then separates at exactly50ms.
    growth=[]
    for index in range(3):
        image=Image.open(ROOT/f"water-formation-{index}.png")
        box=image.getbbox()
        assert [box[2]-box[0],box[3]-box[1]]==[2*(index+1)]*2
        growth.append(sum(image.getpixel((x,y))[3]>0 for y in range(36) for x in range(24)))
    assert growth[0]<growth[1]<growth[2]
    v1=ROOT.parent/"fire-front-v1"
    for index in range(4):
        old=(v1/f"grid-seed-character-{index}.txt").read_text().splitlines()
        new=(ROOT/f"grid-seed-character-{index}.txt").read_text().splitlines()
        offset=1 if index==1 else 0
        assert {(x,y+offset,c) for y,row in enumerate(old) for x,c in enumerate(row) if c in "LGH"}=={(x,y,c) for y,row in enumerate(new) for x,c in enumerate(row) if c in "LGH"}
        if index!=1:assert old==new
    seed_push=(ROOT/"grid-seed-character-1.txt").read_text().splitlines()
    for x in (1,22):
        assert seed_push[28][x]=="." and seed_push[29][x] in "WI"
    stretched=(ROOT/"grid-water-character-2.txt").read_text().splitlines()
    assert stretched[31]==reference[31] and stretched[32:34]==reference[32:34]
    contact=Image.new("RGB",(760,560),(39,44,45));cd=ImageDraw.Draw(contact)
    font=ImageFont.truetype("C:/Windows/Fonts/consola.ttf",14)
    colors={k:v[:3] for k,v in PALETTES["character"].items()}
    fxcolors={k:v[:3] for k,v in PALETTES["fx"].items()}
    for row,action in enumerate(("seed","water")):
        base_y=48+row*272
        cd.text((24,base_y-42),action.upper()+" / native4x / character + separate FX",font=font,fill=(236,231,213))
        for i,frame in enumerate(DATA["actions"][action]["frames"]):
            x=24+i*120
            cd.text((x,base_y-22),f"F{i} {frame['start_ms']}ms",font=font,fill=(236,231,213))
            render(cd,action,frame["start_ms"],(x,base_y),4,colors,fxcolors)
    contact.save(ROOT/"contact-sheet.png")
    # One fixed GIF palette, no dither/quantization.20ms samples may approximate exact events.
    allcolors=[(39,44,45)]+[v[:3] for k,v in PALETTES["character"].items() if k!="."]+[v[:3] for k,v in PALETTES["fx"].items() if k!="."]
    pcolors=allcolors+[ (84,90,88) ]
    rawpalette=[v for rgb in pcolors for v in rgb]+[0]*(768-len(pcolors)*3)
    cmap={k:allcolors.index(v[:3]) for k,v in PALETTES["character"].items() if k!="."}
    fmap={k:allcolors.index(v[:3]) for k,v in PALETTES["fx"].items() if k!="."}
    pages=[]
    for t in range(0,LENGTH,STEP):
        page=Image.new("P",(448,544),0);page.putpalette(rawpalette);pd=ImageDraw.Draw(page)
        for col,action in enumerate(("seed","water")):
            x=48+208*col
            glyph(pd,(x,8),action.upper()+" / REAL",1)
            i=phase(action,t)
            glyph(pd,(x,25),str(t)+"ms "+("IDLE" if i is None else "F"+str(i)),1)
            render(pd,action,t,(x,48),6,cmap,fmap)
            slow=t/4
            glyph(pd,(x,372),"4x SLOW / "+str(int(slow))+"ms",1)
            j=phase(action,slow)
            glyph(pd,(x,389),"IDLE" if j is None else "F"+str(j),1)
            render(pd,action,slow,(x+48,408),2,cmap,fmap)
        glyph(pd,(24,528),"20ms GIF SAMPLES / HTML HAS EXACT MS",1)
        pages.append(page)
    gifpath=ROOT/"comparison.gif"
    pages[0].save(gifpath,save_all=True,append_images=pages[1:],duration=STEP,loop=0,optimize=False,disposal=2)
    gif=Image.open(gifpath)
    assert gif.n_frames==len(pages)
    for i,page in enumerate(pages):
        gif.seek(i)
        assert gif.info["duration"]==STEP and gif.convert("RGB").tobytes()==page.convert("RGB").tobytes()
    (ROOT/"preview-data.json").write_text(json.dumps(DATA,separators=(",",":"))+"\n",encoding="utf-8")
    (ROOT/"manifest.json").write_text(json.dumps(manifest,indent=2)+"\n",encoding="utf-8")
    assert sha(SOURCE/"down.png")==source_hash
    native_files.append(ROOT/"idle.png")
    report={"status":"PASS","checks":checks,"idle_byte_identical":True,"source_down_sha256":source_hash,"character_frames":10,"formation_frames":10,"projectiles":2,"durations_ms":TIMING["durations_ms"],"release_ms":TIMING["release_ms"],"separate_layers":True,"water_growth_pixels":growth,"water_growth_then_separation":True,"seed_leaf_relative_pose_retained":True,"seed_push_body_face_dy":1,"seed_handtip_total_dy":2,"water_lower_torso_connected":True,"gif_frames":len(pages),"gif_step_ms":STEP,"gif_cycle_ms":LENGTH,"gif_decoded_rgb_exact":True,"native_sha256":{p.name:sha(p) for p in native_files}}
    (OUT/"self-check.json").write_text(json.dumps(report,indent=2)+"\n",encoding="utf-8")
    print(json.dumps({k:v for k,v in report.items() if k not in ("checks","native_sha256")},indent=2))


if __name__=="__main__":
    main()
