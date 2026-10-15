import json
def h(s): return tuple(int(s[i:i+2],16) for i in (0,2,4))
def lin(c):
    c/=255
    return c/12.92 if c<=0.04045 else ((c+0.055)/1.055)**2.4
def L(rgb): r,g,b=[lin(x) for x in rgb]; return 0.2126*r+0.7152*g+0.0722*b
def cr(a,b):
    la,lb=L(a),L(b)
    if la<lb: la,lb=lb,la
    return (la+0.05)/(lb+0.05)
def dist(a,b): return sum((x-y)**2 for x,y in zip(a,b))**0.5
fr={'plant w':h('ffd6de'),'plant r':h('e4566b'),'plant R':h('a82746')}
src={'src y':h('ffe5a0'),'src e':h('f7d5a0'),'src s':h('dcab72')}
heal={'heal b':h('9c7469'),'heal k':h('a8d65a'),'heal K':h('6fa83a')}
def f(v): return tuple(round(x*255) for x in v)
bg={'mature 3f9b4a':h('3f9b4a'),'sprout 86d65f':h('86d65f'),'seed ffe5a0':h('ffe5a0'),'wasteland':f((0.627,0.588,0.435)),'shore':f((0.804,0.749,0.561)),'shallows':f((0.42,0.69,0.7)),'water':f((0.224,0.525,0.604)),'safe ground':f((0.424,0.604,0.333))}
out={}
for gname,g in [('plant',fr)]:
    for bn,b in bg.items():
        out[bn]={k:{'contrast':round(cr(c,b),2),'dist':round(dist(c,b))} for k,c in g.items()}
out['plant_vs_source']={f'{a}|{b}':round(dist(ca,cb)) for a,ca in fr.items() for b,cb in src.items()}
out['plant_vs_heal']={f'{a}|{b}':round(dist(ca,cb)) for a,ca in fr.items() for b,cb in heal.items()}
json.dump(out,open('evidence/p1/p1-06/independent/contrast.json','w'),indent=1)
for k,v in out.items(): print(k,v)
