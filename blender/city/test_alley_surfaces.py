import copy
import json
import unittest
from pathlib import Path
import numpy as np
from shapely.geometry import box, mapping, shape
from alley_surfaces import repair_object, SPEC


def area(obj, kind=None):
    v = np.asarray(obj["verts"]).reshape(-1, 3)
    f = np.asarray(obj["faces"]).reshape(-1, 3)
    if kind is not None:
        f = f[np.asarray(obj["mats"]) == obj["matnames"].index(kind)]
    t = v[f]
    return np.linalg.norm(np.cross(t[:, 1] - t[:, 0], t[:, 2] - t[:, 0]), axis=1).sum() * .5


class AlleySurfaceTests(unittest.TestCase):
    def fixture(self, name="Ground"):
        # Source XYZ: this plane rises one metre over four metres in X.
        return {"name": name, "verts": [0, 0, 0, 4, 0, 1, 0, -4, 0], "faces": [0, 1, 2],
                "mats": [0], "matnames": ["alley"], "smooth": True, "props": {"preserve": 1}}

    def empty_strip(self):
        return [{"id": "unrelated", "geometry": mapping(box(10, 10, 11, 11)), "expected_ground_area_m2": 0}]

    def test_partial_corridor_keeps_exact_plane_and_coverage(self):
        obj = self.fixture()
        old = copy.deepcopy(obj)
        audit = repair_object(obj, self.empty_strip(), mapping(box(1, -1, 3, 5)))
        self.assertGreater(audit["replacement_triangles"], 0)
        self.assertAlmostEqual(area(old), area(obj), places=5)
        self.assertGreater(area(obj, "asphalt"), 0)
        self.assertGreater(area(obj, "alley"), 0)
        self.assertEqual(obj["verts"][:len(old["verts"])], old["verts"])
        for x, _, z in np.asarray(obj["verts"]).reshape(-1, 3):
            self.assertAlmostEqual(z, x / 4, places=5)
        self.assertEqual(obj["props"], old["props"])

    def test_public_sidewalk_and_curb_faces_are_byte_identical(self):
        for name, kind in [("Ground", "sidewalk"), ("Curbs", "curb")]:
            obj = self.fixture(name)
            obj["matnames"] = [kind]
            original = copy.deepcopy(obj)
            report = repair_object(obj, self.empty_strip(), mapping(box(-5, -5, 5, 5)))
            self.assertEqual(report["changed_source_triangles"], 0)
            self.assertEqual(obj, original)

    def test_closed_vertical_skirt_partition_never_opens_gap(self):
        obj = {"name": "Curbs", "verts": [0, 0, 0, 4, 0, 0, 4, 0, 2], "faces": [0, 1, 2],
               "mats": [0], "matnames": ["alley"], "smooth": False}
        before = area(obj)
        report = repair_object(obj, self.empty_strip(), mapping(box(1, -1, 3, 1)))
        self.assertAlmostEqual(area(obj), before, places=6)
        self.assertGreater(area(obj, "asphalt"), 0)
        self.assertGreater(area(obj, "alley"), 0)
        self.assertEqual(report["deleted_area_m2"], 0)

    def test_unmapped_private_front_pads_are_unchanged(self):
        obj = self.fixture()
        original = copy.deepcopy(obj)
        repair_object(obj, self.empty_strip(), mapping(box(20, 20, 30, 30)))
        self.assertEqual(obj, original)

    def test_authored_corridors_exclude_actual_front_approaches(self):
        spec = json.loads(Path(SPEC).read_text())
        corridor = shape(spec["alley_corridors"])
        protected = shape(spec["protected_front_approaches"])
        self.assertLess(corridor.intersection(protected).area, 1e-7)
        self.assertEqual(len(spec["source_alley_ways"]), 76)
        strip = shape(spec["regions"][0]["geometry"])
        self.assertAlmostEqual(strip.area, 62.8405785, places=4)


if __name__ == "__main__":
    unittest.main()
