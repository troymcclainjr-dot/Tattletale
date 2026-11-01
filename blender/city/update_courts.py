"""Re-fit court overlays against existing exported Ground triangles, without a GLB rebuild.

Run: .work/city/venv/Scripts/python.exe blender/city/update_courts.py --publish
Default writes reviewable metadata under .work/courts-lots-pass/generated/. The
normal process.py pipeline uses the same court selector and remains authoritative
for full source builds. This incremental path preserves every unrelated record.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path

import laspy
import numpy as np
import shapely
from pyproj import CRS, Transformer
from shapely.geometry import Polygon, Point, shape
from shapely.ops import unary_union
from shapely.strtree import STRtree

import config as C
import park_courts
from yards import atomic_json


class GroundSampler:
    """Exact barycentric heights from exported grass faces, not a fitted proxy."""
    def __init__(self, triangles):
        self.tri = triangles
        self.tree = STRtree(shapely.polygons(triangles[:, :, :2]))
        a,b = triangles[:,1,:2]-triangles[:,0,:2],triangles[:,2,:2]-triangles[:,0,:2]
        det = a[:,0]*b[:,1]-a[:,1]*b[:,0]
        self.slope = np.column_stack([b[:,1]*(triangles[:,1,2]-triangles[:,0,2])-a[:,1]*(triangles[:,2,2]-triangles[:,0,2]),
            a[:,0]*(triangles[:,2,2]-triangles[:,0,2])-b[:,0]*(triangles[:,1,2]-triangles[:,0,2])])/det[:,None]

    def __call__(self, x, y):
        xy=np.column_stack([np.asarray(x).ravel(),np.asarray(y).ravel()])
        ix,j=self.tree.query(shapely.points(xy),predicate='intersects')
        out=np.full(len(xy),np.nan)
        out[ix]=self.tri[j,0,2]+np.sum(self.slope[j]*(xy[ix]-self.tri[j,0,:2]),axis=1)-.10
        if not np.isfinite(out).all():
            raise ValueError('Court sampler escaped existing grass: '+str(xy[~np.isfinite(out)][:3]))
        return out.reshape(np.asarray(x).shape)


def source_inputs(root, work, level):
    geometry_path=root/'.work/city/build/pen_lucy_geom.json'
    digest=hashlib.sha256(geometry_path.read_bytes()).hexdigest()
    cache=work/'ground-cache.npz'; marker=work/'ground-cache.sha256';grass_path=work/'ground-cache.wkb'
    if cache.exists() and marker.exists() and grass_path.exists() and marker.read_text()==digest:
        tri=np.load(cache)['tri'];grass=shapely.from_wkb(grass_path.read_bytes())
    else:
        data=json.loads(geometry_path.read_text())
        ground=next(o for o in data['objects'] if o['name']=='Ground')
        vertices=np.asarray(ground['verts']).reshape(-1,3)
        tri=vertices[np.asarray(ground['faces']).reshape(-1,3)]
        mats=np.asarray(ground['matnames'])[ground['mats']]
        tri=tri[mats=='grass']
        grass=shapely.union_all(shapely.set_precision(shapely.polygons(tri[:,:,:2]),.001))
        np.savez_compressed(cache,tri=tri);grass_path.write_bytes(shapely.to_wkb(grass));marker.write_text(digest)
    parks=[dict(name=p['name'],poly=Polygon([(v[0],-v[2]) for v in p['polygon']],
           [[(v[0],-v[2]) for v in r] for r in p.get('holes',[])])) for p in level['parks']]
    with laspy.open(next(Path(C.RAW).glob('*.laz'))) as f: crs=f.header.parse_crs() or CRS.from_epsg(6347)
    horizontal=crs.sub_crs_list[0] if crs.is_compound else crs
    factor=horizontal.axis_info[0].unit_conversion_factor
    tf=Transformer.from_crs('EPSG:4326',horizontal,always_xy=True)
    ox,oy=tf.transform(*level['origin_lonlat'])
    def project(xy):
        x,y=tf.transform(xy[:,0],xy[:,1])
        return np.column_stack([(np.asarray(x)-ox)*factor,(np.asarray(y)-oy)*factor])
    buildings=json.loads((root/'blender/city/data/pen_lucy_buildings.geojson').read_text())
    footprints=unary_union([shapely.transform(shape(f['geometry']),project) for f in buildings['features']])
    surfaces=json.loads((root/'godot/assets/data/pen_lucy_street_surfaces.json').read_text())['surfaces']
    zones={'grass':grass,'alley':Polygon(),'lot':Polygon()}
    for key,records in surfaces.items():
        zones[key]=unary_union([Polygon([(x,-z) for x,z in r['polygon']],
                            [[(x,-z) for x,z in ring] for ring in r['holes']]) for r in records])
    # All other hard surfaces already cut holes in the authoritative grass union.
    return parks,footprints,zones,GroundSampler(tri),digest


def reserve_metadata(plants,yards,court_space,shrub_radii=None):
    if court_space.is_empty:
        return 0,0
    before=plants['plants'];kept=[]
    for p in before:
        point=Point(p['position'][0],-p['position'][2])
        margin=float(p['trunk_radius'])+.40 if p['kind'].startswith('tree') else float((shrub_radii or {}).get(id(p),p['radius']))+1.2
        if court_space.distance(point)>margin:kept.append(p)
    plants['plants']=kept
    plants['counts'].update(trees=sum(p['kind'].startswith('tree') for p in kept),bushes=sum(p['kind'].startswith('bush') for p in kept))
    records=[]
    for r in yards['records']:
        radius=float(r.get('radius',.24))
        if r['kind'].startswith('hedge'):
            radius=math.hypot(float(r['scale'][0]),float(r['scale'][2]))*.5
        if court_space.distance(Point(r['position'][0],-r['position'][2]))>radius+.25:records.append(r)
    removed=len(yards['records'])-len(records);yards['records']=records
    counts={kind:sum(r['kind']==kind for r in records) for kind in sorted(set(r['kind'] for r in records))}
    litter=[r for r in records if r['kind'] in ('paper','wrapper','cardboard','loose_can','cup')]
    hedges=[r for r in records if r['kind'].startswith('hedge')]
    yards['audit'].update(counts=counts,litter=len(litter),litter_cells=len({(math.floor(r['position'][0]/48),math.floor(r['position'][2]/48)) for r in litter}),
        hedge_rows=len(hedges),hedge_homes=len({r['building_id'] for r in hedges}),hedge_length_m=round(sum(r['scale'][0] for r in hedges),2),
        court_overlap_m2=0.0,court_reserved_records_removed=removed)
    return len(before)-len(kept),removed


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--publish',action='store_true');args=parser.parse_args()
    root=Path(C.ROOT);work=root/'.work/courts-lots-pass';work.mkdir(parents=True,exist_ok=True)
    data=root/'godot/assets/data';output=data if args.publish else work/'generated';output.mkdir(parents=True,exist_ok=True)
    level=json.loads((data/'pen_lucy_level.json').read_text())
    parks,footprints,zones,height,digest=source_inputs(root,work,level)
    # Current metadata is authoritative. Restoring the old reservation baseline
    # would silently undo unrelated vegetation/yard fixes from later passes.
    plants=json.loads((data/'pen_lucy_vegetation.json').read_text());yards=json.loads((data/'pen_lucy_yards.json').read_text())
    source_vegetation_digest=hashlib.sha256((data/'pen_lucy_vegetation.json').read_bytes()).hexdigest()
    growth_path=data/'pen_lucy_shrub_growth.json'
    growth=json.loads(growth_path.read_text()) if growth_path.exists() else {}
    growth_valid=growth.get('source_sha256')==source_vegetation_digest
    shrub_radii={id(plants['plants'][r['index']]):r['radius'] for r in growth['plants']} if growth_valid else {}
    previous=json.loads((data/'pen_lucy_courts.json').read_text())
    greens,inventory=park_courts.green_spaces(parks,zones['grass'])
    park_courts.bind_court_identities(greens)
    forbidden=unary_union([footprints,zones['road'],zones['sidewalk'],zones['alley'],zones['lot'],park_courts.civic_clearance_space(data)])
    records=[];coverage=[];changes=[]
    for original in previous['courts']:
        green=next((g for g in greens if g.get('court_id')==original['id']),None)
        if green is None:
            raise ValueError('Original court green missing: '+original['id'])
        if green.get('court_removed',False):
            coverage.append({'court_id':original['id'],'green_id':green['id'],'status':'excluded','reason':'removed_at_user_request'})
            changes.append({'id':original['id'],'change':'removed'})
            continue
        if original['kind']=='full':
            records.append(original)
            coverage.append({'court_id':original['id'],'green_id':green['id'],'status':'covered','reason':'existing_full_court_preserved'})
            continue
        selected,attempts=park_courts.select([green],forbidden,height,with_audit=True)
        coverage.extend(attempts)
        if selected and selected[0]['length']>=18:
            replacement=park_courts.record_for(selected[0],0)
            records.append(replacement)
            changes.append({'id':original['id'],'change':'upgraded_to_full','width_m':replacement['width_m'],'length_m':replacement['length_m']})
        else:
            records.append(original)
            changes.append({'id':original['id'],'change':'half_retained_no_safe_full_fit'})
    space=unary_union([Polygon([(x,-z) for x,z in c['footprint']]) for c in records])
    audit=dict(previous['audit'])
    audit.update(courts=len(records),hoops=sum(len(c['hoops']) for c in records),full_courts=sum(c['kind']=='full' for c in records),
        triangles=sum(c['mesh']['triangles'] for c in records),green_coverage=coverage,green_inventory=inventory,layout_changes=changes,
        max_court_grade=max(c['court_grade'] for c in records),max_apron_slope_deg=max(c['max_apron_slope_deg'] for c in records),
        max_fill_m=max(c['max_fill_m'] for c in records),road_building_overlap_m2=sum(c['road_building_overlap_m2'] for c in records),
        covered_greens=len(records),excluded_greens=len(greens)-len(records))
    before_plants=list(plants['plants'])
    removed,props=reserve_metadata(plants,yards,space,shrub_radii)
    audit.update(retained_trees=plants['counts']['trees'],retained_bushes=plants['counts']['bushes'],removed_vegetation_records=removed,
                 source_ground_sha256=digest,source_height_method='exact exported grass triangles',reservation_records_removed=props)
    courts={'version':1,'courts':records,'audit':audit}
    level['construction_audit']['park_courts']=audit
    for name,payload in (('pen_lucy_courts.json',courts),('pen_lucy_vegetation.json',plants),('pen_lucy_yards.json',yards),('pen_lucy_level.json',level)):
        atomic_json(output/name,payload)
    if growth_valid:
        new_index={id(p):i for i,p in enumerate(plants['plants'])}
        growth['plants']=[dict(r,index=new_index[id(before_plants[r['index']])]) for r in growth['plants'] if id(before_plants[r['index']]) in new_index]
        growth['source_sha256']=hashlib.sha256((output/'pen_lucy_vegetation.json').read_bytes()).hexdigest()
        atomic_json(output/growth_path.name,growth)
    atomic_json(work/'coverage-audit.json',audit)
    print(json.dumps({k:v for k,v in audit.items() if k not in ('green_inventory','green_coverage')},indent=2))
    print('Published' if args.publish else 'Prepared',output)


if __name__=='__main__':main()
