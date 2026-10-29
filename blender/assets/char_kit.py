"""char_kit - small helpers shared by the char_cop_dan / char_cop_steve / char_mailman scripts (on top of lib/person.py)."""
import sys, os; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import math
import numpy as np
import bpy
import claykit as ck
from lib import person as P

BIG = P.BIG


# ---------------------------------------------------------------- SDF shapes
def bounded(s, lo, hi):
    """Give an SDF finite bounds (plates built from prisms and slabs have infinite ones)."""
    return P.Sdf(s.f, lo, hi)


def plate(pts, th, rr, z0=0.0):
    """Flat clay plate from a 2D outline (x, y), 2*th thick along z (centered on z0), edges rounded rr."""
    A = np.array(pts, float)
    core = P.intersect(P.offset(P.poly2d(pts), -rr), P.Sdf(lambda p: np.abs(p[:, 2] - z0) - (th - rr), [-BIG] * 3, [BIG] * 3))
    m = rr + 0.002
    return bounded(P.offset(core, rr), [A[:, 0].min() - m, A[:, 1].min() - m, z0 - th - m], [A[:, 0].max() + m, A[:, 1].max() + m, z0 + th + m])


def star(n, ro, ri, cx=0.0, cy=0.0, rot=0.0):
    return [(cx + (ro if k % 2 == 0 else ri) * math.sin(rot + k * math.pi / n), cy + (ro if k % 2 == 0 else ri) * math.cos(rot + k * math.pi / n)) for k in range(2 * n)]


SHIELD = [(-0.5, 0.34), (-0.27, 0.5), (0.0, 0.42), (0.27, 0.5), (0.5, 0.34), (0.46, -0.1), (0.24, -0.37), (0.0, -0.5), (-0.24, -0.37), (-0.46, -0.1)]


def shield_pts(w, h, cx=0.0, cy=0.0):
    return [(cx + x * w, cy + y * h) for x, y in SHIELD]


def prism_x(pts):
    """A 2D outline drawn in the (z, y) plane, extruded along x (patches on the side of a sleeve)."""
    p2 = P.poly2d(pts)
    return P.Sdf(lambda p: p2.f(p[:, [2, 1, 0]]), [-BIG] * 3, [BIG] * 3)


def frame_z(n, up=(0.0, 1.0, 0.0)):
    """3x3 (local -> parent) whose local z is n and local y leans toward `up`."""
    z = P._unit(n)
    u = np.asarray(up, float)
    y = P._unit(u - z * (u @ z))
    return np.stack([np.cross(y, z), y, z], 1)


def in_frame(s, O, Rm):
    """The shape s expressed in a frame with origin O and axes Rm (local -> parent)."""
    O = np.asarray(O, float)
    c = np.array([[x, y, z] for x in (s.lo[0], s.hi[0]) for y in (s.lo[1], s.hi[1]) for z in (s.lo[2], s.hi[2])])
    q = (c - O) @ Rm
    return P.Sdf(lambda p: s.f(p @ Rm.T + O), q.min(0), q.max(0))


def hit(s, origin, direction, reach):
    """First surface point along a ray and the outward normal there."""
    P._MARGIN[0] = max(P._MARGIN[0], 0.03)
    o, d = np.asarray(origin, float), P._unit(direction)
    t = P.ray_hit(s, [o], [d], reach, steps=160)[0]
    if np.isnan(t):
        raise RuntimeError(f"no surface hit from {origin} along {direction}")
    pt = o + d * t
    return pt, P._unit(P._sdf_grad(s, pt[None, :], 0.0015)[0])


def place(local, pt, n, up=(0, 1, 0), lift=0.0):
    """Put a shape built around the origin (facing +z) onto a surface point, facing along n."""
    return P.xform(local, pos=np.asarray(pt) + np.asarray(n) * lift, rot=frame_z(n, up))


def euler_facing(n):
    """three.js Euler (x, y, 0) that turns a +z-facing object to face n."""
    return (-math.asin(max(-1.0, min(1.0, float(n[1])))), math.atan2(float(n[0]), float(n[2])), 0.0)


def ellipse_ring(a, b, zc, y, n=28, scale=1.0):
    th = np.linspace(0, 2 * np.pi, n, endpoint=False)
    return np.stack([a * scale * np.sin(th), np.full(n, y), zc + b * scale * np.cos(th)], 1), th


def fit_ellipse(s, ys, zc0, rmax, n=96):
    """Smallest centered ellipse (a, b, zc) in the xz plane holding the cross-sections of s at heights ys."""
    az = np.linspace(-np.pi, np.pi, n, endpoint=False)
    pts = []
    for y in ys:
        O = np.stack([rmax * np.sin(az), np.full(n, y), zc0 + rmax * np.cos(az)], 1)
        D = -np.stack([np.sin(az), np.zeros(n), np.cos(az)], 1)
        t = P.ray_hit(s, O, D, rmax, steps=140)
        ok = ~np.isnan(t)
        pts.append((O + D * t[:, None])[ok])
    pts = np.concatenate(pts)
    x, z = pts[:, 0], pts[:, 2]
    zc = 0.5 * (z.max() + z.min())
    a, b = np.abs(x).max(), 0.5 * (z.max() - z.min())
    k = math.sqrt(((x / a) ** 2 + ((z - zc) / b) ** 2).max())
    return a * k, b * k, zc


# ---------------------------------------------------------------- meshes
def part(name, sdf, m, pivot, cell, target, lumps=0.0, seed=0):
    """Mesh an SDF built in `pivot`'s local game coords and parent it there."""
    ob = P.sdf_mesh(name, sdf, m, cell, target, lumps=lumps, seed=seed)
    if ob is not None and pivot is not None:
        P.attach(ob, pivot)
    return ob


def join_into(r, key, objs):
    """Join extra clay parts (already parented to the same pivot) into that pivot's mesh."""
    bpy.context.view_layer.update()
    base = r.meshes[key]
    r.meshes[key] = ck.join([base] + [o for o in objs if o is not None], base.name)
    return r.meshes[key]


def swap_material(ob, old_name, new_mat):
    for i, m in enumerate(ob.data.materials):
        if m is not None and m.name == old_name:
            ob.data.materials[i] = new_mat


def cull_hidden(ob, solid, margin):
    """Delete faces buried inside `solid` (an SDF in the same pivot's local coords) by more than margin:
    the hair's inner shell, eyeball backs, skin under a hat, the embedded halves of badges and patches.
    Only use solids that move with this pivot."""
    import bmesh
    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.verts.ensure_lookup_table()
    co = np.array([v.co[:] for v in bm.verts])
    P._MARGIN[0] = 0.03
    inside = P._eval_points(solid, np.stack([co[:, 0], co[:, 2], -co[:, 1]], 1)) < -margin
    kill = [f for f in bm.faces if all(inside[v.index] for v in f.verts)]
    n0 = len(bm.faces)
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    bm.to_mesh(me)
    bm.free()
    me.update()
    print(f"[char_kit] culled {len(kill)}/{n0} hidden faces from {ob.name}")


def hat_hair(r, cutter, style="short", target=1000):
    """The builder's hair (the person is built with style bald), everything under the hat cut away."""
    H = r.H
    full = P._hair_cap(r, style)
    hair = P.subtract(full, P.offset(cutter, -0.003 * H), k=0.005 * H)
    r.sdf["hair"] = hair
    return part("Hair", hair, r.mats["hair"], r.head, 0.0017 * H, target, lumps=0.0006 * H, seed=41)


def cull_person(r, head_solid=None, body_solid=None, arm_solid=None):
    """Cull hidden faces on every pivot mesh. Defaults: head skin, torso + pelvis (collar opening kept),
    long sleeve + hand, trouser leg + shoe."""
    H = r.H
    cull_hidden(r.meshes["Head"], head_solid if head_solid is not None else r.sdf["head"], 0.003 * H)
    if body_solid is None:
        body_solid = P.union(r.sdf["torso"], P._pelvis_sdf(r))
    neck = P.cylinder((0, 0.4 * H, 0), 0.062 * H, 0.1 * H)      # keep the collar opening (the neck moves)
    cull_hidden(r.meshes["Body"], P.subtract(body_solid, neck), 0.004 * H)
    if arm_solid is None:
        arm_solid = P.union(long_sleeve(r), r.sdf["hand"])
    cull_hidden(r.meshes["ArmL"], arm_solid, 0.003 * H)
    cull_hidden(r.meshes["ArmR"], P.mirror_x(arm_solid), 0.003 * H)
    upper, sole, _ = P._shoe_sdfs(r)
    leg = P.union(r.sdf["leg"], upper, sole) if sole is not None else P.union(r.sdf["leg"], upper)
    cull_hidden(r.meshes["LegL"], leg, 0.003 * H)
    cull_hidden(r.meshes["LegR"], P.mirror_x(leg), 0.003 * H)


def long_sleeve(r):
    """The builder's long sleeve shape (ArmL-local), for fitting patches and culling."""
    H = r.H
    return P.union(P.sphere((0, 0, 0), 0.0455 * H), P.round_cone((0, -0.005 * H, 0), (0, -0.252 * H, 0.005 * H), 0.0455 * H, 0.0405 * H), k=0.02 * H)


def report(r, tag="char"):
    tris = 0
    for ob in bpy.context.scene.objects:
        if ob.type == "MESH":
            t = sum(len(p.vertices) - 2 for p in ob.data.polygons)
            tris += t
            print(f"[{tag}]   {ob.name:12s} parent={ob.parent.name if ob.parent else None!s:6s} {t:6d} tris  {len(ob.data.materials)} mats")
    print(f"[{tag}] total {tris} tris")
    return tris


def hand_report(r, pose, label, target=None):
    """Where the hands land in a pose (body-local, in H), and their distance to a held object."""
    H = r.H
    P.reset_pose(r)
    P.set_pose(r, **pose)
    inv = r.body.matrix_world.inverted()
    out = []
    for nm, hd in (("R", r.handR), ("L", r.handL)):
        w = hd.matrix_world.translation
        b = inv @ w
        g = (b.x / H, b.z / H, -b.y / H)
        s = f"hand{nm} body-local ({g[0]:+.3f},{g[1]:+.3f},{g[2]:+.3f})H"
        if target is not None:
            s += f"  {nm}->{target.name}: {(target.matrix_world.translation - w).length:.3f} m"
        out.append(s)
    print(f"[hands] {label}: " + "  ".join(out))
    P.reset_pose(r)
