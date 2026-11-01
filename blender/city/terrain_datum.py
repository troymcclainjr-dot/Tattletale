"""Continuous replacement terrain below independently raised material tops."""
import numpy as np
import shapely
from shapely.strtree import STRtree

MATERIAL_LIFT = {"asphalt": .01, "alley": .02, "grass": .10,
                 "sidewalk": .15, "dirt": .10, "brick": .10}


class TerrainDatum:
    def __init__(self, triangles, materials):
        self.triangles = np.asarray(triangles, float).copy()
        lifts = np.asarray([MATERIAL_LIFT.get(str(m), 0.) for m in materials])
        self.triangles[:, :, 1] -= lifts[:, None]
        vertices = self.triangles.reshape(-1, 3)
        # Recolored asphalt may be a 2cm alley instead of a 1cm lot. Reconcile
        # coincident boundaries, retaining the upper base rather than a crack.
        _, groups = np.unique(np.round(vertices[:, [0, 2]], 5), axis=0, return_inverse=True)
        heights = np.full(groups.max() + 1, -np.inf)
        np.maximum.at(heights, groups, vertices[:, 1])
        vertices[:, 1] = heights[groups]
        polygons = shapely.polygons(self.triangles[:, :, [0, 2]])
        valid = shapely.area(polygons) > 1e-9
        self.triangles = self.triangles[valid]
        self.index = STRtree(polygons[valid])
        matrix = np.concatenate([self.triangles[:, :, [0, 2]], np.ones((valid.sum(), 3, 1))], axis=2)
        self.planes = np.linalg.solve(matrix, self.triangles[:, :, 1, None])[:, :, 0]

    def heights(self, points):
        points = np.asarray(points, float)
        query = shapely.points(points)
        choices = self.index.nearest(query)
        hits = self.index.query(query, predicate="intersects")
        choices[hits[0]] = hits[1]
        return np.sum(np.column_stack([points, np.ones(len(points))]) * self.planes[choices], axis=1)

    def normalize(self, triangles, target_lift, overlay_lift=0.0):
        result = np.asarray(triangles, float).copy()
        if not len(result):
            return result
        # Repeated boundary queries use one answer, including rounded clipping
        # points and T junctions. Overlay height is replaced, never accumulated.
        points, indices = np.unique(result[:, :, [0, 2]].reshape(-1, 2), axis=0, return_inverse=True)
        result[:, :, 1] = (self.heights(points) + target_lift)[indices].reshape(-1, 3)
        return result
