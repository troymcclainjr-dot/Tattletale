import unittest
import numpy as np
from shapely.geometry import Polygon, Point
from shapely.ops import unary_union
from lawn_collision import build, Surface


def grid(x0, x1, height):
    triangles = []
    for x in np.arange(x0, x1, .5):
        for z in np.arange(0, 2, .5):
            a,b,c,d = [(px, height(px,pz), pz) for px,pz in [(x,z),(x+.5,z),(x+.5,z+.5),(x,z+.5)]]
            triangles.extend([[a,b,c],[a,c,d]])
    return triangles


class LawnCollisionTests(unittest.TestCase):
    def test_only_high_extensions_need_new_collision(self):
        old = grid(0,2,lambda x,z:.02) + grid(2,4,lambda x,z:.1)
        lawn = grid(0,4,lambda x,z:.125)
        result, audit = build(lawn, old)
        domain = unary_union([Polygon(np.asarray(t)[:,[0,2]]) for t in result])
        self.assertAlmostEqual(domain.area, 4.)
        self.assertFalse(domain.covers(Point(3,1)))
        self.assertLess(len(result), audit['source_extension_triangles'])
        self.assertLessEqual(audit['maximum_surface_error_m'], .008)

    def test_curved_grade_stays_within_footing_tolerance(self):
        old = grid(0,4,lambda x,z:.025*x*x + .01*z + .02)
        lawn = grid(0,4,lambda x,z:.025*x*x + .01*z + .125)
        result, audit = build(lawn, old)
        self.assertLessEqual(audit['maximum_surface_error_m'], .008)
        points = np.array([(x,z) for x in np.arange(.1,3.91,.2) for z in np.arange(.1,1.91,.2)])
        error = np.abs(Surface(result).height(points)-Surface(lawn).height(points))
        self.assertLess(float(error.max()), .0081)


if __name__ == '__main__':
    unittest.main()
