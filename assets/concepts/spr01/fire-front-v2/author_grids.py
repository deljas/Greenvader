"""Front fire v2: exact retained seed leaves, recoil tips, longer discrete water inflate."""
from pathlib import Path
import json
import shutil

ROOT=Path(__file__).resolve().parent
V1=ROOT.parent/"fire-front-v1"
SOURCE=ROOT.parent/"four-directions-v2"


def read(name):
    return (V1/name).read_text().splitlines()


def write(name,rows):
    (ROOT/name).write_text("\n".join("".join(r) for r in rows)+"\n",encoding="utf-8")


def reposition(rows,relative_dy,tip_extra=False,cup=False):
    grid=[list("."*24) for _ in range(36)]
    for y,row in enumerate(rows):
        if y>=32:continue
        for x,c in enumerate(row):
            if c=="." :continue
            dx=(1 if x<12 else -1) if cup and c in "LGH" and y<=10 else 0
            grid[y+relative_dy][x+dx]=c
    # Stretch the lower bulb into the planted feet, rather than lifting it away.
    if relative_dy<0:
        grid[31]=list(rows[31])
    grid[32],grid[33]=list(rows[32]),list(rows[33])
    if tip_extra:
        # V1 neutral outer tips are(1,27)/(22,27); a pushed frame has them at y28.
        for x in (1,22):
            grid[28][x]="."
            grid[29][x]="W" if x==1 else "I"
    return grid


def main():
    for file in ("character-palette.json","fx-palette.json","idle.png","grid-idle.txt","grid-seed-projectile.txt"):
        shutil.copyfile(V1/file,ROOT/file)
    for i in range(4):
        char=read(f"grid-seed-character-{i}.txt")
        formation=read(f"grid-seed-formation-{i}.txt")
        if i==1:
            char=reposition(char,1,tip_extra=True)
            fx=[list("."*24) for _ in range(36)]
            for y,row in enumerate(formation):
                for x,c in enumerate(row):
                    if c!=".":fx[y+1][x]=c
            formation=fx
        write(f"grid-seed-character-{i}.txt",char)
        write(f"grid-seed-formation-{i}.txt",formation)
    mapping=[0,1,1,2,3,4]
    relative=[0,0,-1,0,1,0]
    for i,(old,dy) in enumerate(zip(mapping,relative)):
        char=reposition(read(f"grid-water-character-{old}.txt"),dy,tip_extra=i==3,cup=i==2)
        write(f"grid-water-character-{i}.txt",char)
        if i<2:
            formation=read(f"grid-water-formation-{i}.txt")
        else:
            formation=[list("."*24) for _ in range(36)]
            if i==2:
                for y in range(8,14):
                    for x in range(9,15):
                        if (x,y) not in ((9,8),(14,8),(9,13),(14,13)):
                            formation[y][x]="P" if x<=11 and y<=10 else ("C" if x<=13 else "B")
        write(f"grid-water-formation-{i}.txt",formation)
    water=[list("."*8) for _ in range(8)]
    for y in range(1,7):
        for x in range(1,7):
            if (x,y) not in ((1,1),(6,1),(1,6),(6,6)):
                water[y][x]="P" if x<=3 and y<=3 else ("C" if x<=5 else "B")
    write("grid-water-projectile.txt",water)
    timing={
      "durations_ms":{"seed":[33,50,50,67],"water":[40,60,50,60,80,110]},
      "phases":{"seed":["gather","flick-release-recoil","large-leaf-recoil","recover"],"water":["open-small-drop","inflate-medium","inflate-large-stretch","push-release","large-leaf-soft-droop","recover"]},
      "release_ms":{"seed":33,"water":150},
      "body_y_offsets":{"seed":[0,1,0,0],"water":[0,0,-1,1,1,0]},
      "socket_xy":{"seed":[[12,13],[12,14],[12,13],[12,13]],"water":[[12,13],[12,13],[12,12],[12,14],[12,14],[12,13]]}
    }
    (ROOT/"timing-source.json").write_text(json.dumps(timing,indent=2)+"\n",encoding="utf-8")


if __name__=="__main__":
    main()
