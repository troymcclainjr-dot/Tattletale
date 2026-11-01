import json,numpy as np,shapely
from pathlib import Path
from shapely.geometry import Polygon
from shapely.strtree import STRtree
root=Path(__file__).resolve().parents[2];data=json.loads((root/'.work/city/build/pen_lucy_geom.json').read_text());tri=[]
for o in data['objects']:
 if not o['name'].startswith(('Row_','Bldg_')):continue
 v=np.array(o['verts']).reshape(-1,3)[:,:2];v[:,1]*=-1;tri.append(v[np.array(o['faces']).reshape(-1,3)])
polys=shapely.polygons(np.concatenate(tri));polys=polys[shapely.area(polys)>.00001];tree=STRtree(polys)
candidates=json.loads((root/'artifacts/civic-plan/candidates.json').read_text());valid=[]
for p in candidates:
 footprint=Polygon(p['polygon']);access=Polygon(p['access']);ids=tree.query(footprint,predicate='intersects');drive=tree.query(access,predicate='intersects')
 if len(ids) or len(drive):continue
 p['exported_architecture_overlap_m2']=0.;valid.append(p)
(root/'artifacts/civic-plan/validated-candidates.json').write_text(json.dumps(valid));print('Exact exported architecture clear',len(valid))
chosen=[]
for service in ['police','fire','hospital']:
 sub=[]
 for p in sorted([q for q in valid if q['service']==service],key=lambda q:q['center_score']):
  if any(np.linalg.norm(np.array(p['position'])[::2]-np.array(q['position'])[::2])<40 for q in sub):continue
  sub.append(p);print(service,p['street'],p['position'])
  if len(sub)==6:break
