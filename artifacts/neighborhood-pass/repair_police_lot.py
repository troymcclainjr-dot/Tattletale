"""Terrain-exact precinct paving with matched demolition-hole rims.

Writes only police parking fields. Bays and the separate fence stay fixed.
"""
import json
from pathlib import Path
Path(".work/neighborhood-pass").mkdir(parents=True, exist_ok=True)
import numpy as np
import shapely
from shapely.geometry import Polygon, Point, box
from shapely.ops import unary_union, nearest_points
from shapely.strtree import STRtree

root=Path(__file__).resolve().parents[2]
path=root/'godot/assets/data/pen_lucy_civic_build.json'
plan=json.loads(path.read_text())
site=next(s for s in plan['sites'] if s['id']=='police')
street_data=json.loads((root/'godot/assets/data/pen_lucy_street_surfaces.json').read_text())['surfaces']
streets=unary_union([Polygon(p['polygon'],p['holes']) for kind in ['road','sidewalk'] for p in street_data[kind]])
original_lot=box(-37,-70,-9,-52)
lot=box(-37,-70,-6,-52).difference(streets)
assert lot.geom_type=='Polygon' and not lot.interiors
assert original_lot.difference(lot).area<1e-7

geom=json.loads((root/'.work/city/build/pen_lucy_geom.json').read_text())
g=next(o for o in geom['objects'] if o['name']=='Ground')
v=np.asarray(g['verts']).reshape(-1,3)[:,[0,2,1]];v[:,2]*=-1
t=v[np.asarray(g['faces']).reshape(-1,3)];xz=t[:,:,[0,2]]
near=(xz.max(axis=1)[:,0]>-40)&(xz.min(axis=1)[:,0]<-4)&(xz.max(axis=1)[:,1]>-74)&(xz.min(axis=1)[:,1]<-48)
t=t[near];materials=np.asarray(g['mats'])[near];material_names=g['matnames']
polys=shapely.polygons(t[:,:,[0,2]]);valid=shapely.area(polys)>1e-7
t=t[valid];polys=polys[valid];materials=materials[valid]
tree=STRtree(polys)
del geom,g,v
pieces=[];faces=[];material_areas={}

def parts(geometry):
    if geometry.is_empty:return []
    if geometry.geom_type=='Polygon':return [geometry]
    return [p for child in getattr(geometry,'geoms',[]) for p in parts(child)]

def height(tri,x,z):
    flat=tri[:,[0,2]];a,b=flat[1]-flat[0],flat[2]-flat[0]
    det=a[0]*b[1]-a[1]*b[0];p=np.array([x,z])-flat[0]
    u=(p[0]*b[1]-p[1]*b[0])/det;w=(a[0]*p[1]-a[1]*p[0])/det
    return float(tri[0,1]+u*(tri[1,1]-tri[0,1])+w*(tri[2,1]-tri[0,1]))

def rim_height(x,z):
    point=Point(x,z)
    ids=tree.query(point.buffer(1e-6),predicate='intersects')
    if len(ids):return max(height(t[i],x,z) for i in ids)
    i=tree.nearest(point);nearest=nearest_points(tree.geometries[i],point)[0]
    return height(t[i],nearest.x,nearest.y)

def append_face(vertices,target=faces):
    if Polygon([(v[0],v[2]) for v in vertices]).area>1e-9:
        target.append([[round(float(v),6) for v in point] for point in vertices])

for i in tree.query(lot,predicate='intersects'):
    clipped=polys[i].intersection(lot)
    if clipped.area<1e-7:continue
    pieces.append(clipped)
    name=material_names[materials[i]]
    material_areas[name]=material_areas.get(name,0.)+clipped.area
    for polygon in parts(clipped):
        for tri in shapely.constrained_delaunay_triangles(polygon).geoms:
            append_face([[x,height(t[i],x,z)+.025,z] for x,z in list(tri.exterior.coords)[:3]])

holes=lot.difference(unary_union(pieces))
rim_vertices=[]
for polygon in parts(holes):
    if polygon.area<1e-7:continue
    for tri in shapely.constrained_delaunay_triangles(polygon).geoms:
        coords=list(tri.exterior.coords)[:3]
        append_face([[x,rim_height(x,z)+.025,z] for x,z in coords])
    rim_vertices.extend(polygon.exterior.coords)

# Paint samples the finished mesh, including the matched hole surfaces.
finished=np.asarray(faces);finished_polys=shapely.polygons(finished[:,:,[0,2]])
finished_tree=STRtree(finished_polys)
def top(x,z):
    ids=finished_tree.query(Point(x,z).buffer(2e-6),predicate='intersects')
    assert len(ids),(x,z,'point outside final parking mesh')
    return max(height(finished[i],x,z) for i in ids)

stripes=[]
for x in [-36.1+i*2.8 for i in range(8)]:
    for start in [-69.7,-57.3]:
        for i in range(10):
            z=start+.25+i*.5
            stripes.append({'position':[round(x,4),round(top(x,z)+.017,6),round(z,4)],'size':[.09,.014,.5],'purpose':'parking_bay_divider'})

# Repair all remaining old-building holes outside the enlarged parking surface.
surround=[]
for patch in site.get('terrain_patches',[]):
    for original in patch['triangles']:
        tri=np.asarray(original,dtype=float)
        for polygon in parts(Polygon(tri[:,[0,2]]).difference(lot)):
            if polygon.area<1e-8:continue
            for piece in shapely.constrained_delaunay_triangles(polygon).geoms:
                append_face([[x,height(tri,x,z),z] for x,z in list(piece.exterior.coords)[:3]],surround)

coverage=unary_union(finished_polys)
rim_error=max(abs(top(x,z)-(rim_height(x,z)+.025)) for x,z in rim_vertices)
source_grass=unary_union([polys[i] for i in range(len(polys)) if material_names[materials[i]]=='grass'])
former_front_garden=source_grass.intersection(box(-12,-60,-6,-55.5))
remaining_garden=former_front_garden.difference(lot)
assert coverage.difference(lot).area<.0001
assert lot.difference(coverage).area<.0001
assert lot.intersection(streets).area<1e-8
assert remaining_garden.area<1e-5
assert rim_error<.001
audit=dict(site['parking_height_audit'])
audit.update({'source':'Exported Ground barycentric heights and matched source-terrain rim vertices; legacy fit plane retained only for external fallback',
              'method':'Exact Ground triangle clipping at +25mm; removed-building holes triangulated from matching terrain-rim heights; east apron clipped to existing sidewalk',
              'triangles':len(faces),'uncovered_m2':round(holes.area,4),'bay_count':14,'bay_width_m':2.8,'bay_depth_m':5,'aisle_width_m':7.4,
              'lot_area_m2':round(lot.area,4),'east_apron_added_m2':round(lot.difference(original_lot).area,4),
              'road_sidewalk_overlap_m2':round(lot.intersection(streets).area,8),
              'former_front_garden_area_m2':round(former_front_garden.area,4),'former_front_garden_uncovered_m2':round(remaining_garden.area,8),
              'source_material_areas_m2':{k:round(v,4) for k,v in material_areas.items()},
              'maximum_filled_hole_rim_error_m':round(rim_error,8),
              'coverage_missing_m2':round(lot.difference(coverage).area,8),'legacy_plane_used_for_mesh':False})
surround_audit={'surround_triangles':len(surround),'surround_overlap_lot_m2':0.,'height_method':'Original patch triangles exactly reclipped outside enlarged sidewalk-clipped parking polygon'}

# Reload to preserve concurrent changes to every non-parking field.
latest=json.loads(path.read_text());destination=next(s for s in latest['sites'] if s['id']=='police')
destination.update(parking_lot_xz=list(lot.exterior.coords),parking_triangles=faces,parking_stripes=stripes,
                   parking_height_audit=audit,parking_surround_triangles=surround,parking_surround_audit=surround_audit)
path.write_text(json.dumps(latest,indent=2))
(root/'.work/neighborhood-pass/police-lot-report.json').write_text(json.dumps(audit,indent=2))
print(json.dumps(audit,indent=2))
