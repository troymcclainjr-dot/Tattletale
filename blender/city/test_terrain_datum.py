import unittest
import numpy as np
import json
from pathlib import Path
from terrain_datum import TerrainDatum


class TerrainDatumTests(unittest.TestCase):
    def setUp(self):
        self.triangles = np.array([[[0,.02,0],[1,.06,0],[1,.08,1]],
                                   [[1,.14,0],[2,.18,0],[1,.16,1]],
                                   [[2,.23,0],[3,.27,0],[2,.25,1]]])
        self.datum = TerrainDatum(self.triangles, ['alley', 'grass', 'sidewalk'])

    def test_replacement_drops_old_step_but_retains_terrain_grade(self):
        triangles = np.array([[[0,.02,0],[1,.06,0],[1,.08,1]],
                              [[1,.14,0],[2,.18,0],[1,.16,1]],
                              [[2,.23,0],[3,.27,0],[2,.25,1]]])
        result = self.datum.normalize(triangles, .125)
        np.testing.assert_allclose(result[:,:,1], .125 + result[:,:,0]*.04 + result[:,:,2]*.02)
        np.testing.assert_array_equal(result[:,:,[0,2]], triangles[:,:,[0,2]])
        self.assertAlmostEqual(result[0,1,1], result[1,0,1])

    def test_existing_overlay_lift_is_removed_once(self):
        triangles = self.triangles.copy()
        triangles[:,:,1] += .025
        np.testing.assert_allclose(self.datum.normalize(triangles, .125), self.datum.normalize(self.triangles, .125))

    def test_recolored_asphalt_reconciles_shared_boundary(self):
        datum = TerrainDatum(self.triangles[:2], ['asphalt', 'grass'])
        result = datum.normalize(self.triangles[:2], .125)
        self.assertAlmostEqual(result[0,1,1], result[1,0,1])
        self.assertAlmostEqual(result[0,2,1], result[1,2,1])

    def test_published_lawns_and_campus_have_closed_shared_edges(self):
        data = Path(__file__).resolve().parents[2] / 'godot/assets/data'
        lawns = json.loads((data/'pen_lucy_alive_world.json').read_text())['lawn_triangles']
        campus = json.loads((data/'pen_lucy_hospital_grounds.json').read_text())['triangles']
        for triangles in [lawns, [t for key, values in campus.items() if key != 'paint' for t in values]]:
            vertices = np.asarray(triangles).reshape(-1, 3)
            _, groups = np.unique(np.round(vertices[:, [0, 2]], 5), axis=0, return_inverse=True)
            low, high = np.full(groups.max()+1, np.inf), np.full(groups.max()+1, -np.inf)
            np.minimum.at(low, groups, vertices[:, 1])
            np.maximum.at(high, groups, vertices[:, 1])
            self.assertLess(float((high-low).max()), .001, 'obsolete material steps left a crack in replacement terrain')


if __name__ == '__main__':
    unittest.main()
