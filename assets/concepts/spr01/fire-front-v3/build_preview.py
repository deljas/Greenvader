"""Embed exact grid/timing data; verify timing boundaries and brief face overlap."""
from pathlib import Path
import json
import re

ROOT=Path(__file__).resolve().parent
OUT=ROOT.parents[3]/"evidence/spr01/fire-front-v3/self"


def main():
    raw=(ROOT/"preview-data.json").read_text()
    data=json.loads(raw)
    template=(ROOT/"preview-template.html").read_text(encoding="utf-8")
    output=template.replace("__DATA__",raw.strip())
    (ROOT/"comparison.html").write_text(output,encoding="utf-8")
    assert "__DATA__" not in output and "https://" not in output and "fetch(" not in output
    assert json.loads(re.search(r'<script id="data" type="application/json">(.*?)</script>',output,re.S).group(1))==data
    boundaries={}
    overlaps={}
    for action,a in data["actions"].items():
        def at(t):
            return next((f for f in a["frames"] if f["start_ms"]<=t<f["end_ms"]),None)
        assert at(0)["index"]==0 and at(a["total_ms"]) is None
        assert at(a["release_ms"])["start_ms"]==a["release_ms"]
        for f in a["frames"]:
            assert at(f["start_ms"])["index"]==f["index"]
            assert at(f["end_ms"]-1)["index"]==f["index"]
        covered=[]
        eye_covered=[]
        for t in range(a["total_ms"]):
            f=at(t)
            face={(x,y,c) for y,row in enumerate(f["character_grid"]) for x,c in enumerate(row) if c in "EM"}
            effect={(x,y) for y,row in enumerate(f["formation_grid"]) for x,c in enumerate(row) if c!="."}
            if a["release_ms"]<=t<a["release_ms"]+150:
                socket=a["release_socket_xy"]
                cy=socket[1]+int((t-a["release_ms"])*.35)
                effect|={(socket[0]-4+x,cy-4+y) for y,row in enumerate(a["projectile_grid"]) for x,c in enumerate(row) if c!="."}
            if any((x,y) in effect for x,y,c in face):covered.append(t)
            if any((x,y) in effect and c=="E" for x,y,c in face):eye_covered.append(t)
        assert not eye_covered
        longest=0;run=0;previous=-2
        for t in covered:
            run=run+1 if t==previous+1 else 1
            longest=max(longest,run);previous=t
        assert longest<=20
        overlaps[action]={"any_face_overlap_ms":covered,"longest_contiguous_ms":longest,"eye_overlap_ms":eye_covered}
        boundaries[action]={"starts_ms":[f["start_ms"] for f in a["frames"]],"end_ms":a["total_ms"],"release_ms":a["release_ms"]}
    script=re.findall(r"<script>(.*?)</script>",output,re.S)[0]
    (OUT/"preview-script-check.js").write_text(script,encoding="utf-8")
    report={"embedded_data_exact":True,"self_contained":True,"timing_boundaries":boundaries,"face_overlap":overlaps,"browser_playback_visual":"NOT_RUN","game_integration":"NOT_RUN"}
    (OUT/"html-check.json").write_text(json.dumps(report,indent=2)+"\n",encoding="utf-8")
    print(json.dumps({"html":"comparison.html","timing":boundaries,"max_face_overlap":{k:v["longest_contiguous_ms"] for k,v in overlaps.items()}},indent=2))


if __name__=="__main__":
    main()
