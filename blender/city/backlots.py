"""Deterministic, source-surface checked side/rear parking and dumpster additions."""
import json, math, hashlib
from pathlib import Path
from collections import Counter
import numpy as np
import shapely
from shapely.geometry import Polygon, Point, LineString, shape
from shapely.ops import unary_union
from shapely.strtree import STRtree

ROOT=Path(__file__).resolve().parents[2]
WORK=ROOT/'.work/courts-lots-pass'
WORK.mkdir(parents=True,exist_ok=True)
source_hashes={}
def read(p):
 data=(ROOT/p).read_bytes()
 source_hashes[p]=hashlib.sha256(data).hexdigest()
 return json.loads(data)
source=read('.work/city/build/pen_lucy_geom.json')
print('source loaded',flush=True)
ground=next(o for o in source['objects'] if o['name']=='Ground')
v=np.array(ground['verts']).reshape(-1,3)[:,[0,2,1]];v[:,2]*=-1
tri=v[np.array(ground['faces']).reshape(-1,3)]
polys=[Polygon(t[:,[0,2]]) for t in tri]
tree=STRtree(polys)
print('ground triangles',len(polys),flush=True)
materials=np.array(ground['mats'])
def surface_at(x,z):
 p=Point(x,z)
 for i in tree.query(p):
  if polys[i].area>1e-8 and polys[i].buffer(1e-8).covers(p):
   t=tri[i]; a=np.array([[t[0,0],t[0,2],1],[t[1,0],t[1,2],1],[t[2,0],t[2,2],1]])
   y=float(np.array([x,z,1])@np.linalg.solve(a,t[:,1]))
   return y,ground['matnames'][int(materials[i])]
 return None,None
def paved_deficit(poly):
 indices=tree.query(poly.buffer(.03))
 local=[polys[i] for i in indices if ground['matnames'][int(materials[i])] in ('alley','asphalt') and polys[i].area>1e-8]
 return poly.difference(shapely.union_all(shapely.set_precision(local,.001)).buffer(.025)).area
streets=read('godot/assets/data/pen_lucy_street_surfaces.json')['surfaces']
roads=unary_union([Polygon(p['polygon'],p['holes']) for p in streets['road']])
walks=unary_union([Polygon(p['polygon'],p['holes']) for p in streets['sidewalk']])
level=read('godot/assets/data/pen_lucy_level.json')
civic=read('godot/assets/data/pen_lucy_civic_build.json')['sites']
business=read('godot/assets/data/pen_lucy_new_businesses.json')['businesses']
removed={bid for s in civic for bid in s['demolition_ids']}|{bid for b in business for bid in b['building_ids']}
buildings=[b for b in read('artifacts/civic-plan/map-source.json')['buildings'] if b['p']['osm_id'] not in removed]
building_polys=[shape(b['polygon']) for b in buildings]+[Polygon(b['polygon']) for b in business]+[Polygon(s['footprint_xz']) for s in civic]
buildtree=STRtree(building_polys)
exclusions=[]
for s in civic:
 if 'landscape_clear_zone' in s: exclusions.append(shape(s['landscape_clear_zone']))
 else: exclusions.append(Polygon(s['footprint_xz']).buffer(8))
for b in business: exclusions.append(Polygon(b['clearance_polygon']))
reserve=unary_union(exclusions)
doors=[]
for d in level['rear_doors']:
 if d['building_id'] in removed:continue
 p=np.array(d['position'])[[0,2]];n=np.array(d['normal'])[[0,2]]
 doors.append(LineString([p,p+n*2.5]).buffer(.85))
for d in level['porch_stairs']:
 if d['building_id'] in removed:continue
 p=np.array(d['landing'])[[0,2]];q=np.array(d['approach'])[[0,2]];n=np.array(d['normal'])[[0,2]]
 doors.append(LineString([p,q,q+n*1.0]).buffer(float(d['width_m'])/2+.4))
doorzone=unary_union(doors)
props=[]
for r in read('godot/assets/data/pen_lucy_yards.json')['records']:
 if r['kind'] not in ('dumpster','can','hedge0','hedge1','hedge2'):continue
 p=Point(r['position'][0],r['position'][2])
 if reserve.covers(p):continue
 radius=float(r.get('radius',.4))
 if r['kind'].startswith('hedge'):radius=max(float(r['scale'][0]),float(r['scale'][2]))*.5
 props.append(p.buffer(radius+.2))
for r in read('godot/assets/data/pen_lucy_vegetation.json')['plants']:
 if r['kind'].startswith('tree'):props.append(Point(r['position'][0],r['position'][2]).buffer(float(r.get('trunk_radius',.3))+.45))
prop_tree=STRtree(props)
selected=[]; rejected=Counter()
def rectangle(x,z,yaw,width,length):
 right=np.array([math.cos(yaw),-math.sin(yaw)]);forward=np.array([math.sin(yaw),math.cos(yaw)])
 return Polygon([np.array([x,z])+right*a*width/2+forward*b*length/2 for a,b in [(-1,-1),(1,-1),(1,1),(-1,1)]])
def candidate(x,z,yaw,kind,bid,identity=None,mandatory=False,outward=None):
 width,length=(1.92,1.18) if kind=='dumpster' else (1.84,4.44)
 footprint=rectangle(x,z,yaw,width,length)
 clearance=footprint.buffer(.22)
 reason=None
 if any(clearance.intersects(building_polys[i]) for i in buildtree.query(clearance)):reason='building'
 elif clearance.intersects(roads) or clearance.intersects(walks):reason='public_path'
 elif clearance.intersects(doorzone):reason='entrance'
 elif any(clearance.intersects(props[i]) for i in prop_tree.query(clearance)):reason='yard_or_tree'
 elif not mandatory and clearance.intersects(reserve):reason='civic_reservation'
 elif paved_deficit(footprint)>.015:reason='unpaved'
 elif any(clearance.intersects(s['_poly'].buffer(.4)) for s in selected):reason='new_prop'
 elif not mandatory and any(Point(x,z).distance(Point(s['position'][0],s['position'][2]))<(26 if kind!='dumpster' else 20) for s in selected):reason='spacing'
 # A parallel parking bay retains an adjacent 2.4m service/walking lane.
 if not reason and outward is not None and kind!='dumpster':
  lane=rectangle(x+outward[0]*2.4,z+outward[1]*2.4,yaw,2.4,5.0)
  if paved_deficit(lane)>.025 or any(lane.intersects(building_polys[i]) for i in buildtree.query(lane)):reason='service_lane'
 heights=[]
 if not reason:
  for xx,zz in list(footprint.exterior.coords)[:-1]+[(x,z)]:
   yy,mat=surface_at(xx,zz)
   if yy is None:reason='no_ground';break
   heights.append(yy)
  if heights and max(heights)-min(heights)>.40:reason='grade'
 if reason:
  rejected[reason]+=1
  return reason
 yy,mat=surface_at(x,z)
 record={'id':identity or f'Backlot{kind.title()}_{len(selected):02d}','kind':kind,'position':[round(x,4),round(yy,4),round(z,4)],'yaw':round(yaw,7),'building_id':bid,'mandatory':mandatory,'paved_area_m2':round(footprint.area,3),'paved_coverage':1.0,'max_corner_grade_m':round(max(heights)-min(heights),4),'source_surface':mat,'_poly':footprint}
 if kind!='dumpster':record.update(site='backlot',paint=len(selected)%6)
 selected.append(record)
 return None

mandatory=[(215.05,-49.2,-math.pi/2,'dumpster','w336336837','WyanokeBldg219Dumpster'),(181.2,-211.0,-math.pi/2,'dumpster','w336338569','CatorMarketDumpster'),(188.9,-216.5,0,'compact','w336337537','CatorAcrossGapCar')]
for x,z,yaw,kind,bid,identity in mandatory:
 result=candidate(x,z,yaw,kind,bid,identity,True)
 print('MANDATORY',identity,result or 'PASS')
 if result:
  found=False
  for dz in [0,-.5,.5,-1,1,-1.5,1.5,-2,2]:
   for dx in [0,-.3,.3,-.6,.6,-.9,.9]:
    if not candidate(x+dx,z+dz,yaw,kind,bid,identity,True):found=True;break
   if found:break
  if not found:print('UNRESOLVED',identity)

# Stable shuffled building order distributes sparse additions across the map.
buildings.sort(key=lambda b:hashlib.sha256(b['p']['osm_id'].encode()).hexdigest())
for kind,target in [('compact',13),('dumpster',20)]:
 for b in buildings:
  if sum(s['kind']==kind for s in selected)>=target:break
  poly=shape(b['polygon']);coords=list(poly.exterior.coords)
  if poly.area<18:continue
  found=False
  for a,c in zip(coords,coords[1:]):
   a=np.array(a);c=np.array(c);edge=c-a;length=np.linalg.norm(edge)
   if length<(6 if kind!='dumpster' else 3):continue
   tangent=edge/length;out=np.array([-tangent[1],tangent[0]])
   if poly.covers(Point((a+c)/2+out*.1)):out=-out
   # Stay away from street-facing walls; these are rear/side service placements.
   midpoint=(a+c)/2
   if roads.distance(Point(midpoint))<9:continue
   yaw=math.atan2(tangent[0],tangent[1]) if kind!='dumpster' else math.atan2(out[0],out[1])
   for fraction in [.25,.75,.5,.15,.85]:
    offset=1.4 if kind!='dumpster' else 1.0
    # Row_015 imported convex wall collision spans its shallow rear notch.
    # Leave additional clearance from that actual hull, not just source walls.
    if kind=='dumpster' and b['p']['osm_id']=='w336329468':offset=1.65
    p=a+edge*fraction+out*offset
    if not candidate(*p,yaw,kind,b['p']['osm_id'],outward=out):found=True;break
   if found:break

output={'version':1,'coordinate_system':'Godot x east,y up,z south','generator':'blender/city/backlots.py','source_geometry_sha256':source_hashes['.work/city/build/pen_lucy_geom.json'],'source_files_sha256':source_hashes,'records':[{k:v for k,v in s.items() if k!='_poly'} for s in selected],'audit':{'counts':dict(Counter(s['kind'] for s in selected)),'rejections':dict(rejected),'runtime_repair':{'building_id':'w336329468','reason':'Row_015 imported convex rear wall spans the source footprint notch','outward_offset_m':1.65},'rules':['entire footprint on source alley/asphalt','no public road or sidewalk overlap','building clearance >=0.22m','rear door 2.5m approach and front stair corridor clear','existing bins hedges and tree trunks clear','cars retain adjacent 2.4m paved lane','sparse deterministic distribution']}}
(ROOT/'godot/assets/data/pen_lucy_backlots.json').write_text(json.dumps(output,indent=2)+'\n')
print(json.dumps(output['audit'],indent=2))

# Ground-truth map for visual inspection, separate from engine screenshots.
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.patches import Polygon as Patch
fig,axes=plt.subplots(1,3,figsize=(18,7))
for ax,extent in zip(axes,[(207,227,-57,-37),(166,201,-231,-195),(-180,580,-400,410)]):
 x0,x1,z0,z1=extent
 box=Polygon([(x0,z0),(x1,z0),(x1,z1),(x0,z1)])
 for i in tree.query(box) if x1-x0<100 else []:
  if not polys[i].intersects(box):continue
  col={'grass':'#b2c99d','alley':'#777b7c','asphalt':'#515658','sidewalk':'#cecebf','dirt':'#a99f86'}.get(ground['matnames'][int(materials[i])],'#b99078')
  ax.add_patch(Patch(np.asarray(polys[i].exterior.coords),facecolor=col,edgecolor='none'))
 for p in building_polys:
  if p.intersects(box):ax.add_patch(Patch(np.asarray(p.exterior.coords),facecolor='#a98270',edgecolor='#6a4940',linewidth=.5))
 for s in selected:
  p=s['_poly']
  if p.intersects(box):
   ax.add_patch(Patch(np.asarray(p.exterior.coords),facecolor='#1b6344' if s['kind']=='dumpster' else '#326dd7',edgecolor='white',linewidth=.6))
   if extent[1]-extent[0]<100:ax.text(s['position'][0],s['position'][2]-1,s['id'],fontsize=6)
 ax.set_xlim(x0,x1);ax.set_ylim(z1,z0);ax.set_aspect('equal');ax.grid(alpha=.2)
fig.tight_layout();fig.savefig(WORK/'backlot-placement-map.png',dpi=150)
