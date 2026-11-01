"""Build a terrain-sampled campus, retaining exact street and row-home exclusions."""
import json, math
from pathlib import Path
import numpy as np
import shapely
from shapely.geometry import Point, Polygon, LineString, box, shape, mapping
from shapely.ops import unary_union, nearest_points
from shapely.strtree import STRtree
from terrain_datum import TerrainDatum
from hospital_frontage_clearance import frontage_clearance

ROOT = Path(__file__).resolve().parents[2]
plan = json.loads((ROOT/'godot/assets/data/pen_lucy_civic_build.json').read_text())
site = next(s for s in plan['sites'] if s['id'] == 'hospital')
zone = shape(site['landscape_clear_zone'])
surfaces = json.loads((ROOT/'godot/assets/data/pen_lucy_street_surfaces.json').read_text())['surfaces']
streets = unary_union([Polygon(p['polygon'], p['holes']) for kind in ['road', 'sidewalk'] for p in surfaces[kind]])
preserved = unary_union([Polygon(b['footprint']) for b in site['preserve_buildings']]).buffer(5)
# Actual hospital model is 55 m wide, not the conservative 56 m planning envelope.
footprint = box(401, -185.5, 439, -130.5)
sidewalks = unary_union([Polygon(p['polygon'], p['holes']) for p in surfaces['sidewalk']])
frontages, frontage_audit = frontage_clearance(site,
    json.loads((ROOT/'godot/assets/data/pen_lucy_window_homes.json').read_text())['homes'],
    json.loads((ROOT/'godot/assets/data/pen_lucy_level.json').read_text())['porch_stairs'], sidewalks)
domain = zone.difference(streets).difference(preserved).difference(footprint).difference(frontages)

geom = json.loads((ROOT/'.work/city/build/pen_lucy_geom.json').read_text())
ground = next(o for o in geom['objects'] if o['name'] == 'Ground')
verts = np.asarray(ground['verts']).reshape(-1, 3)[:, [0, 2, 1]]
verts[:, 2] *= -1
all_triangles = verts[np.asarray(ground['faces']).reshape(-1, 3)]
all_materials = np.asarray([ground['matnames'][i] for i in ground['mats']])
xz = all_triangles[:, :, [0, 2]]
low, high = xz.min(axis=1), xz.max(axis=1)
near = (high[:, 0] > 375) & (low[:, 0] < 510) & (high[:, 1] > -220) & (low[:, 1] < -60)
triangles = all_triangles[near]
flat = triangles[:, :, [0, 2]]
edge_a, edge_b = flat[:, 1]-flat[:, 0], flat[:, 2]-flat[:, 0]
det = edge_a[:, 0]*edge_b[:, 1]-edge_a[:, 1]*edge_b[:, 0]
valid = abs(det) > 1e-6
triangles, flat, det = triangles[valid], flat[valid], det[valid]
# All campus finishes share one graded datum. Sampling the original raised
# grass/sidewalk tops independently leaves open steps across the parking lot.
triangles = TerrainDatum(triangles, all_materials[near][valid]).normalize(triangles, 0.0)
BASE_OFFSET = .125  # clears old 10cm private lawn edges, below public 15cm walks
tree = STRtree(shapely.polygons(flat))
del geom, ground, verts, all_triangles, xz

height_cache = {}
def ground_y(x, z):
    point = Point(x, z)
    ids = tree.query(point, predicate='intersects')
    if len(ids):
        i = ids[0]
    else:
        i = tree.nearest(point)
        closest = nearest_points(tree.geometries[i], point)[0]
        x, z = closest.x, closest.y
    a, b = flat[i, 1]-flat[i, 0], flat[i, 2]-flat[i, 0]
    p = np.array([x, z])-flat[i, 0]
    u = (p[0]*b[1]-p[1]*b[0])/det[i]
    w = (a[0]*p[1]-a[1]*p[0])/det[i]
    return float(triangles[i, 0, 1]+u*(triangles[i, 1, 1]-triangles[i, 0, 1])+w*(triangles[i, 2, 1]-triangles[i, 0, 1]))

def elevation(x, z):
    key = (round(x, 6), round(z, 6))
    if key not in height_cache:
        terrain = ground_y(x, z) + BASE_OFFSET
        distance = footprint.distance(Point(x, z))
        grade = max(0., 1.-distance/12.)
        height_cache[key] = terrain + max(0., site['floor_y']-terrain)*grade
    return height_cache[key]

# Paved circulation follows the building's west frontage, loops south into the
# parking court, and provides a restrained north/east service lane.
asphalt = unary_union([
    box(386, -191, 401, -129), box(399, -130.5, 435, -98),
    box(399, -192, 450, -185.5), box(439, -187, 449, -137),
]).intersection(domain)
walk = unary_union([
    box(393.5, -172.0, 401, -163.0),
    box(399, -130.5, 404, -101),
    box(404, -133.0, 433, -130.5),
]).intersection(domain)
asphalt = asphalt.difference(walk)
landscape = domain.difference(unary_union([asphalt, walk]))
regions = {'asphalt': asphalt, 'walk': walk, 'landscape': landscape}
output = {key: [] for key in [*regions, 'paint']}
worst_residual = 0.

def parts(g):
    if g.is_empty: return []
    if g.geom_type == 'Polygon': return [g]
    return [p for item in getattr(g, 'geoms', []) for p in parts(item)]

def emit(coords, target, offset=0., depth=0):
    global worst_residual
    coords = np.asarray(coords, dtype=float)
    heights = np.array([elevation(x, z) for x, z in coords])
    mids = [(coords[0]+coords[1])/2, (coords[1]+coords[2])/2, (coords[2]+coords[0])/2]
    error = max(abs(elevation(*mid)-(heights[i]+heights[(i+1)%3])/2) for i, mid in enumerate(mids))
    if error > .015 and depth < 4:
        a,b,c = coords; ab,bc,ca = mids
        for child in [(a,ab,ca),(ab,b,bc),(ca,bc,c),(ab,bc,ca)]:
            emit(child,target,offset,depth+1)
        return
    worst_residual = max(worst_residual, error)
    output[target].append([[round(float(x),5),round(float(y+offset),5),round(float(z),5)] for (x,z),y in zip(coords,heights)])

def tessellate(poly, target, offset=0., grid=2.):
    if poly.is_empty: return
    x0,z0,x1,z1 = poly.bounds
    for x in np.arange(math.floor(x0/grid)*grid, x1, grid):
        for z in np.arange(math.floor(z0/grid)*grid, z1, grid):
            cell = poly.intersection(box(x,z,x+grid,z+grid))
            for p in parts(cell):
                if p.area < 1e-7: continue
                for t in shapely.constrained_delaunay_triangles(p).geoms:
                    emit(list(t.exterior.coords)[:3],target,offset)

def emit_source(coords, source, target, depth=0):
    global worst_residual
    # Interpolate each exported triangle in its own plane: shared terrain edges
    # remain exact, and former-building holes are interpolated from their rim.
    coords=np.asarray(coords,dtype=float)
    matrix=np.array([[p[0],p[2],1.] for p in source])
    plane=np.linalg.solve(matrix,np.array([p[1] for p in source]))
    def graded(p):
        y=float(np.dot([p[0],p[1],1.],plane))+BASE_OFFSET
        weight=max(0.,1.-footprint.distance(Point(*p))/12.)
        return y+max(0.,site['floor_y']-y)*weight
    ys=np.array([graded(p) for p in coords])
    mids=[(coords[0]+coords[1])/2,(coords[1]+coords[2])/2,(coords[2]+coords[0])/2]
    error=max(abs(graded(p)-(ys[i]+ys[(i+1)%3])/2) for i,p in enumerate(mids))
    if error>.025 and depth<5:
        a,b,c=coords;ab,bc,ca=mids
        for child in [(a,ab,ca),(ab,b,bc),(ca,bc,c),(ab,bc,ca)]:emit_source(child,source,target,depth+1)
        return
    worst_residual=max(worst_residual,error)
    output[target].append([[round(float(x),5),round(float(y),5),round(float(z),5)] for (x,z),y in zip(coords,ys)])

for key, region in regions.items():
    covered=[]
    for i in tree.query(region,predicate='intersects'):
        clipped=tree.geometries[i].intersection(region)
        for p in parts(clipped):
            if p.area<1e-7:continue
            covered.append(p)
            for t in shapely.constrained_delaunay_triangles(p).geoms:
                emit_source(list(t.exterior.coords)[:3],triangles[i],key)
    holes=region.difference(unary_union(covered))
    for p in parts(holes):
        if p.area<1e-6:continue
        for t in shapely.constrained_delaunay_triangles(p).geoms:
            coords=list(t.exterior.coords)[:3]
            source=np.array([[x,ground_y(x,z),z] for x,z in coords])
            emit_source(coords,source,key)

# Discard numerical slivers introduced when clipping nearly coincident edges.
for key in regions:
    output[key]=[t for t in output[key] if Polygon([(p[0],p[2]) for p in t]).area>1e-9]

# Painted lines sample the finished campus triangles, including filled holes.
finished=np.array([t for key in regions for t in output[key]])
finished_flat=finished[:,:,[0,2]]
finished_tree=STRtree(shapely.polygons(finished_flat))
def elevation(x,z):
    point=Point(x,z)
    ids=finished_tree.query(point,predicate='intersects')
    i=ids[0] if len(ids) else finished_tree.nearest(point)
    source=finished[i]
    matrix=np.array([[p[0],p[2],1.] for p in source])
    plane=np.linalg.solve(matrix,source[:,1])
    return float(np.dot([x,z,1.],plane))

# One compact parking court: two rows of five 2.7 x 5 m stalls with a 6 m aisle.
marks = []
for x0,x1 in [(408,413),(419,424)]:
    for n in range(6):
        z = -126 + n*2.7
        marks.append(box(x0,z-.045,x1,z+.045))
    marks.append(box(x0-.045,-126,x0+.045,-112.5))
    for n in range(5):
        assert asphalt.covers(box(x0,-126+n*2.7,x1,-126+(n+1)*2.7)), 'Parking stall clips campus boundary'
# Ambulance approach edge guides lead from the west lane to the open canopy apron.
for z in [-148,-135]:
    marks.append(box(395,z-.06,401,z+.06))
paint = unary_union(marks).intersection(asphalt)
tessellate(paint,'paint',.012)

old_patches = unary_union([Polygon(p['polygon_xz']) for p in site.get('terrain_patches',[])])
uncovered = old_patches.difference(unary_union([domain,footprint]))
# Preserve the original demolition-hole repair outside the campus; these pieces
# use original terrain heights and need no duplicated district patch triangles.
output['repair'] = []
for p in parts(uncovered):
    for t in shapely.constrained_delaunay_triangles(p).geoms:
        output['repair'].append([[round(x,5),round(ground_y(x,z)+BASE_OFFSET,5),round(z,5)] for x,z in list(t.exterior.coords)[:3]])

data = {'version':1,'site_id':'hospital','world_origin':[0,0,0],
        'source_position':site['position'],'source_yaw':site['yaw'],
        'triangles':output,'coverage':mapping(domain),
        'audit':{'collision_layer':1,'base_offset_m':BASE_OFFSET,'floor_y':site['floor_y'],
                 'height_datum':'shared terrain below raised source finishes',
                 'campus_area_m2':round(domain.area,3),'outside_clear_zone_m2':round(domain.difference(zone).area,6),
                 'road_sidewalk_overlap_m2':round(domain.intersection(streets).area,6),
                 'preserved_5m_buffer_overlap_m2':round(domain.intersection(preserved).area,6),
                 'preserved_frontages':frontage_audit,
                 'residential_frontage_overlap_m2':round(domain.intersection(frontages).area,6),
                 'demolition_repair_outside_campus_m2':round(uncovered.area,3),
                 'triangle_counts':{k:len(v) for k,v in output.items()},
                 'max_sampled_height_residual_m':round(worst_residual,5),
                 'parking_stalls':10,'grade_collar_m':12}}
path=ROOT/'godot/assets/data/pen_lucy_hospital_grounds.json'
path.write_text(json.dumps(data,separators=(',',':')))
print(json.dumps(data['audit'],indent=2))
print('wrote',path, 'bytes',path.stat().st_size)
