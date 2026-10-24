"""Author editable front seed/water grids. No generated-image resizing or game changes."""
from pathlib import Path
import json
import shutil
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent
SOURCE = ROOT.parent / "four-directions-v2"
GREEN = {"L": 1, "G": 2, "H": 3}
# Two independently drawn leaf blades per pose; large always viewer-left.
# Each polygon begins at its tip and ends near its root.
POSES = {
"seed": [
 [[(7,2),(10,3),(11,6),(11,11),(11,14),(9,12),(7,8),(6,4)],[(16,6),(17,7),(16,10),(13,13),(12,14),(12,11),(14,8)]],
 [[(6,3),(9,4),(11,7),(11,12),(11,14),(8,11),(6,8),(5,5)],[(21,7),(22,8),(20,11),(16,13),(12,14),(14,11),(18,8)]],
 [[(2,7),(5,6),(8,7),(10,10),(11,14),(8,12),(4,11),(2,9)],[(19,6),(20,7),(18,10),(15,12),(12,14),(13,11),(16,8)]],
 [[(3,4),(6,4),(9,7),(10,10),(11,14),(8,12),(5,9),(3,6)],[(20,7),(20,9),(17,12),(12,14),(14,11),(17,8)]],
],
"water": [
 [[(2,5),(5,4),(8,6),(10,10),(11,14),(8,12),(4,9),(2,7)],[(21,8),(21,10),(18,12),(12,14),(14,11),(18,8)]],
 [[(1,6),(4,5),(7,6),(10,10),(11,14),(7,12),(3,10),(1,8)],[(22,10),(21,12),(17,14),(12,14),(14,12),(18,10)]],
 [[(1,7),(4,6),(7,8),(10,11),(11,14),(7,12),(3,11),(1,9)],[(21,7),(21,9),(18,12),(12,14),(14,11),(18,8)]],
 [[(2,9),(5,8),(8,10),(11,14),(8,14),(4,12),(2,11)],[(20,7),(20,9),(17,12),(12,14),(14,11),(17,8)]],
 [[(3,5),(6,5),(9,8),(10,11),(11,14),(8,12),(5,10),(3,7)],[(20,7),(20,9),(17,12),(12,14),(14,11),(17,8)]],
]}
DURATIONS = {"seed":[33,50,50,67], "water":[17,33,50,67,83]}
PHASES = {"seed":["gather","flick-release","large-leaf-recoil","recover"],"water":["open-small-drop","inflate","push-release","large-leaf-soft-droop","recover"]}


def blank(w=24,h=36):
    return [list("."*w) for _ in range(h)]


def write(name,grid):
    (ROOT/name).write_text("\n".join("".join(row) for row in grid)+"\n",encoding="utf-8")


def leaf(grid,polygon,dy):
    mask=Image.new("1",(24,36),0)
    ImageDraw.Draw(mask).polygon([(x,y+dy) for x,y in polygon],fill=1)
    xs=[x for x,y in polygon]
    lo,hi=min(xs),max(xs)
    for y in range(36):
        for x in range(24):
            if mask.getpixel((x,y)):
                # Hard internal planes, not a perimeter stroke.
                fraction=(x-lo)/max(hi-lo,1)
                grid[y][x]="L" if fraction<0.38 else ("G" if fraction<0.78 else "H")


def main():
    palette=json.loads((SOURCE/"palette.json").read_text())
    (ROOT/"character-palette.json").write_text(json.dumps(palette,indent=2)+"\n",encoding="utf-8")
    fx_palette={".":[0,0,0,0],"B":[80,139,165,255],"C":[127,182,200,255],"P":[193,222,225,255],"T":[185,151,92,255],"V":[218,193,132,255],"R":[145,114,65,255]}
    (ROOT/"fx-palette.json").write_text(json.dumps(fx_palette,indent=2)+"\n",encoding="utf-8")
    shutil.copyfile(SOURCE/"down.png",ROOT/"idle.png")
    shutil.copyfile(SOURCE/"grid-down.txt",ROOT/"grid-idle.txt")
    original=(SOURCE/"grid-down.txt").read_text().splitlines()
    for action,poses in POSES.items():
        for frame,polygons in enumerate(poses):
            grid=blank()
            dy=1 if action=="water" and frame==2 else 0
            for y,row in enumerate(original):
                if y>=32: continue
                for x,char in enumerate(row):
                    if char in "WISEM": grid[y+dy][x]=char
            grid[32],grid[33]=list(original[32]),list(original[33])
            for polygon in polygons: leaf(grid,polygon,dy)
            # Distinct attached roots with an emission socket between the blades.
            grid[14+dy][11],grid[14+dy][12]="G","G"
            write(f"grid-{action}-character-{frame}.txt",grid)
            fx=blank()
            if action=="seed":
                if frame==0:
                    fx[12][11],fx[12][12],fx[13][12]="V","T","T"
                elif frame==1:
                    fx[12][9],fx[12][15]="V","T"
            else:
                if frame==0:
                    fx[11][11],fx[11][12],fx[12][11],fx[12][12]="P","C","C","B"
                elif frame==1:
                    for y in range(10,14):
                        for x in range(10,14):
                            if (x,y) not in ((10,10),(13,10),(10,13),(13,13)):
                                fx[y][x]="P" if y==10 else ("C" if x<13 else "B")
            write(f"grid-{action}-formation-{frame}.txt",fx)
    seed=blank(8,8)
    for x,y,c in [(4,2,"V"),(3,3,"V"),(4,3,"T"),(5,3,"T"),(3,4,"T"),(4,4,"T"),(5,4,"R"),(4,5,"R")]: seed[y][x]=c
    write("grid-seed-projectile.txt",seed)
    water=blank(8,8)
    for y in range(2,7):
        for x in range(2,7):
            if (x,y) not in ((2,2),(6,2),(2,6),(6,6)):
                water[y][x]="P" if y<=3 and x<=4 else ("C" if x<=5 else "B")
    write("grid-water-projectile.txt",water)
    draft={"durations_ms":DURATIONS,"phases":PHASES,"release_ms":{"seed":33,"water":50},"body_y_offsets":{"seed":[0,0,0,0],"water":[0,0,1,0,0]},"socket_xy":{"seed":[[12,13]]*4,"water":[[12,13],[12,13],[12,14],[12,13],[12,13]]}}
    (ROOT/"timing-source.json").write_text(json.dumps(draft,indent=2)+"\n",encoding="utf-8")


if __name__=="__main__":
    main()
