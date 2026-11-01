import unittest
import numpy as np
from shapely.geometry import box, Polygon
from surface_repairs import vertical_remainder, planar_pieces, repair_object


class SurfaceRepairTests(unittest.TestCase):
    def test_vertical_skirt_clips_without_changing_heights(self):
        tri = np.array([[0, 0, 0], [4, 0, 0], [4, 2, 0]], float)
        kept, touched = vertical_remainder(tri, box(1, -1, 3, 1))
        self.assertTrue(touched)
        self.assertTrue(kept)
        for piece in kept:
            self.assertTrue(np.all(piece[:, 0] <= 1.000001) or np.all(piece[:, 0] >= 2.999999))
            self.assertTrue(np.all(piece[:, 1] >= 0) and np.all(piece[:, 1] <= 2))

    def test_ground_cut_keeps_original_grade_and_winding(self):
        tri = np.array([[0, 0, 0], [4, 1, 0], [0, 2, 4]], float)
        parts = planar_pieces(tri, Polygon(tri[:, [0, 2]]).intersection(box(.5, .5, 3, 3)))
        self.assertTrue(parts)
        for piece in parts:
            for x, y, z in piece:
                self.assertAlmostEqual(y, x / 4 + z / 2)
            self.assertGreater(np.dot(np.cross(piece[1] - piece[0], piece[2] - piece[0]), np.cross(tri[1] - tri[0], tri[2] - tri[0])), 0)

    def test_real_street_curb_is_untouched(self):
        obj = {"name": "Curbs", "verts": [0, 0, 0, 4, 0, 0, 4, 0, 2], "faces": [0, 1, 2],
               "mats": [0], "matnames": ["curb"], "smooth": False}
        original = repr(obj)
        report = repair_object(obj, box(-1, -1, 5, 1), [(-1, -1, 5, 1)])
        self.assertEqual(report["changed_source_triangles"], 0)
        self.assertEqual(repr(obj), original)

    def test_private_skirt_is_recolored_without_an_open_gap(self):
        obj = {"name": "Curbs", "verts": [0, 0, 0, 4, 0, 0, 4, 0, 2], "faces": [0, 1, 2],
               "mats": [0], "matnames": ["dirt"], "smooth": False}
        report = repair_object(obj, box(1, -1, 3, 1), [(1, -1, 3, 1)])
        self.assertEqual(report["removed_triangles"], 0)
        vertices = np.asarray(obj["verts"]).reshape(-1, 3)
        tris = vertices[np.asarray(obj["faces"]).reshape(-1, 3)]
        area = np.linalg.norm(np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0]), axis=1).sum() * .5
        self.assertAlmostEqual(area, 4.0)
        self.assertIn("sidewalk", obj["matnames"])
        self.assertEqual(set(obj["mats"]), {0, 1})


if __name__ == "__main__":
    unittest.main()
