"""Author power metadata and civic feasibility candidates from the current city export.
Run with project's city venv. Never changes existing world objects or destinations.
"""
import json, math
from pathlib import Path
import numpy as np, shapely
from shapely.geometry import Polygon, LineString, Point, shape, box, mapping
from shapely.ops import unary_union
from shapely.affinity import rotate, translate
from shapely.strtree import STRtree
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'artifacts/civic-plan'
DATA=ROOT/'godot/assets/data'
def read(p):return json.loads(p.read_text())
def write(p,d):p.write_text(json.dumps(d,separators=(',',':')))
def xz(p):return (p[0],p[2])
src=read(OUT/'map-source.json');level=src['level']
footprints=unary_union([shape(b['polygon']) for b in src['buildings']])
parks=unary_union([Polygon([xz(v) for v in p['polygon']],[[xz(v) for v in h] for h in p['holes']]) for p in level['parks']])
courts=unary_union([Polygon(c['footprint']) for c in read(DATA/'pen_lucy_courts.json')['courts']])
surfaces=read(DATA/'pen_lucy_street_surfaces.json')['surfaces']
zones={key:unary_union([Polygon(p['polygon'],p['holes']) for p in records]) for key,records in surfaces.items()}
site=Polygon([xz(p) for p in level['site_boundary']])
area=Polygon([xz(p) for p in level['area_boundary']])
# Ground triangles are exactly the coordinates exported for the current GLB.
geom=read(ROOT/'.work/city/build/pen_lucy_geom.json')
g=next(o for o in geom['objects'] if o['name']=='Ground')
verts=np.array(g['verts']).reshape(-1,3)[:,[0,2,1]];verts[:,2]*=-1
tris=verts[np.array(g['faces']).reshape(-1,3)]
flat=tris[:,:,[0,2]]
aa=flat[:,1]-flat[:,0];bb=flat[:,2]-flat[:,0];det=aa[:,0]*bb[:,1]-aa[:,1]*bb[:,0];keep=np.abs(det)>.00001
tris=tris[keep];flat=flat[keep];det=det[keep]
tree=STRtree(shapely.polygons(flat))
def height(x,z):
 ids=tree.query(Point(x,z),predicate='intersects')
 if not len(ids):return None
 i=ids[0];a,b=flat[i,1]-flat[i,0],flat[i,2]-flat[i,0];p=np.array([x,z])-flat[i,0]
 u=(p[0]*b[1]-p[1]*b[0])/det[i];v=(a[0]*p[1]-a[1]*p[0])/det[i]
 return float(tris[i,0,1]+u*(tris[i,1,1]-tris[i,0,1])+v*(tris[i,2,1]-tris[i,0,1]))
# Reject projected actual architecture, including overhanging porches/steps.
architecture=[]
for o in geom['objects']:
 if not o['name'].startswith(('Row_','Bldg_')):continue
 v=np.array(o['verts']).reshape(-1,3)[:,[0,1]];v[:,1]*=-1
 architecture.append(shapely.MultiPoint(v).convex_hull)
architecture=unary_union(architecture)
del geom
entrances=[]
for p in level['porch_stairs']:
 entrances.append(LineString([xz(p['approach']),xz(p['landing'])]).buffer(1.6))
for p in level['rear_doors']:entrances.append(Point(xz(p['position'])).buffer(1.8))
for p in level['businesses']:entrances.append(Point(xz(p['door_position'])).buffer(2.0))
reserved=unary_union(entrances+[courts.buffer(2),architecture.buffer(.5)])
plants=read(DATA/'pen_lucy_vegetation.json')['plants']
plant_zones=unary_union([Point(xz(p['position'])).buffer(min(2.4,float(p['radius']))+.25) for p in plants])
yard=unary_union([Point(xz(p['position'])).buffer(float(p.get('radius',.4))+.4) for p in read(DATA/'pen_lucy_yards.json')['records'] if p['kind'] not in ('paper','wrapper','cardboard','loose_can','cup')])
reserved=unary_union([reserved,plant_zones,yard])
poles=[];spans=[];street_counts={};minimum=99.0
for ri,r in enumerate(level['roads']):
 if not r['name'] or float(r['sidewalk_width'])<2:continue
 line=LineString([xz(p) for p in r['points']]);last=None
 for distance in np.arange(13.,line.length-10.,29.):
  a=line.interpolate(max(0,distance-.5));b=line.interpolate(min(line.length,distance+.5));t=np.array([b.x-a.x,b.y-a.y]);t/=np.linalg.norm(t);normal=np.array([-t[1],t[0]])
  c=line.interpolate(distance);found=None
  # Consistent west/north side for continuous spans, opposite only where blocked.
  for side in [1,-1]:
   p=Point(np.array([c.x,c.y])+normal*side*(float(r['width'])/2+.42))
   if not zones['sidewalk'].buffer(.04).covers(p.buffer(.18)) or zones['road'].distance(p)<.23:continue
   if reserved.intersects(p.buffer(.18)) or not site.covers(p):continue
   if any(Point(xz(q['position'])).distance(p)<12 for q in poles):continue
   y=height(p.x,p.y)
   if y is None:continue
   found=dict(position=[round(p.x,4),round(y-.03,4),round(p.y,4)],yaw=round(math.atan2(t[0],t[1]),6),street=r['name'],side=side)
   break
  if found is None:last=None;continue
  index=len(poles);poles.append(found);street_counts[r['name']]=street_counts.get(r['name'],0)+1
  if last is not None:
   prev=poles[last];wire=LineString([xz(prev['position']),xz(found['position'])])
   if prev['side']==found['side'] and wire.length<37 and not architecture.buffer(.8).intersects(wire):
    clearance=99.
    for t_ in np.linspace(0,1,13):
     xy=wire.interpolate(t_,normalized=True);ground=height(xy.x,xy.y)
     if ground is None:clearance=-1;break
     wire_y=(1-t_)*prev['position'][1]+t_*found['position'][1]+9.2-.65*4*t_*(1-t_)
     clearance=min(clearance,wire_y-ground)
    if clearance>=7.2:
     spans.append(dict(a=last,b=index,min_clearance_m=round(clearance,3)));minimum=min(minimum,clearance)
  last=index
power=dict(version=1,poles=poles,spans=spans,audit=dict(poles=len(poles),spans=len(spans),streets=street_counts,minimum_wire_ground_clearance_m=round(minimum,3),collision_bodies=0,placement='Exact exported sidewalk/ground; reserved entrances, courts, architecture, trees and yard props',source_geometry='current .work/city/build/pen_lucy_geom.json'))
write(DATA/'pen_lucy_power.json',power)
# Street-facing proposal envelopes with a direct, clear access corridor.
blocked=unary_union([footprints.buffer(1.5),parks.buffer(1),courts.buffer(2),zones['road'].buffer(.8)])
shapely.prepare(blocked)
access_blocked=unary_union([footprints.buffer(1),courts.buffer(1),parks]);shapely.prepare(access_blocked)
candidates=[]
for kind,w,depth in [('police',20.,24.),('fire',20.,28.),('hospital',24.,28.)]:
 for r in level['roads']:
  if not r['name']:continue
  line=LineString([xz(p) for p in r['points']])
  for distance in np.arange(w/2+5,line.length-w/2-5,5):
   c=line.interpolate(distance);a=line.interpolate(distance-1);b=line.interpolate(distance+1);t=np.array([b.x-a.x,b.y-a.y]);t/=np.linalg.norm(t);n=np.array([-t[1],t[0]])
   for side,extra,angle in [(s,e,ang) for s in [-1,1] for e in [0.,8.,16.,24.,32.,40.] for ang in [0,30,-30,60,-60,90]]:
    nn=n*side; setback=float(r['width'])/2+float(r['sidewalk_width'])+2+extra
    base=np.array([c.x,c.y])+nn*setback
    corners=[base-t*w/2,base+t*w/2,base+t*w/2+nn*depth,base-t*w/2+nn*depth]
    poly=rotate(Polygon(corners),angle,origin=tuple(base+nn*depth/2))
    corners=list(poly.exterior.coords)[:-1]
    if not site.buffer(-2).covers(poly) or blocked.intersects(poly):continue
    # Six-metre access through sidewalk (proposed curb cut), no existing homes.
    driveway=LineString([base+nn*3,np.array([c.x,c.y])]).buffer(3,cap_style=2)
    if access_blocked.intersects(driveway):continue
    p=poly.centroid;y=height(p.x,p.y)
    if y is None:continue
    ys=[height(*q) for q in corners]
    if any(v is None for v in ys) or max(ys)-min(ys)>2.5:continue
    candidates.append(dict(service=kind,street=r['name'],position=[round(p.x,3),round(y,3),round(p.y,3)],polygon=[[round(x,3),round(z,3)] for x,z in poly.exterior.coords],access=[[round(v,3) for v in q] for q in driveway.exterior.coords],width=w,depth=depth,grade_range_m=round(max(ys)-min(ys),3),center_score=Point(90,-50).distance(p)))
write(OUT/'candidates.json',candidates)
print(json.dumps(power['audit'],indent=2));print('Civic candidate counts', {s:sum(p['service']==s for p in candidates) for s in ['police','fire','hospital']})
for service in ['police','fire','hospital']:
 chosen=[]
 for p in sorted([c for c in candidates if c['service']==service],key=lambda c:c['center_score']):
  if any(Point(xz(p['position'])).distance(Point(xz(q['position'])))<45 for q in chosen):continue
  chosen.append(p)
  print(service,p['street'],p['position'],p['width'],p['depth'])
  if len(chosen)==8:break

