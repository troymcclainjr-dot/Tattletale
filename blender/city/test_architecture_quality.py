"""Bounded facade geometry checks; no Blender or Godot needed."""
import copy
import unittest

import numpy as np
from shapely.geometry import box

import kits


def fixture(arch="row_porch", width=5.4, ground=0., row=0, street="Other Street"):
    footprint = box(-width / 2, -5, width / 2, 5)
    roof = lambda xy: np.full(len(xy), ground + 8.4)
    building = {"id": "facade-fixture", "arch": arch, "pieces": [("main", footprint, roof)],
                "poly": footprint, "n": np.array([0., 1.]), "roof_at": roof,
                "porch": 2.2 if arch.endswith("porch") else 0., "porch_top": ground + 3.5,
                "door_left": True, "s0": -5., "s1": 7.2, "tags": {"addr:street": street},
                "roof": "flat", "row": row}
    building["style"] = kits.style(building, "row" + str(row))
    return building


def make(building, ground=0., forbidden=None):
    parts = kits.Parts(forbidden)
    kits.build(parts, building, {"H": lambda x, y: np.full_like(x, ground), "exposed": lambda p: True})
    return parts


def selected_row(arch, family):
    return next(i for i in range(100) if kits.bay_family(fixture(arch=arch, row=i)) == family)


class ArchitectureQualityTests(unittest.TestCase):
    def test_garages_have_shutters_without_invented_gameplay_entrances(self):
        building = fixture(arch="garage")
        parts = make(building)
        self.assertIn("shutter_dark", parts.items)
        self.assertNotIn("rear_door", building)
        self.assertNotIn("porch_stair", building)
        self.assertNotIn("upper_bay", building)
        self.assertLess(sum(len(v) for v in parts.items.values()), 10)

    def test_selection_coherent_sparse_and_rose_hill_preserved(self):
        families = [kits.bay_family(fixture(row=i)) for i in range(100)]
        self.assertGreater(families.count("canted"), 20)
        self.assertLess(families.count("canted"), 55)
        for row in range(30):
            a = fixture(row=row)
            b = copy.deepcopy(a)
            b["id"] = "different-house"
            self.assertEqual(kits.bay_family(a), kits.bay_family(b))
        self.assertEqual(kits.bay_family(fixture(street="Rose Hill Terrace")), "rose_hill")
        self.assertIsNone(kits.bay_family(fixture(arch="detached")))

    def test_bays_keep_doors_stairs_and_upper_sashes(self):
        for arch, family in (("row_porch", "canted"), ("row", "box")):
            building = fixture(arch, row=selected_row(arch, family))
            parts = make(building)
            bay = building["upper_bay"]
            self.assertEqual(bay["family"], family)
            self.assertGreater(bay["base_z"], 3.)
            self.assertLessEqual(bay["depth_m"], .72)
            self.assertTrue(all(z is not None for z in building["facade_layout"]["upper_sills_z"]))
            self.assertIn("rear_door", building)
            self.assertTrue(parts.items["glass"])
            if arch == "row_porch":
                self.assertGreaterEqual(bay["porch_clearance_m"], .035 - 1e-8)
                self.assertTrue(building["porch_stair"]["geometry_complete"])

    def test_narrow_and_road_conflicting_bays_fall_back_to_flat_windows(self):
        row = selected_row("row_porch", "canted")
        narrow = fixture(width=3., row=row)
        make(narrow)
        self.assertNotIn("upper_bay", narrow)
        self.assertTrue(all(z is not None for z in narrow["facade_layout"]["upper_sills_z"]))
        building = fixture(row=row)
        parts = kits.Parts(box(-20, -.9, 20, -.2))
        wall = kits.Wall([0, 0], [5.4, 0])
        self.assertFalse(kits.upper_bay(parts, wall, building, .7, 3.5, 8.4, 7.55, True))
        self.assertFalse(parts.items)
        self.assertFalse(parts.prisms)

    def test_profiles_stay_inside_existing_cornice_projection(self):
        wall = kits.Wall([0, 0], [5.4, 0])
        for profile in range(4):
            parts = kits.Parts()
            style = kits.style(fixture(), "fixture")
            style["cornice_profile"] = profile
            kits.cornice(parts, wall, 8., style)
            for items in parts.items.values():
                for center, size, axis, *_ in items:
                    self.assertGreaterEqual(center[2] - size[2] / 2, 8. - .78 - 1e-8)
                    self.assertLessEqual(-center[1] + size[1] / 2, .34 + 1e-8)
            self.assertLess(sum(len(v) for v in parts.items.values()), 15)

    def test_capitals_never_reduce_porch_headroom(self):
        wall = kits.Wall([0, 0], [5.4, 0])
        for top in (3.3, 3.5, 4.):
            plain, dressed = kits.Parts(), kits.Parts()
            style = kits.style(fixture(), "fixture")
            style["porch_profile"] = 0
            kits.porch(plain, wall, 2.2, .7, top, 0., style, .9)
            style["porch_profile"] = 2
            kits.porch(dressed, wall, 2.2, .7, top, 0., style, .9)
            base = {repr(item) for values in plain.items.values() for item in values}
            for values in dressed.items.values():
                for item in values:
                    if repr(item) not in base:
                        center, size, *_ = item
                        self.assertGreaterEqual(center[2] - size[2] / 2, .7 + kits.PORCH_MIN_CEILING - 1e-8)

    def test_new_bay_follows_ground_datum_without_shape_change(self):
        row = selected_row("row_porch", "canted")
        a, b = fixture(row=row), fixture(row=row, ground=87.123)
        pa, pb = make(a), make(b, ground=87.123)
        for (ta, ma), (tb, mb) in zip(pa.prisms, pb.prisms):
            self.assertEqual(ma, mb)
            np.testing.assert_allclose(ta, tb - [0, 0, 87.123], atol=1e-10)
        self.assertAlmostEqual(a["upper_bay"]["base_z"], b["upper_bay"]["base_z"] - 87.123)


if __name__ == "__main__":
    unittest.main()
