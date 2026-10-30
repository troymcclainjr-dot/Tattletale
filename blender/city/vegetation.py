"""Small deterministic vegetation library, shared by the GLB and runtime LOD batches.

Tree positions remain surveyed canopy centers. Bushes are fictional garden dressing,
restricted to mapped grass and kept clear of pavement and building footprints.
"""
import json
from pathlib import Path
import numpy as np
import shapely

MATERIALS = {
    "leaf_olive": ("clay", "#657a3c", 0.96),
    "leaf_deep": ("clay", "#3e6036", 0.96),
    "leaf_sage": ("clay", "#7b8951", 0.96),
    "leaf_dry": ("clay", "#8c814c", 0.98),
    "twig": ("clay", "#65503b", 0.96),
}


def ico(subdivide=False):
    t = (1 + 5 ** 0.5) / 2
    v = np.array([[-1, t, 0], [1, t, 0], [-1, -t, 0], [1, -t, 0], [0, -1, t], [0, 1, t],
                  [0, -1, -t], [0, 1, -t], [t, 0, -1], [t, 0, 1], [-t, 0, -1], [-t, 0, 1]], float)
    f = np.array([[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9],
                  [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2],
                  [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10],
                  [8, 6, 7], [9, 8, 1]])
    tri = v[f]
    if subdivide:
        a, b, c = tri[:, 0], tri[:, 1], tri[:, 2]
        ab, bc, ca = (a + b) / 2, (b + c) / 2, (c + a) / 2
        tri = np.concatenate([np.stack([a, ab, ca], 1), np.stack([b, bc, ab], 1),
                              np.stack([c, ca, bc], 1), np.stack([ab, bc, ca], 1)])
    return tri / np.linalg.norm(tri, axis=2, keepdims=True)


def branch(a, b, radius, tip, sides=6):
    a, b = np.asarray(a, float), np.asarray(b, float)
    axis = b - a
    axis /= np.linalg.norm(axis)
    reference = np.array([0, 0, 1.0]) if abs(axis[2]) < 0.9 else np.array([1.0, 0, 0])
    u = np.cross(axis, reference)
    u /= np.linalg.norm(u)
    v = np.cross(axis, u)
    angle = np.arange(sides + 1) * 2 * np.pi / sides
    ring = np.cos(angle)[:, None] * u + np.sin(angle)[:, None] * v
    lo, hi = a + ring * radius, b + ring * tip
    return np.concatenate([np.stack([lo[:-1], lo[1:], hi[1:]], 1), np.stack([lo[:-1], hi[1:], hi[:-1]], 1)])


def make_template(variant, bush=False, near=True):
    rng = np.random.default_rng(8501 + variant * 97 + (1000 if bush else 0))
    blocks = []
    if bush:
        centers = [(-0.48, -0.14, 0.45), (0.34, -0.32, 0.42), (0.19, 0.39, 0.56), (-0.12, 0.1, 0.73)]
        sizes = [(0.48, 0.40, 0.29), (0.42, 0.45, 0.33), (0.40, 0.43, 0.34), (0.32, 0.32, 0.27)]
    else:
        # Different crown architectures, not rotations of a single round blob.
        layouts = [
            [(-0.58, 0.03, 0.65), (0.47, -0.27, 0.69), (0.1, 0.50, 0.76), (-0.15, -0.25, 0.87)],
            [(-0.30, -0.20, 0.57), (0.33, 0.12, 0.70), (-0.21, 0.28, 0.81), (0.10, -0.12, 0.92)],
            [(-0.54, -0.24, 0.77), (0.48, 0.30, 0.84), (-0.1, 0.42, 0.63), (0.18, -0.39, 0.66)],
            [(-0.59, 0.18, 0.60), (0.32, -0.47, 0.78), (0.49, 0.30, 0.66), (-0.20, -0.09, 0.90)],
        ]
        centers = layouts[variant % len(layouts)]
        sizes = [(0.44, 0.38, 0.20), (0.42, 0.38, 0.20), (0.39, 0.43, 0.21), (0.36, 0.35, 0.16)]
        if variant == 1:
            sizes = [(x * 0.78, y * 0.78, z * 1.12) for x, y, z in sizes]
        blocks.append((branch((0, 0, -0.015), (0, 0, 0.59), 0.06, 0.027), "twig", False))
    for index, (center, size) in enumerate(zip(centers, sizes)):
        center = np.asarray(center) + rng.uniform(-0.05, 0.05, 3) * np.array([1, 1, 0.4])
        scale = np.asarray(size) * rng.uniform(0.86, 1.14, 3)
        direction = ico(near and not bush)
        # Coordinate-based perturbation gives shared corners the same shape offset.
        lump = 1 + 0.10 * np.sin(direction[..., 0] * 8.2 + variant) * np.cos(direction[..., 1] * 7.4 + index)
        tri = direction * lump[..., None] * scale + center
        mat = ["leaf_olive", "leaf_deep", "leaf_sage", "leaf_dry"][(variant + index + (1 if bush else 0)) % 4]
        blocks.append((tri, mat, True))
        if near:
            start = (0, 0, 0.06 if bush else 0.37 + 0.035 * index)
            blocks.append((branch(start, center, 0.024 if bush else 0.029, 0.008, 5), "twig", False))
            # Bare twig tips interrupt the outline of untended shrubs.
            if bush and index % 2 == 0:
                end = center + np.array([0.10, -0.06, 0.25])
                blocks.append((branch(center, end, 0.012, 0.004, 4), "twig", False))
    return blocks


def encode(blocks):
    vertices, normals, colors = [], [], []
    for triangles, material, smooth in blocks:
        tri = triangles.copy()
        normal = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
        normal /= np.maximum(np.linalg.norm(normal, axis=1, keepdims=True), 1e-9)
        normal = np.repeat(normal[:, None, :], 3, axis=1)
        if smooth:
            center = (tri.min(axis=(0, 1)) + tri.max(axis=(0, 1))) / 2
            scale = np.maximum((tri.max(axis=(0, 1)) - tri.min(axis=(0, 1))) / 2, 0.01)
            normal = (tri - center) / (scale * scale)
            normal /= np.maximum(np.linalg.norm(normal, axis=2, keepdims=True), 1e-9)
        # Blender -> Godot (x, z, -y); reverse winding for Godot ArrayMesh faces.
        tri = tri[:, ::-1, :][..., [0, 2, 1]] * np.array([1, 1, -1])
        normal = normal[:, ::-1, :][..., [0, 2, 1]] * np.array([1, 1, -1])
        hx = MATERIALS[material][1].lstrip("#")
        rgb = [int(hx[i:i + 2], 16) / 255 for i in (0, 2, 4)]
        vertices.extend(np.round(tri, 5).ravel().tolist())
        normals.extend(np.round(normal, 5).ravel().tolist())
        colors.extend((rgb + [1.0]) * (len(tri) * 3))
    return {"vertices": vertices, "normals": normals, "colors": colors, "triangles": len(vertices) // 9}


def build(trees, grass, building_footprints, height, origin_y, tree_mesh, output_path):
    templates = {}
    raw = {}
    for bush, count in [(False, 4), (True, 3)]:
        for variant in range(count):
            key = ("bush" if bush else "tree") + str(variant)
            raw[key] = {lod: make_template(variant, bush, lod == "near") for lod in ["near", "far"]}
            templates[key] = {lod: encode(blocks) for lod, blocks in raw[key].items()}
    rng = np.random.default_rng(1907)
    placements = []
    for index, (x, north, h, radius) in enumerate(trees):
        ground = float(height(np.array([x]), np.array([north]))[0])
        key = "tree" + str(index % 4)
        yaw = float(rng.uniform(-np.pi, np.pi))
        placements.append({"kind": key, "position": [round(x, 3), round(ground - origin_y, 3), round(-north, 3)],
                           "radius": round(radius, 3), "height": round(h, 3), "yaw": round(-yaw, 5), "trunk_radius": round(radius * 0.06, 3)})
        rotation = np.array([[np.cos(yaw), -np.sin(yaw), 0], [np.sin(yaw), np.cos(yaw), 0], [0, 0, 1]])
        for tri, mat, smooth in raw[key]["far"]:
            placed = (tri * np.array([radius, radius, h])) @ rotation.T + np.array([x, north, ground])
            tree_mesh.add(placed, mat, smooth=smooth)
    # A stratified, seeded distribution across all mapped grass, never the walk.
    usable = grass.buffer(-0.45).difference(building_footprints.buffer(0.55))
    shapely.prepare(usable)
    xmin, ymin, xmax, ymax = grass.bounds
    xs, ys = np.meshgrid(np.arange(xmin, xmax, 8.0), np.arange(ymin, ymax, 8.0))
    candidates = np.column_stack([xs.ravel(), ys.ravel()]) + rng.uniform(-2.8, 2.8, (xs.size, 2))
    keep = shapely.contains_xy(usable, candidates[:, 0], candidates[:, 1]) & (rng.random(len(candidates)) < 0.52)
    bushes = candidates[keep]
    for index, (x, north) in enumerate(bushes):
        ground = float(height(np.array([x]), np.array([north]))[0]) + 0.10
        placements.append({"kind": "bush" + str(index % 3), "position": [round(x, 3), round(ground - origin_y, 3), round(-north, 3)],
                           "radius": round(float(rng.uniform(0.52, 1.15)), 3), "height": round(float(rng.uniform(0.42, 1.08)), 3),
                           "yaw": round(float(rng.uniform(-np.pi, np.pi)), 5), "trunk_radius": 0.0})
    payload = {"version": 1, "templates": templates, "plants": placements,
               "counts": {"trees": len(trees), "bushes": len(bushes), "shared_variants": len(templates)}}
    Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    Path(output_path).write_text(json.dumps(payload, separators=(",", ":")), encoding="utf-8")
    return payload["counts"]
