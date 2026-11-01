"""Small geometry regressions for the narrow rows and tree variety pass."""
import unittest
import numpy as np
from shapely.geometry import box
import kits
import vegetation


class AliveWorldGeometryTests(unittest.TestCase):
    def test_narrow_row_front_keeps_door_upper_glass_and_rear_entry(self):
        for width in (2.7701,2.8007,2.9444):
            poly=box(-width/2,-5,width/2,5)
            roof=lambda xy:np.full(len(xy),7.)
            b={"id":"narrow-row-"+str(width),"arch":"row_porch","pieces":[("main",poly,roof)],
               "poly":poly,"n":np.array([0.,1.]),"roof_at":roof,"porch":2.5,"porch_top":3.8,
               "door_left":True,"s0":-5.,"s1":7.5,"tags":{},"roof":"flat","row":0}
            b['style']=kits.style(b,'fixture');b['style']['chimney']=False
            parts=kits.Parts()
            kits.build(parts,b,{"H":lambda x,y:np.zeros_like(x),"exposed":lambda p:True})
            self.assertIn('front_yard',b)
            self.assertIn('facade_layout',b)
            self.assertIn('rear_door',b)
            self.assertIn('porch_stair',b)
            self.assertTrue(all(s is not None for s in b['facade_layout']['upper_sills_z']))
            glass=parts.items['glass']
            self.assertTrue(any(c[1]>4.9 and c[2]>3.0 for c,*rest in glass),'front upper glass missing')
            self.assertTrue(any(c[1]>4.9 and c[2]<3.0 for c,*rest in glass),'narrow ground sash missing')
            self.assertLess(b['rear_door']['xyz'][1],-4.9)
            self.assertGreaterEqual(b['porch_top']-.2-.7,2.4)

    def test_conifer_templates_stay_in_existing_tree_envelope(self):
        for variant in (4,5):
            sizes=[]
            for near in (True,False):
                blocks=vegetation.make_template(variant,False,near)
                verts=np.concatenate([tri.reshape(-1,3) for tri,_,_ in blocks])
                self.assertLessEqual(np.linalg.norm(verts[:,:2],axis=1).max(),1.)
                self.assertLessEqual(verts[:,2].max(),1.)
                leaves=np.concatenate([tri.reshape(-1,3) for tri,mat,_ in blocks if mat.startswith('leaf')])
                self.assertGreater(leaves[:,2].min(),.27)
                payload=vegetation.encode(blocks)
                self.assertTrue(np.isfinite(payload['normals']).all())
                sizes.append(payload['triangles'])
            self.assertLess(sizes[1],sizes[0])
        grass=box(-100,-100,100,100)
        selected=[vegetation.tree_kind(i,float(i)*.37,0.,8.,3.,grass) for i in range(80)]
        self.assertTrue({'tree4','tree5'}.issubset(set(selected)))
        self.assertEqual(vegetation.tree_kind(0,0.,0.,8.,3.,box(1,1,5,5)),'tree0')


if __name__=='__main__':unittest.main()
