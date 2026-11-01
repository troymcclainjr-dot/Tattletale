"""Visual-template geometry contracts, independent of Blender/Godot."""
import hashlib
import json
from pathlib import Path
import unittest
import tempfile
import shutil

import numpy as np
import vegetation
import yards
import update_vegetation_templates


class VegetationQualityTests(unittest.TestCase):
    def templates(self):
        for bush, count in ((False, 6), (True, 3)):
            for variant in range(count):
                yield ("bush" if bush else "tree") + str(variant), lambda near, v=variant, b=bush: vegetation.make_template(v, b, near)
        yield "bush_spire", vegetation.pointed_template

    def test_closed_foliage_has_finite_outward_normals_and_bounded_lods(self):
        for kind, factory in self.templates():
            budgets = []
            for near in (True, False):
                data = vegetation.encode(factory(near))
                points = np.asarray(data["vertices"]).reshape(-1, 3)
                normals = np.asarray(data["normals"]).reshape(-1, 3)
                self.assertTrue(np.isfinite(points).all(), kind)
                self.assertTrue(np.isfinite(normals).all(), kind)
                np.testing.assert_allclose(np.linalg.norm(normals, axis=1), 1., atol=2e-5, err_msg=kind)
                self.assertLessEqual(np.linalg.norm(points[:, [0, 2]], axis=1).max(), 1.001, kind)
                self.assertLessEqual(points[:, 1].max(), 1.001, kind)
                self.assertGreaterEqual(points[:, 1].min(), -.026, kind)
                tri = points.reshape(-1, 3, 3)
                cross = np.cross(tri[:, 1]-tri[:, 0], tri[:, 2]-tri[:, 0])
                face_normal = normals.reshape(-1, 3, 3).mean(axis=1)
                # Godot front faces are clockwise, normals must face out.
                self.assertTrue((np.sum(cross*face_normal, axis=1) < 1e-8).all(), kind)
                self.assertEqual(data, vegetation.encode(factory(near)), kind)
                budgets.append(data["triangles"])
            self.assertLess(budgets[1], budgets[0], kind)
            self.assertLessEqual(budgets[0], 600, kind)
            self.assertLessEqual(budgets[1], 140, kind)

    def test_shrub_growth_habits_differ_at_same_scale(self):
        signatures = []
        for variant in range(3):
            vertices = np.asarray(vegetation.encode(vegetation.shrub_template(variant))["vertices"]).reshape(-1, 3)
            radius = np.linalg.norm(vertices[:, [0, 2]], axis=1)
            signatures.append(tuple(round(float(radius[(vertices[:, 1] > lo) & (vertices[:, 1] < hi)].mean()), 2)
                                    for lo, hi in ((.1, .3), (.4, .6), (.6, .8))))
        self.assertEqual(len(set(signatures)), 3)

    def test_pine_keeps_visible_gaps_between_whorls_in_both_lods(self):
        for near in (True, False):
            foliage = [tri for tri, material, _ in vegetation.pine_template(near) if material.startswith("leaf")]
            for height in (.525, .77):
                self.assertFalse(any(tri[..., 2].min() <= height <= tri[..., 2].max() for tri in foliage),
                                 "A joined crown filled the pine's sky gap")
            self.assertTrue(any(tri[..., 2].mean() < .5 for tri in foliage))
            self.assertTrue(any(.55 < tri[..., 2].mean() < .75 for tri in foliage))
            self.assertTrue(any(tri[..., 2].mean() > .8 for tri in foliage))

    def test_current_evergreen_positions_produce_both_runtime_habits(self):
        data = Path(__file__).resolve().parents[2] / "godot/assets/data/pen_lucy_vegetation.json"
        kinds = set()
        for plant in json.loads(data.read_text())["plants"]:
            if plant["kind"] not in ("tree4", "tree5"):
                continue
            seed = (round(plant["position"][0]*10)*73856093) ^ (round(-plant["position"][2]*10)*19349663)
            kinds.add(4 + ((seed >> 8) & 1))
        self.assertEqual(kinds, {4, 5}, "Current source placements must expose both evergreen silhouettes")

    def test_published_growth_remains_bound_to_same_vegetation_file(self):
        data = Path(__file__).resolve().parents[2] / "godot/assets/data"
        vegetation_path = data / "pen_lucy_vegetation.json"
        plants = json.loads(vegetation_path.read_text())
        growth = json.loads((data / "pen_lucy_shrub_growth.json").read_text())
        self.assertEqual(hashlib.sha256(vegetation_path.read_bytes()).hexdigest(), growth["source_sha256"])
        self.assertTrue(all(plants["plants"][g["index"]]["kind"].startswith("bush") for g in growth["plants"]))
        self.assertEqual(set(plants["templates"]), {name for name, _ in self.templates()})

    def test_hedges_keep_clipped_top_without_color_checkerboard(self):
        for variant in range(3):
            data = yards.hedge_template(variant)
            colors = np.asarray(data["colors"]).reshape(-1, 4)[:, :3]
            vertices = np.asarray(data["vertices"]).reshape(-1, 3)
            self.assertLessEqual(data["triangles"], 400)
            self.assertLess(np.ptp(vertices[vertices[:, 1] > .97, 1]), .03)
            self.assertLess(np.ptp(colors, axis=0).max(), .08)

    def test_refresh_preserves_all_current_placements_and_growth(self):
        root = Path(__file__).resolve().parents[2]
        data = root / "godot/assets/data"
        scratch = root / ".work/pacifist-foundation"
        scratch.mkdir(parents=True, exist_ok=True)
        names = ("pen_lucy_vegetation.json", "pen_lucy_yards.json", "pen_lucy_shrub_growth.json")
        with tempfile.TemporaryDirectory(dir=scratch) as folder:
            target = Path(folder)
            before = {}
            for name in names:
                shutil.copyfile(data / name, target / name)
                before[name] = json.loads((target / name).read_text())
            update_vegetation_templates.refresh(target)
            for name in names:
                after = json.loads((target / name).read_text())
                old = before[name]
                old.pop("templates", None)
                after.pop("templates", None)
                old.pop("source_sha256", None)
                after.pop("source_sha256", None)
                self.assertEqual(old, after, name + " nonvisual data changed")


if __name__ == "__main__":
    unittest.main()
