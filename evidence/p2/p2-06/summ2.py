import json,sys,glob,os
for p in sys.argv[1:]:
    for f in sorted(glob.glob(p)):
        d=json.load(open(f)); r=d['reach_times_min']
        print("%-22s r50=%6.2f r75=%6.2f r90=%6.2f r99=%6.2f cleared=%6.2f allstable=%6.2f carrots=%d shots_seed=%d" % (os.path.basename(f).replace('.json',''), r.get('50',-1), r.get('75',-1), r.get('90',-1), r.get('99',-1), d['cleared_at_min'], d['all_stable_at_min'], d['carrots_placed'], d['shots_seed']))
