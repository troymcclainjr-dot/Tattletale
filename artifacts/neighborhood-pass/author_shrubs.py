import json,hashlib
from pathlib import Path
Path(".work/neighborhood-pass").mkdir(parents=True, exist_ok=True)
from shapely.geometry import Polygon,Point,LineString
from shapely.ops import unary_union
r=Path.cwd();vp=r/'godot/assets/data/pen_lucy_vegetation.json';v=json.loads(vp.read_text());level=json.loads((r/'godot/assets/data/pen_lucy_level.json').read_text());homes=json.loads((r/'godot/assets/data/pen_lucy_window_homes.json').read_text());surf=json.loads((r/'godot/assets/data/pen_lucy_street_surfaces.json').read_text());yards=json.loads((r/'godot/assets/data/pen_lucy_yards.json').read_text());blocked=[Polygon(h['polygon']).buffer(.25) for h in homes['homes']];blocked +=[Polygon(p['polygon'],p['holes']) for kind in ['road','sidewalk'] for p in surf['surfaces'][kind]]
for p in level.get('porch_stairs',[]):blocked.append(LineString([(v[0],v[2]) for v in [p['approach'],p['landing']]]).buffer(.8))
for p in level.get('rear_doors',[]):blocked.append(Point(p['position'][0],p['position'][2]).buffer(1.0))
for q in yards['records']:
 if str(q['kind']).startswith('hedge'):blocked.append(Point(q['position'][0],q['position'][2]).buffer(max(q['scale'][0],q['scale'][2])*.5+.2))
zone=unary_union(blocked);plants=[]
for i,p in enumerate(v['plants']):
 if not p['kind'].startswith('bush'):continue
 at=Point(p['position'][0],p['position'][2]);clear=zone.distance(at);target=min(1.65,max(p['radius'],p['radius']*1.4));radius=max(p['radius'],min(target,clear-.15));plants.append(dict(index=i,radius=round(radius,3),height=round(min(1.85,max(1.25,p['height']*1.8)),3)))
out=dict(version=1,source_sha256=hashlib.sha256(vp.read_bytes()).hexdigest(),plants=plants,audit=dict(shrubs=len(plants),widened=sum(p['radius']>v['plants'][p['index']]['radius']+.01 for p in plants),minimum_height=1.25,maximum_height=1.85,clearance='Original radius retained at constrained sites; expansion leaves15cm to pavement, architecture, porch/rear access and preserved hedge bounds'))
(r/'godot/assets/data/pen_lucy_shrub_growth.json').write_text(json.dumps(out,separators=(',',':')));(r/'.work/neighborhood-pass/shrub-audit.json').write_text(json.dumps(out['audit'],indent=2));print(out['audit'])
