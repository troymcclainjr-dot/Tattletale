"""Pen Lucy, Baltimore (world space): the city. Real OSM footprints with heights from USGS LiDAR,
dressed in archetype kits (porch-front rows, marble stoops, storefronts, detached houses), on the
bare-earth terrain with streets, sidewalks and curbs, alleys, grass and LiDAR trees, and gray context
massing around the edge. Everything is generated; nothing here is hand placed.

Run blender/city/fetch.py and blender/city/process.py first (see blender/city/README.md); this
script only turns .work/city/build/pen_lucy_geom.json into meshes.

Origin: the Old York Rd / Wyanoke Ave intersection at ground level. x east, y up, z south, 1 unit = 1 m.
"""
import sys, os; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import claykit as ck
import bpy, json, math
import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "city"))
import config as C

ck.reset()
geom = json.load(open(C.GEOM_JSON))
mats = {k: ck.mat(kind, hx, rough) for k, (kind, hx, rough) in geom["materials"].items()}

col = bpy.data.collections.new("PenLucy")
bpy.context.scene.collection.children.link(col)
for o in geom["objects"]:
    v = np.array(o["verts"], np.float32)
    f = np.array(o["faces"], np.int32)
    me = bpy.data.meshes.new(o["name"])
    me.vertices.add(len(v) // 3)
    me.vertices.foreach_set("co", v)
    nf = len(f) // 3
    me.loops.add(len(f))
    me.loops.foreach_set("vertex_index", f)
    me.polygons.add(nf)
    me.polygons.foreach_set("loop_start", np.arange(0, len(f), 3, dtype=np.int32))
    me.polygons.foreach_set("loop_total", np.full(nf, 3, np.int32))
    for name in o["matnames"]:
        me.materials.append(mats[name])
    me.polygons.foreach_set("material_index", np.array(o["mats"], np.int32))
    smooth = np.array(o["smooth_faces"], bool) if "smooth_faces" in o else np.full(nf, o["smooth"], bool)
    me.polygons.foreach_set("use_smooth", smooth)
    me.validate(clean_customdata=False)
    me.update()
    obj = bpy.data.objects.new(o["name"], me)
    for k, val in o["props"].items():
        obj[k] = val
    col.objects.link(obj)

ck.export("pen_lucy", subdir="city", save_blend=False)
# the .blend is regenerated every build and too big for git history, so it stays in .work
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(C.BUILD, "pen_lucy.blend"), compress=True)
# process.py places the cameras on the terrain; fov is vertical, Blender wants a lens for 36 mm wide
W, H = 960, 720
views = [{"eye": v["eye"], "look": v["look"],
          "lens": 18 / math.tan(math.atan(math.tan(math.radians(v["fov"]) / 2) * W / H))} for v in geom["views"]]
ck.preview("pen_lucy", ground=False, size=(W, H), views=views)
