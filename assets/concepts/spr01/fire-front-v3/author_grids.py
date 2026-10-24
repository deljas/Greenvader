"""Front fire v3: source-duration slowdown, a longer water hold, authored effort faces."""
from pathlib import Path
import json
import shutil

ROOT=Path(__file__).resolve().parent
V2=ROOT.parent/"fire-front-v2"


def read(name):
    return (V2/name).read_text().splitlines()


def write(name,rows):
    (ROOT/name).write_text("\n".join("".join(r) for r in rows)+"\n",encoding="utf-8")


def hold_pose(rows):
    grid=[list("."*24) for _ in range(36)]
    for y,row in enumerate(rows):
        if y>=32:continue
        for x,c in enumerate(row):
            if c!=".":grid[y+1][x]=c
    grid[32],grid[33]=list(rows[32]),list(rows[33])
    return grid


def expression(rows,state,dy):
    grid=[list(r) for r in rows]
    if state=="neutral":return grid
    # Restore the original bulb's W/I planes under every old feature first.
    for y,row in enumerate(rows):
        for x,c in enumerate(row):
            if c in "EM":
                grid[y][x]="W" if x in (8,11) else "I"
    if state=="squeeze":
        for x,y in [(7,24),(8,25),(7,26),(16,24),(15,25),(16,26)]:
            grid[y+dy][x]="E"
        grid[27+dy][12]="M"
    else:
        for x in (8,15):
            grid[24+dy][x]=grid[25+dy][x]="E"
        for y in (26,27):
            for x in (11,12):grid[y+dy][x]="M"
    return grid


def main():
    for file in ("character-palette.json","fx-palette.json","idle.png","grid-idle.txt","grid-seed-projectile.txt","grid-water-projectile.txt"):
        shutil.copyfile(V2/file,ROOT/file)
    expressions={"seed":["squeeze","open-release","neutral","neutral"],"water":["neutral","neutral","squeeze","squeeze","open-release","neutral","neutral"]}
    offsets={"seed":[0,1,0,0],"water":[0,0,-1,0,1,1,0]}
    for i,state in enumerate(expressions["seed"]):
        write(f"grid-seed-character-{i}.txt",expression(read(f"grid-seed-character-{i}.txt"),state,offsets["seed"][i]))
        shutil.copyfile(V2/f"grid-seed-formation-{i}.txt",ROOT/f"grid-seed-formation-{i}.txt")
    mapping=[0,1,2,2,3,4,5]
    for i,(old,state) in enumerate(zip(mapping,expressions["water"])):
        char=read(f"grid-water-character-{old}.txt")
        fx=read(f"grid-water-formation-{old}.txt")
        if i==3:
            char=hold_pose(char)
            shifted=[list("."*24) for _ in range(36)]
            for y,row in enumerate(fx):
                for x,c in enumerate(row):
                    if c!=".":shifted[y+1][x]=c
            fx=shifted
        write(f"grid-water-character-{i}.txt",expression(char,state,offsets["water"][i]))
        write(f"grid-water-formation-{i}.txt",fx)
    timing={
        "durations_ms":{"seed":[66,100,100,134],"water":[80,100,100,120,100,120,180]},
        "phases":{"seed":["gather-squeeze","flick-release-open","large-leaf-recoil","recover"],"water":["open-small-drop","inflate-medium","inflate-large-squeeze","hold-large-squeeze","push-release-open","large-leaf-soft-droop","recover"]},
        "release_ms":{"seed":66,"water":400},
        "body_y_offsets":offsets,
        "expressions":expressions,
        "socket_xy":{"seed":[[12,13],[12,14],[12,13],[12,13]],"water":[[12,13],[12,13],[12,12],[12,13],[12,14],[12,14],[12,13]]}
    }
    assert timing["durations_ms"]["seed"]==[d*2 for d in json.loads((V2/"timing-source.json").read_text())["durations_ms"]["seed"]]
    (ROOT/"timing-source.json").write_text(json.dumps(timing,indent=2)+"\n",encoding="utf-8")


if __name__=="__main__":
    main()
