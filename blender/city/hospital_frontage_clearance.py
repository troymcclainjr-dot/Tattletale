"""Keep preserved residential forecourts outside hospital landscape overlays.

The original five-metre building buffer does not cover every front yard. Use
the exported stair approach and exact public sidewalk to retain the whole
private frontage, including its existing lawn and path partition.
"""
import json
import hashlib
from pathlib import Path
import numpy as np
import shapely
from shapely.geometry import Point, Polygon
from shapely.ops import nearest_points, unary_union

ROOT = Path(__file__).resolve().parents[2]


def frontage_clearance(site, homes, stairs, sidewalk):
    retained = {entry['id'] for entry in site['preserve_buildings']}
    homes = {home['id']: home for home in homes if home['id'] in retained}
    regions, audit = [], []
    for stair in stairs:
        home = homes.get(stair['building_id'])
        if not home or not home.get('residential'):
            continue
        normal = np.asarray(stair['normal'], float)[[0, 2]]
        normal /= np.linalg.norm(normal)
        tangent = np.array([normal[1], -normal[0]])
        footprint = np.asarray(home['polygon'], float)
        lo, hi = min(footprint @ tangent) - .06, max(footprint @ tangent) + .06
        landing = np.asarray(stair['landing'], float)[[0, 2]]
        approach = np.asarray(stair['approach'], float)[[0, 2]]
        walk_edge = np.asarray(nearest_points(Point(approach), sidewalk)[1].coords[0])
        start, end = float(landing @ normal) - .2, float(walk_edge @ normal) + .12
        if end - start < .5 or end - start > 16 or hi - lo < 1:
            continue
        region = Polygon([tangent * u + normal * v for u, v in
                          [(lo, start), (hi, start), (hi, end), (lo, end)]])
        regions.append(region)
        audit.append({'building_id': home['id'], 'area_m2': round(region.area, 4)})
    return unary_union(regions), audit


def load_clearance():
    data = ROOT / 'godot/assets/data'
    read = lambda name: json.loads((data / name).read_text())
    site = next(s for s in read('pen_lucy_civic_build.json')['sites'] if s['id'] == 'hospital')
    sidewalk = unary_union([Polygon(p['polygon'], p.get('holes', []))
                            for p in read('pen_lucy_street_surfaces.json')['surfaces']['sidewalk']])
    return frontage_clearance(site, read('pen_lucy_window_homes.json')['homes'],
                              read('pen_lucy_level.json')['porch_stairs'], sidewalk)


def clip_triangles(triangles, exclusion):
    """Trim only touched triangles; keep retained vertices on the same plane."""
    result, removed_area = [], 0.0
    for raw in triangles:
        tri = np.asarray(raw, float)
        polygon = Polygon(tri[:, [0, 2]])
        overlap = polygon.intersection(exclusion)
        if overlap.area < 1e-9:
            result.append(raw)
            continue
        removed_area += overlap.area
        remainder = polygon.difference(exclusion)
        plane = np.linalg.solve(np.column_stack([tri[:, [0, 2]], np.ones(3)]), tri[:, 1])
        for part in shapely.get_parts(remainder):
            if part.geom_type != 'Polygon' or part.area < 1e-9:
                continue
            for piece in shapely.constrained_delaunay_triangles(part).geoms:
                coordinates = np.asarray(piece.exterior.coords)[:3]
                heights = np.column_stack([coordinates, np.ones(3)]) @ plane
                result.append(np.column_stack([coordinates[:, 0], heights, coordinates[:, 1]]).round(5).tolist())
    return result, removed_area


def main():
    """Selective data publication; no city rebuild or changed terrain heights."""
    path = ROOT / 'godot/assets/data/pen_lucy_hospital_grounds.json'
    data = json.loads(path.read_text())
    exclusion, frontages = load_clearance()
    signature = hashlib.sha256(exclusion.wkb).hexdigest()
    if data['audit'].get('frontage_clearance_signature') == signature:
        print('Preserved frontages already clear; no publication changes')
        return
    for finish in ['asphalt', 'walk', 'paint', 'repair']:
        overlap = sum(Polygon(np.asarray(t)[:, [0, 2]]).intersection(exclusion).area
                      for t in data['triangles'][finish])
        if overlap > .001:
            raise ValueError(f'Frontage correction would affect {finish}: {overlap} m²; review required')
    before = data['triangles']['landscape']
    data['triangles']['landscape'], removed = clip_triangles(before, exclusion)
    # Keep the campus's coverage/audit consistent with its physical triangles.
    coverage = shapely.geometry.shape(data['coverage']).difference(exclusion)
    data['coverage'] = shapely.geometry.mapping(coverage)
    data['audit']['campus_area_m2'] = round(coverage.area, 3)
    data['audit']['triangle_counts']['landscape'] = len(data['triangles']['landscape'])
    data['audit']['preserved_frontages'] = frontages
    data['audit']['frontage_clearance_signature'] = signature
    data['audit']['residential_frontage_overlap_m2'] = 0.0
    data['audit']['frontage_landscape_removed_m2'] = round(removed, 6)
    path.write_text(json.dumps(data, separators=(',', ':')))
    print(json.dumps({'frontages': len(frontages), 'removed_landscape_m2': round(removed, 6),
                      'triangles_before': len(before), 'triangles_after': len(data['triangles']['landscape'])}))


if __name__ == '__main__':
    main()
