#!/bin/bash
cd C:/godot/greenvader
python -I - "$1" <<'PY'
import hashlib,os,sys,json
out={}
for root in ["scripts","scenes","data"]:
    for d,_,fs in os.walk(root):
        for f in sorted(fs):
            p=os.path.join(d,f).replace("\\","/")
            out[p]=hashlib.sha256(open(p,"rb").read()).hexdigest()
out["project.godot"]=hashlib.sha256(open("project.godot","rb").read()).hexdigest()
json.dump(out,open(sys.argv[1],"w"),indent=1,sort_keys=True)
print(len(out),"files")
PY
