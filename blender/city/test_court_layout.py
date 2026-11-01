"""Court orientation, end-access support and saved identity regression checks."""
import unittest
import numpy as np
from shapely.geometry import Polygon, Point, box
import park_courts as courts


class CourtLayoutTests(unittest.TestCase):
    def test_narrow_green_gets_lengthwise_full_court_with_clear_end_access(self):
        green={"name":"Narrow long green","poly":box(0,0,13,33),"court_id":"park_court_13"}
        height=lambda x,y:np.asarray(x)*.006+np.asarray(y)*.008
        selected,audit=courts.select([green],Polygon(),height,True)
        self.assertEqual(len(selected),1)
        court=selected[0]
        self.assertEqual((court["width"],court["length"]),(10.,20.))
        self.assertEqual(court["access"],"opposed_offset_end_ramps")
        self.assertTrue(green["poly"].covers(court["footprint"]))
        self.assertLess(court["max_apron_slope_deg"],4.)
        self.assertLessEqual(court["max_fill_m"],.8)
        mesh,origin,hoops,_=courts.mesh_for(court,0)
        self.assertEqual(len(hoops),2)
        center=np.array([court["center"][0],court["intercept"],-court["center"][1]])
        across=np.array([court["across"][0],0,-court["across"][1]])
        along=np.array([court["along"][0],0,-court["along"][1]])
        for hoop in hoops:
            delta=np.array(hoop["position"])-center
            self.assertAlmostEqual(delta@across,0,places=4)
            self.assertAlmostEqual(abs(delta@along),10.72,places=4)
        self.assertLess(np.dot(np.array(hoops[0]["position"])-center,along)*np.dot(np.array(hoops[1]["position"])-center,along),0)
        # End-ramp floor vertices remain at least 1.5m sideways of the pole.
        points=court["triangles"].reshape(-1,3)
        ramps=points[np.abs(points[:,1])>court["length"]/2+1.001]
        self.assertGreater(len(ramps),0)
        self.assertGreaterEqual(np.abs(ramps[:,0]).min(),1.5)
        for p in points:
            xy=court["center"]+court["across"]*p[0]+court["along"]*p[1]
            self.assertGreater(p[2]-height(*xy),.1)
        record=courts.record_for(court,0)
        self.assertEqual(record["id"],"park_court_13")
        self.assertEqual(record["kind"],"full")

    def test_compact_eighteen_metre_court_has_two_opposed_hoops(self):
        height=lambda x,y:np.zeros_like(x)
        court=courts.fit_candidate(np.array([0.,0.]),np.array([1.,0.]),np.array([0.,1.]),10.,18.,1.,height,.015)
        self.assertIsNotNone(court)
        _,_,hoops,_=courts.mesh_for(court,0)
        self.assertEqual(len(hoops),2)
        self.assertAlmostEqual(hoops[0]["position"][0],0)
        self.assertAlmostEqual(hoops[1]["position"][0],0)
        self.assertAlmostEqual(hoops[0]["position"][2],-hoops[1]["position"][2])

    def test_removed_court_id_does_not_renumber_other_greens(self):
        greens=[{"id":"different_green_order_0","name":"Argonne removal","poly":box(269,-62,272,-59)},
                {"id":"different_green_order_1","name":"Court eighteen","poly":box(130,46,133,49)}]
        courts.bind_court_identities(greens)
        self.assertEqual(greens[0]["court_id"],"park_court_17")
        self.assertTrue(greens[0]["court_removed"])
        self.assertEqual(greens[1]["court_id"],"park_court_18")
        self.assertFalse(greens[1]["court_removed"])
        selected,audit=courts.select([greens[0]],Polygon(),lambda x,y:np.zeros_like(x),True)
        self.assertEqual(selected,[])
        self.assertEqual(audit[0]["reason"],"removed_at_user_request")


if __name__=="__main__":unittest.main()
