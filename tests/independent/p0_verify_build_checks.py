# Assembles checks.json from per-suite outputs and the offline pixel analysis (P0-VERIFY). Run: python -I this.py
import json
O = 'C:/godot/greenvader/evidence/p0-verify/independent/'
checks = []
v1 = json.load(open(O + 'v1-input-checks.json'))['checks']
for c in v1:
    c = dict(c)
    c['evidence'] = 'v1-input-stdout.log, v1-input-checks.json, v1-input-frames.log'
    checks.append(c)
analysis = json.load(open(O + 'analysis.json'))
self_test = analysis[0]
rows = analysis[1:]


def tag_rows(tag, prefix=None):
    return [r for r in rows if r['tag'] == tag and (prefix is None or r['label'].startswith(prefix))]


def res(ok):
    return 'PASS' if ok else 'FAIL'


checks.append({'id': 'V2-SELFTEST', 'condition': 'Block-uniformity detector detects a single bad pixel and a 1px shift, passes a clean image', 'result': res(self_test['ok']), 'observed': self_test, 'evidence': 'analysis.json'})
infos = {t: json.load(open(O + t + '-info.json')) for t in ['v2-1280x720', 'v2-1366x768', 'v2-1920x1080']}
for tag, mode in [('v2-1280x720', 'windowed'), ('v2-1366x768', 'windowed'), ('v2-1920x1080', 'fullscreen (WINDOW_MODE_FULLSCREEN=3, non-exclusive)')]:
    st = tag_rows(tag, 'static')
    allr = tag_rows(tag)
    ok = all(r['margins_exact_uniform'] and r['content_edge_ring_not_margin_colour'] for r in allr)
    exp = st[0]['expected']
    checks.append({'id': 'V2-LAYOUT-' + tag[3:], 'condition': 'Mode %s. Integer scale k, content rect and margins equal oracle p0_layout_oracle.ps1; margins exactly one colour; first/last content rows/cols are not margin colour' % mode,
                   'result': res(ok), 'observed': {'actual_client_size': str(infos[tag]['window_size']), 'window_mode_enum': infos[tag]['window_mode'], 'oracle_expected': exp, 'margin_colour_observed': st[0].get('margin_color') or 'none (no margins)',
                   'images_checked': len(allr), 'note': 'windowed screen capture: bottom 12x12 client px corners are DWM rounded-window artefacts, masked for the margin test; PrintWindow cross-check has no such artefact'}, 'evidence': tag + '-static-sunny-a.png, analysis.json'})
    ok2 = all(r['blocks_all_uniform'] for r in st)
    checks.append({'id': 'V2-BLOCKS-' + tag[3:], 'condition': 'Static frames: every k x k block of the content area is a single colour (non-uniform blocks outside window-corner artefacts = 0)',
                   'result': res(ok2), 'observed': {r['label']: {'nonuniform_outside_corners': r['nonuniform_blocks_outside_corner_zones'], 'in_corner_artefact_zone': r['nonuniform_blocks_in_window_corner_zones'], 'total_blocks': r['total_blocks']} for r in st}, 'evidence': tag + '-static-sunny-*.png'})
    ok3 = all(r.get('pixels_differing_from_viewport_texture', -1) == 0 for r in st)
    checks.append({'id': 'V2-VPMATCH-' + tag[3:], 'condition': 'Static frames: downsampled window pixels equal the engine viewport texture (640x360) exactly (corner artefacts excluded)',
                   'result': res(ok3), 'observed': {r['label']: r.get('pixels_differing_from_viewport_texture') for r in st}, 'evidence': tag + '-static-sunny-a-vp.png'})
for pw in ['v2-pw-1280x720', 'v2-pw-1366x768']:
    rs = tag_rows(pw)
    ok = all(r['margins_exact_uniform'] and r['content_edge_ring_not_margin_colour'] and r['blocks_all_uniform_incl_corner_pixels'] for r in rs if r['capture_method'] == 'PrintWindow')
    checks.append({'id': 'V2-PRINTWINDOW-' + pw[6:], 'condition': 'Cross-check with Win32 PrintWindow(PW_CLIENTONLY|PW_RENDERFULLCONTENT): layout equals oracle and ALL blocks uniform with no corner mask (static + night)', 'result': res(ok),
                   'observed': [{'label': r['label'], 'method': r['capture_method'], 'margin': r.get('margin_color'), 'nonuniform_all_incl_corners': r['nonuniform_blocks_outside_corner_zones'] + r['nonuniform_blocks_in_window_corner_zones']} for r in rs], 'evidence': pw + '-*-printwindow.png'})
mins = json.load(open(O + 'v2-min-checks.json'))['checks']
for c in mins:
    c = dict(c)
    c['evidence'] = 'v2-min-checks.json, v2-min-stdout.log'
    checks.append(c)
mr = tag_rows('v2-min')
ok = all(r['margins_exact_uniform'] and r['content_edge_ring_not_margin_colour'] and r['blocks_all_uniform'] for r in mr)
checks.append({'id': 'V2-MIN-IMAGES', 'condition': 'Captured images at the clamped minimum (640x360, k=1, no margins) and at 700x400 / 1000x360 (k=1, margins) match oracle', 'result': res(ok),
               'observed': [{'label': r['label'], 'size': r['image_size'], 'k': r['expected']['k'], 'L': r['expected']['L'], 'margin_ok': r['margins_exact_uniform']} for r in mr], 'evidence': 'v2-min-*.png'})
groups = ['move-D', 'move-WD', 'limit-right', 'limit-top', 'limit-left', 'limit-bottom', 'flight-moving', 'weather']
for pre in groups:
    n = 0
    bad = 0
    per = {}
    for tag in ['v2-1280x720', 'v2-1366x768', 'v2-1920x1080']:
        rs = tag_rows(tag, pre)
        n += len(rs)
        b = sum(0 if r['blocks_all_uniform'] and r['margins_exact_uniform'] else 1 for r in rs)
        bad += b
        per[tag] = {'images': len(rs), 'nonuniform_images': b}
    checks.append({'id': 'V3-GRID-' + pre, 'condition': 'Dynamic frames (%s) at 3 sizes: all k x k blocks uniform, margins exact (no blur / half-pixel offset in captured pixels)' % pre, 'result': res(n > 0 and bad == 0), 'observed': per, 'evidence': 'v2-*-%s-*.png, analysis.json' % pre})
cam = {}
d = json.load(open(O + 'v2-1366x768-captures.json'))['captures']
for lab, idx, expect in [('limit-right', 0, 960.0), ('limit-top', 1, 180.0), ('limit-left', 0, 320.0), ('limit-bottom', 1, 620.0)]:
    vals = [json.loads(r['state']['cam'].replace('(', '[').replace(')', ']'))[idx] for r in d if r['label'].startswith(lab)]
    cam[lab] = {'camera_centre_per_capture': vals, 'edge_value_reached': any(abs(v - expect) < 0.5 for v in vals), 'edge_value': expect}
checks.append({'id': 'V3-CAMERA-LIMITS', 'condition': 'Captured sequences include frames where the camera is clamped at right/top/left/bottom world limit (limit values 960/180/320/620 = world 1280x800 minus half the 640x360 view; world size read from game constants, so this is an observation of reaching the limit)',
               'result': res(all(v['edge_value_reached'] for v in cam.values())), 'observed': cam, 'evidence': 'v2-1366x768-captures.json'})
checks.append({'id': 'V3-DISTINGUISH', 'condition': 'Sunny/rain/night: hero, boar, seed projectile and water projectile can be told apart in captured images (SUBJECTIVE, verifier viewed images; see REPORT.md)', 'result': 'PASS',
               'observed': 'subjective; seed projectile in rain/night is low contrast (dull tan on grey-green) but still visible; see REPORT.md', 'evidence': 'v2-1280x720-weather-{sunny,rain,night}-flight-a.png, v3-zoom-{sunny,rain,night}.png'})
checks.append({'id': 'MANUAL-PHYSICAL-KEYBOARD-MOUSE', 'condition': 'Physical keyboard/mouse -> OS -> Godot path (W/A/S/D, real-cursor aim, clicks, Esc); sky non-response triage', 'result': 'NOT_RUN',
               'observed': 'NOT_RUN (manual confirmation by the user pending). Engine-internal injection is not evidence for the physical path.', 'evidence': ''})
json.dump({'target': '138664a (game files frozen; SHA-256 start==end)', 'checks': checks}, open(O + 'checks.json', 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
from collections import Counter
print(Counter(c['result'] for c in checks))
for c in checks:
    if c['result'] != 'PASS':
        print(c['id'], c['result'])
