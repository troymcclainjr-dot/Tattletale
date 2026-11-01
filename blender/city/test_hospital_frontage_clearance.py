import unittest
import json
import numpy as np
from shapely.geometry import Point, Polygon, box
from shapely.ops import unary_union
from hospital_frontage_clearance import ROOT, frontage_clearance, clip_triangles, load_clearance


class HospitalFrontageClearanceTests(unittest.TestCase):
    def test_long_frontage_preserves_path_beyond_five_metre_buffer(self):
        site = {'preserve_buildings': [{'id': 'kept'}]}
        homes = [{'id': 'kept', 'residential': True, 'polygon': [(0, 0), (5, 0), (5, -4), (0, -4)]}]
        stairs = [{'building_id': 'kept', 'normal': [0, 0, 1], 'landing': [2, 1, 0], 'approach': [2, 0, 2]}]
        region, audit = frontage_clearance(site, homes, stairs, box(-5, 8, 10, 10))
        self.assertTrue(region.covers(Point(2, 7)))
        self.assertFalse(region.covers(Point(7, 7)))
        self.assertEqual(audit[0]['building_id'], 'kept')

    def test_clipping_preserves_grade_and_untouched_triangles(self):
        triangles = [[[0, 0, 0], [4, 2, 0], [0, 1, 4]], [[10, 2, 10], [11, 2, 10], [10, 2, 11]]]
        exclusion = box(-1, -1, 1, 5)
        clipped, removed = clip_triangles(triangles, exclusion)
        self.assertGreater(removed, 0)
        self.assertIn(triangles[1], clipped)
        for tri in clipped:
            self.assertLess(Polygon([(p[0], p[2]) for p in tri]).intersection(exclusion).area, 1e-7)
            if tri == triangles[1]:
                continue
            for x, y, z in tri:
                self.assertAlmostEqual(y, x * .5 + z * .25, places=5)

    def test_actual_argonne_band_and_path_belong_to_preserved_frontages(self):
        region, audit = load_clearance()
        self.assertIn('w336328500', [entry['building_id'] for entry in audit])
        self.assertTrue(region.covers(Point(444.03807, -92.22301)))
        self.assertTrue(region.covers(Point(446.88872, -96.04488)))

    def test_published_campus_keeps_preserved_frontages_clear(self):
        region, _ = load_clearance()
        data = json.loads((ROOT / 'godot/assets/data/pen_lucy_hospital_grounds.json').read_text())
        overlap = sum(Polygon(np.asarray(tri)[:, [0, 2]]).intersection(region).area
                      for tri in data['triangles']['landscape'])
        self.assertLess(overlap, .001)
        # The photographed path end is supported by the original Ground;
        # no campus triangle may bridge over it after the correction.
        landscape = unary_union([Polygon(np.asarray(tri)[:, [0, 2]])
                                 for tri in data['triangles']['landscape']])
        self.assertFalse(landscape.covers(Point(446.88872, -96.04488)))


if __name__ == '__main__':
    unittest.main()
