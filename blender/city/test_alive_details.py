"""Small geometry checks; the full published-world fixture remains separate."""
import unittest
import numpy as np
from shapely.geometry import box, Polygon
from alive_world import Ground, footprint


class AliveDetailGeometryTests(unittest.TestCase):
    def test_clipping_preserves_grade_and_holes(self):
        # Blender XY ground, Z elevation, converts to Godot X,-Y horizontal.
        source = {"objects": [{"name": "Ground", "verts": [0, 0, 0, 4, 0, 1, 0, 4, 2],
                                "faces": [0, 1, 2], "matnames": ["grass"], "mats": [0]}]}
        ground = Ground(source)
        self.assertAlmostEqual(ground.height(1, -1), .75)
        area = box(.2, -3, 3, -.2).difference(box(.7, -1.3, 1.3, -.7))
        clipped = ground.clipped_triangles(area)
        self.assertTrue(clipped)
        for tri in clipped:
            polygon = Polygon([(p[0], p[2]) for p in tri])
            self.assertLess(polygon.difference(area).area, 1e-5)
            for x, y, z in tri:
                self.assertAlmostEqual(y - .025, x / 4 - z / 2, places=4)
        self.assertIsNone(ground.height(5, -5))
        self.assertTrue(ground.coverage(area, {"asphalt"}).is_empty)

    def test_dumpster_dimensions_rotated_not_inflated(self):
        for angle in [0, .7, 1.57]:
            polygon = footprint([10, 20], [np.sin(angle), np.cos(angle)], 1.92, 1.18)
            self.assertAlmostEqual(polygon.area, 1.92 * 1.18)
            self.assertAlmostEqual(polygon.centroid.x, 10)
            self.assertAlmostEqual(polygon.centroid.y, 20)


if __name__ == "__main__":
    unittest.main()
