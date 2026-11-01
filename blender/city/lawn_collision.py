"""Small terrain-matched colliders only for lawn extensions above old paving."""
import math
import numpy as np
import shapely
from shapely.geometry import Polygon, box
from shapely.ops import unary_union
from shapely.strtree import STRtree


class Surface:
    def __init__(self, triangles):
        self.triangles = np.asarray(triangles, float)
        polygons = shapely.polygons(self.triangles[:, :, [0, 2]])
        keep = shapely.area(polygons) > 1e-9
        self.triangles = self.triangles[keep]
        self.polygons = polygons[keep]
        self.index = STRtree(self.polygons)
        matrix = np.concatenate([self.triangles[:, :, [0, 2]], np.ones((keep.sum(), 3, 1))], axis=2)
        self.planes = np.linalg.solve(matrix, self.triangles[:, :, 1, None])[:, :, 0]

    def height(self, coordinates):
        coordinates = np.asarray(coordinates)
        query = shapely.points(coordinates)
        ids = self.index.nearest(query)
        hits = self.index.query(query, predicate='intersects')
        ids[hits[0]] = hits[1]
        return np.sum(np.column_stack([coordinates, np.ones(len(coordinates))]) * self.planes[ids], axis=1)


def polygon_parts(geometry):
    if geometry.geom_type == 'Polygon':
        return [geometry] if geometry.area > 1e-8 else []
    return [part for child in getattr(geometry, 'geoms', []) for part in polygon_parts(child)]


def build(triangles, source_triangles, tolerance=.008, minimum_rise=.04):
    lawn, old = Surface(triangles), Surface(source_triangles)
    centers = lawn.triangles.mean(axis=1)
    rise = centers[:, 1] - old.height(centers[:, [0, 2]])
    selected = rise > minimum_rise
    domain = unary_union(lawn.polygons[selected])
    if domain.is_empty:
        return [], {'triangles': 0, 'area_m2': 0., 'maximum_surface_error_m': 0.}
    # Source ground continues to support lawns within the original 2.5cm
    # decorative lift. Only higher extensions need additional physics.
    cells = {}
    for part in polygon_parts(domain):
        x0, z0, x1, z1 = part.bounds
        for x in range(math.floor(x0/2)*2, math.ceil(x1/2)*2, 2):
            for z in range(math.floor(z0/2)*2, math.ceil(z1/2)*2, 2):
                if part.intersects(box(x, z, x+2, z+2)):
                    cells.setdefault((x, z), []).append(part)
    result, maximum_error = [], 0.

    def mesh_piece(region):
        emitted, worst = [], 0.
        for part in polygon_parts(region):
            # Simplify only redundant near-collinear edge samples, not the lot.
            for triangle in shapely.constrained_delaunay_triangles(part.simplify(1e-6, preserve_topology=True)).geoms:
                coordinates = np.asarray(triangle.exterior.coords)[:3]
                heights = lawn.height(coordinates)
                plane = np.linalg.solve(np.column_stack([coordinates, np.ones(3)]), heights)
                ids = lawn.index.query(triangle, predicate='intersects')
                samples = shapely.get_coordinates(shapely.intersection(lawn.polygons[ids], triangle))
                if len(samples):
                    error = np.abs(lawn.height(samples) - np.column_stack([samples, np.ones(len(samples))]) @ plane).max()
                    worst = max(worst, float(error))
                emitted.append(np.column_stack([coordinates[:, 0], heights, coordinates[:, 1]]))
        return emitted, worst

    def cell_mesh(x, z, size, domain_piece):
        nonlocal maximum_error
        region = domain_piece.intersection(box(x, z, x+size, z+size))
        if region.is_empty:
            return
        emitted, error = mesh_piece(region)
        if error > tolerance and size > .25:
            for dx, dz in [(0,0), (size/2,0), (0,size/2), (size/2,size/2)]:
                cell_mesh(x+dx, z+dz, size/2, region)
            return
        if error > tolerance:
            # Rare sharp source crease: retain exact clipped source planes.
            emitted = []
            for i in lawn.index.query(region, predicate='intersects'):
                for part in polygon_parts(lawn.polygons[i].intersection(region)):
                    for triangle in shapely.constrained_delaunay_triangles(part).geoms:
                        coordinates = np.asarray(triangle.exterior.coords)[:3]
                        heights = lawn.height(coordinates)
                        emitted.append(np.column_stack([coordinates[:, 0], heights, coordinates[:, 1]]))
            error = 0.00001
        maximum_error = max(maximum_error, error)
        result.extend(emitted)

    for (x,z), parts in sorted(cells.items()):
        cell_mesh(x, z, 2., unary_union(parts))
    audit = {'triangles': len(result), 'source_extension_triangles': int(selected.sum()),
             'area_m2': round(domain.area, 3), 'minimum_rise_m': minimum_rise,
             'maximum_surface_error_m': round(maximum_error, 6), 'tolerance_m': tolerance,
             'unchanged_lawn_triangles': int((~selected).sum()), 'initial_2m_cells': len(cells)}
    return np.asarray(result).round(5).tolist(), audit
