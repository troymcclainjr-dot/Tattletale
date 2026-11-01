"""Focused source geometry regressions; run with the city Python environment."""
import unittest
import numpy as np
from shapely.geometry import box, Polygon, GeometryCollection, LineString, Point, MultiPolygon
from shapely.ops import unary_union
import yards
import park_courts


class YardGeometryTests(unittest.TestCase):
    def test_sidewalk_transition_boundary_handles_clipping_remnants(self):
        surface = GeometryCollection([MultiPolygon([box(0, 0, 4, 4), box(6, 0, 10, 4)]),
                                      LineString([(4, 2), (6, 2)])])
        edge = yards.paving_boundary(surface)
        self.assertAlmostEqual(edge.distance(Point(0.003, 2)), 0.003)
        self.assertAlmostEqual(edge.distance(Point(2, 2)), 2)
        self.assertAlmostEqual(edge.distance(Point(5, 2)), 1)
        self.assertTrue(yards.paving_boundary(GeometryCollection()).is_empty)

    def test_adjacent_homes_keep_stairs_and_walks_clear(self):
        buildings = []
        for index, x in enumerate((0, 6, 12)):
            buildings.append({"id": str(index), "arch": "row_porch", "poly": box(x, -8, x + 6, 0),
                              "front_yard": {"edge": [[x, 0], [x + 6, 0]], "normal": [0, 1], "door": [x + 1, 0]},
                              "porch_stair": {"landing_xyz": [x + 1, 0.2, 1], "approach_xyz": [x + 1, 2, 0]}})
        footprints = unary_union([b["poly"] for b in buildings])
        road, walk = box(-5, 7, 25, 16), box(-5, 5, 25, 7)
        beds, soil, edges, paths, records, audit = yards.gardens(buildings, footprints, road, walk, Polygon(), Polygon(), box(-5, -10, 25, 20))
        self.assertEqual(audit["homes_with_beds"], 2)
        self.assertGreater(beds.area, 20)
        self.assertLess(beds.intersection(paths).area, 1e-8)
        self.assertLess(beds.intersection(unary_union([road, walk, footprints])).area, 1e-8)
        self.assertTrue(soil.is_empty, "hedge lawns must not contain circular dirt cutouts")
        self.assertLess(edges.difference(beds).area, 1e-8)
        self.assertTrue(paths.covers(box(6.2, 2.2, 7.8, 4.9)))
        self.assertEqual(len(records), 2)

    def test_original_can_is_grounded_and_clockwise(self):
        from pathlib import Path
        data = yards.can_template(Path(__file__).resolve().parents[2] / "godot/assets/models/furniture.glb")
        vertices = np.array(data["vertices"]).reshape(-1, 3, 3)
        normals = np.array(data["normals"]).reshape(-1, 3, 3)
        cross = np.cross(vertices[:, 1] - vertices[:, 0], vertices[:, 2] - vertices[:, 0])
        self.assertTrue(np.all((cross * normals.mean(axis=1)).sum(axis=1) < 1e-10))
        self.assertLess(abs(vertices[:, :, 1].min()), 0.003)
        self.assertLess(np.abs(vertices[:, :, [0, 2]]).max(), 0.36)

    def test_hedge_row_follows_front_and_preserves_path_gap(self):
        from shapely.geometry import LineString
        path=LineString([(1,-1),(1,5)]).buffer(.84)
        garden={"poly":box(0,0,7,4).difference(path),"normal":np.array([0.,1.])}
        rows=yards.hedge_rows(garden,path)
        self.assertEqual(len(rows),1)
        p,length,yaw,footprint,offset=rows[0]
        self.assertGreater(length,4.)
        self.assertLess(p.y,1.)
        self.assertLess(footprint.intersection(path).area,1e-9)
        self.assertAlmostEqual(yaw,0.)

    def test_hedge_is_contiguous_and_has_flat_clipped_crown(self):
        data=yards.hedge_template(1)
        verts=np.array(data['vertices']).reshape(-1,3)
        self.assertLess(data['triangles'],400)
        self.assertGreater(np.sum(verts[:,1]>.97),70)
        self.assertLess(np.ptp(verts[verts[:,1]>.97,1]),.03)
        self.assertGreater(np.ptp(verts[:,0]),.99)

    def test_court_flat_slab_and_bounded_apron(self):
        height=lambda x,y: np.asarray(x)*.012+np.asarray(y)*.004+10.
        court=park_courts.fit_candidate(np.array([0.,0.]),np.array([1.,0.]),np.array([0.,1.]),12.,9.,2.5,height,.01)
        self.assertIsNotNone(court)
        self.assertLessEqual(court['court_grade'],.010001)
        self.assertLess(court['max_apron_slope_deg'],4.)
        self.assertLess(court['max_fill_m'],.24)
        mesh,origin,hoops,floor_count=park_courts.mesh_for(court,10.)
        self.assertEqual(len(hoops),1)
        self.assertGreater(mesh['triangles'],floor_count)
        self.assertGreater(hoops[0]['rim_position'][1]-origin[1],2.9)

    def test_empty_court_selection_preserves_all_trees(self):
        trees=[(x,5.,8.,3.) for x in range(1812)]
        self.assertEqual(park_courts.trees_outside_courts(trees,Polygon()),trees)
        self.assertEqual(len(park_courts.trees_outside_courts(trees,box(2,3,8,7))),1805)

    def test_green_inventory_includes_unnamed_clearings_and_named_small_parks(self):
        grass=MultiPolygon([box(0,0,40,30),box(50,0,90,30),box(100,0,110,10),box(120,0,125,5)])
        parks=[{"name":"Small mapped playground","poly":box(101,1,109,9)}]
        greens,audit=park_courts.green_spaces(parks,grass)
        self.assertEqual(len(greens),3)
        self.assertEqual(audit['small_lawns_omitted'],1)
        self.assertEqual(len(audit['named_parks'][0]['green_ids']),1)

    def test_retained_court_has_grounded_sides_and_opposed_shallow_ramps(self):
        # A raised centre needs side retaining faces but leaves two clear ramps.
        height=lambda x,y: .15*np.exp(-(np.asarray(y)/2)**2)+np.asarray(x)*.008
        court=park_courts.retained_candidate(np.array([0.,0.]),np.array([1.,0.]),np.array([0.,1.]),12.,9.,6.,height,.015)
        self.assertIsNotNone(court)
        self.assertEqual(court['access'],'opposed_across_ramps')
        self.assertGreater(len(court['retaining_triangles']),0)
        self.assertLess(court['max_apron_slope_deg'],4)
        self.assertLess(court['max_fill_m'],.8)
        self.assertAlmostEqual(court['triangles'][:,:,0].min(),-13.)
        self.assertAlmostEqual(court['triangles'][:,:,0].max(),13.)

    def test_large_flat_green_prefers_full_court_and_reports_narrow_exclusion(self):
        greens=[{'name':'Broad','poly':box(0,0,40,45)},{'name':'Narrow road lawn','poly':box(50,0,57,50)}]
        courts,audit=park_courts.select(greens,Polygon(),lambda x,y:np.zeros_like(x),True)
        self.assertEqual(len(courts),1)
        self.assertEqual((courts[0]['width'],courts[0]['length']),(15.,28.))
        self.assertEqual(audit[1]['status'],'excluded')
        self.assertEqual(audit[1]['geometry_candidates'],0)


if __name__ == "__main__":
    unittest.main()
