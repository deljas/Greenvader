import json,sys,glob
def row(path):
    d=json.load(open(path))
    st=d['stable_at_min']; cm=d['complete_at_min']
    first_stable=min(st.values()) if st else -1
    return "%-28s allstable=%6.2f cleared=%6.2f downs=%d hits=%d stall=%5.1fs kills=%d nests=%d carrots=%d kiwis=%d assaults=%d/%d  stable=%s" % (path.split('/')[-1].replace('.json',''), d['all_stable_at_min'], d['cleared_at_min'], d['downs'], d['hits_taken'], d['stall_total_s'], d['kills'], d['nests_destroyed'], d['carrots_placed'], d['kiwis_placed'], d['assaults'], d['assaults_given_up'], {k:st[k] for k in sorted(st)})
for p in sys.argv[1:]:
    for f in sorted(glob.glob(p)):
        try: print(row(f))
        except Exception as e: print(f, 'ERR', e)
