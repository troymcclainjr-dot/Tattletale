import json,math
from pathlib import Path
Path(".work/neighborhood-pass").mkdir(parents=True, exist_ok=True)
import numpy as np,shapely
from shapely.geometry import Point,LineString
from shapely.ops import unary_union
from shapely.strtree import STRtree
R=Path.cwd();data=json.loads((R/'godot/assets/data/pen_lucy_power.json').read_text());geom=json.loads((R/'.work/city/build/pen_lucy_geom.json').read_text());architecture=unary_union([shapely.MultiPoint(np.array(o['verts']).reshape(-1,3)[:,[0,1]]*np.array([1,-1])).convex_hull for o in geom['objects'] if o['name'].startswith(('Row_','Bldg_'))]);g=next(o for o in geom['objects'] if o['name']=='Ground');v=np.array(g['verts']).reshape(-1,3)[:,[0,2,1]];v[:,2]*=-1;tris=v[np.array(g['faces']).reshape(-1,3)];flat=tris[:,:,[0,2]];ab=flat[:,1]-flat[:,0];ac=flat[:,2]-flat[:,0];det=ab[:,0]*ac[:,1]-ab[:,1]*ac[:,0];keep=abs(det)>1e-5;tris=tris[keep];flat=flat[keep];det=det[keep];tree=STRtree(shapely.polygons(flat))
def height(x,z):
 ids=tree.query(Point(x,z),predicate='intersects')
 if not len(ids):return None
 i=ids[0];a,b=flat[i,1]-flat[i,0],flat[i,2]-flat[i,0];p=np.array([x,z])-flat[i,0];u=(p[0]*b[1]-p[1]*b[0])/det[i];w=(a[0]*p[1]-a[1]*p[0])/det[i];return float(tris[i,0,1]+u*(tris[i,1,1]-tris[i,0,1])+w*(tris[i,2,1]-tris[i,0,1]))
from collections import Counter
degree=Counter(i for s in data['spans'] for i in [s['a'],s['b']]);edges={tuple(sorted([s['a'],s['b']])) for s in data['spans']};candidates=[]
for i,a in enumerate(data['poles']):
 for j in range(i+1,len(data['poles'])):
  b=data['poles'][j]
  if a['street']!=b['street'] or a['side']!=b['side'] or (i,j) in edges:continue
  d=math.dist(a['position'][::2],b['position'][::2])
  if 12<d<60:candidates.append((d,i,j))
added=[]
for d,i,j in sorted(candidates):
 if degree[i]>=2 or degree[j]>=2:continue
 a,b=data['poles'][i],data['poles'][j];line=LineString([a['position'][::2],b['position'][::2]])
 if architecture.buffer(1.4).intersects(line):continue
 clear=100
 for t in np.linspace(0,1,33):
  pos=np.array(a['position'])*(1-t)+np.array(b['position'])*t;y=height(pos[0],pos[2])
  if y is None:clear=-1;break
  clear=min(clear,pos[1]+9.2-.65*4*t*(1-t)-y)
 if clear<7.2:continue
 added.append(dict(a=i,b=j,min_clearance_m=round(clear,3)));degree[i]+=1;degree[j]+=1
out=dict(version=1,source_sha256=__import__('hashlib').sha256((R/'godot/assets/data/pen_lucy_power.json').read_bytes()).hexdigest(),spans=added,audit=dict(added_spans=len(added),isolated_before=sum(all(i not in [s["a"],s["b"]] for s in data["spans"]) for i in range(len(data["poles"]))),isolated_after=sum(degree[i]==0 for i in range(len(data['poles']))),validation='Same named street and curb side; <=60m; full exported architecture1.4m buffer;33 exact exported terrain clearance samples>=7.2m'))
(R/'godot/assets/data/pen_lucy_power_connections.json').write_text(json.dumps(out,indent=2));(R/'.work/neighborhood-pass/power-audit.json').write_text(json.dumps(out,indent=2));print(out['audit'])
