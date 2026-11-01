"""Small deterministic vegetation library, shared by the GLB and runtime LOD batches.

Tree positions remain surveyed canopy centers. Bushes are fictional garden dressing,
restricted to mapped grass and kept clear of pavement and building footprints.
"""
import json
from pathlib import Path
import numpy as np
import shapely

MATERIALS = {
    "leaf_olive": ("clay", "#546d3d", 0.88),
    "leaf_deep": ("clay", "#38593b", 0.88),
    "leaf_sage": ("clay", "#657c4d", 0.88),
    "leaf_dry": ("clay", "#78804c", 0.90),
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


def leaf_sprig(center, direction, length, material):
    """Solid folded leaf tips avoid alpha-card overdraw and detached speckles."""
    center, direction = np.asarray(center, float), np.asarray(direction, float)
    direction /= np.linalg.norm(direction)
    side = np.cross(direction, [0., 0., 1.])
    if np.linalg.norm(side) < .01:
        side = np.array([1., 0., 0.])
    side /= np.linalg.norm(side)
    up = np.cross(direction, side)
    points = np.array([center-direction*length*.35, center+direction*length*.65,
                       center+side*length*.24, center-side*length*.24+up*length*.16])
    triangles = points[[[0, 2, 1], [0, 1, 3], [0, 3, 2], [1, 2, 3]]]
    for triangle in triangles:
        if np.dot(np.cross(triangle[1]-triangle[0], triangle[2]-triangle[0]), triangle.mean(0)-points.mean(0)) < 0:
            triangle[:] = triangle[::-1]
    return triangles, material, False


def crown_shell(profile, sides, variant, material, near):
    """Joined lobed crown; profile is (height, radius), in authoring Z-up."""
    rings = []
    for height, radius in profile:
        angle = np.arange(sides) * 2*np.pi/sides
        ripple = .78 + .14*np.sin(angle*3 + variant + height*2) + .065*np.cos(angle*5-height*5)
        z = height + np.sin(angle*3+variant)*.045*np.sin(height*np.pi)*min(radius*4, 1.)
        rings.append(np.column_stack([np.cos(angle)*radius*ripple,
                                      np.sin(angle)*radius*ripple, z]))
    triangles = []
    for lower, upper in zip(rings, rings[1:]):
        for j in range(sides):
            k = (j+1)%sides
            for tri in ([lower[j], lower[k], upper[k]], [lower[j], upper[k], upper[j]]):
                tri = np.asarray(tri)
                if np.linalg.norm(np.cross(tri[1]-tri[0], tri[2]-tri[0])) > 1e-8:
                    triangles.append(tri)
    blocks = [(np.asarray(triangles), material, True)]
    if near:
        for ring_index in range(2, len(rings)-1, 2):
            for j in range(0, sides, 3):
                point = rings[ring_index][j]
                direction = np.array([point[0], point[1], .22])
                blocks.append(leaf_sprig(point*.985, direction, .10, material))
    return blocks


def shrub_template(variant, near=True):
    # Upright inkberry-like, spreading bayberry-like and loose arching habits.
    profiles = [
        [(0.,0.),(.06,.55),(.23,.85),(.48,.95),(.73,.83),(.91,.52),(1.,0.)],
        [(0.,0.),(.05,.62),(.19,.93),(.43,1.),(.64,.92),(.84,.64),(.94,0.)],
        [(0.,0.),(.07,.42),(.25,.73),(.47,.91),(.70,.97),(.91,.69),(1.,0.)],
    ]
    profile = profiles[variant % 3]
    if not near:
        profile = [profile[i] for i in (0, 2, 3, 4, 6)]
    return crown_shell(profile, 16 if near else 10, variant,
                       ["leaf_deep", "leaf_olive", "leaf_sage"][variant % 3], near)


def pointed_template(near=True):
    # Narrow planted cedar/arborvitae habit with irregular leader and boughs.
    profile = [(-.025,0.),(.02,.60),(.20,.84),(.36,.94),(.49,.77),
               (.63,.65),(.76,.46),(.88,.28),(1.,0.)]
    if not near:
        profile = [profile[i] for i in (0, 2, 3, 5, 7, 8)]
    return crown_shell(profile, 12 if near else 8, 2, "leaf_deep", near)


def make_template(variant, bush=False, near=True):
    if bush:
        return shrub_template(variant, near)
    if variant >= 4:
        return conifer_template(variant-4, near)
    rng = np.random.default_rng(8501 + variant * 97)
    # Oak-like spreading, maple-like upright, elm-like vase, and irregular crown.
    # Artistic habits, not species claims for surveyed trees.
    layouts = [
        [(-.54,.02,.64),(.49,-.24,.68),(.08,.48,.74),(-.12,-.18,.85),(-.63,.29,.78),(.51,.23,.84)],
        [(-.29,-.19,.57),(.32,.12,.70),(-.21,.27,.80),(.09,-.12,.91),(.37,-.28,.83),(-.35,-.08,.91)],
        [(-.53,-.22,.78),(.47,.29,.84),(-.12,.42,.66),(.18,-.38,.69),(-.40,.22,.91),(.38,-.15,.94)],
        [(-.57,.17,.60),(.30,-.45,.76),(.47,.28,.66),(-.19,-.08,.88),(-.48,-.26,.80),(.14,.33,.92)],
    ]
    sizes = [(.40,.35,.20),(.39,.35,.20),(.37,.39,.21),(.35,.33,.17),(.24,.24,.12),(.23,.23,.12)]
    palette = ["leaf_olive", "leaf_deep", "leaf_sage", "leaf_olive"]
    blocks = [(branch((0,0,-.015),(0,0,.59),.06,.027), "twig", False)]
    for index, (center, size) in enumerate(zip(layouts[variant], sizes)):
        center = np.asarray(center) + rng.uniform(-.025,.025,3)
        scale = np.asarray(size)
        if variant == 1:
            scale *= [.82,.82,1.05]
        direction = ico(near and index < 3)
        azimuth = np.arctan2(direction[...,1], direction[...,0])
        lump = .91 + .22*np.sin(azimuth*3+index)*np.cos(direction[...,2]*4) + .095*np.cos(azimuth*5-variant)
        tri = direction*lump[...,None]*scale + center
        blocks.append((tri, palette[variant], True))
        if near:
            fork = np.array([center[0]*.47, center[1]*.47, .43+.035*index])
            if index < 3:
                blocks.append((branch((0,0,.35),fork,.025,.016,5), "twig", False))
                blocks.append((branch(fork,center,.016,.005,5), "twig", False))
            else:
                blocks.append((branch((0,0,.40),center,.020,.005,5), "twig", False))
            for angle in np.arange(2)*np.pi + index*.51:
                vector = np.array([np.cos(angle), np.sin(angle), .26])
                point = center + vector*scale*.92
                blocks.append(leaf_sprig(point, vector, .09, palette[variant]))
    # Keep every crown within the surveyed height, including near leaf tips.
    # The trunk/collision contract remains exactly 0.59 of the authored height.
    for triangles, _, _ in blocks[1:]:
        triangles[..., 2] = .35 + (triangles[..., 2] - .35) * .88
    return blocks


def conifer_template(variant, near):
    """Cedar-like narrow crown and pine-like layered boughs in source envelope."""
    if variant % 2 == 0:
        return pine_template(near)
    profiles = [
        [(.29,0.),(.31,.66),(.41,.86),(.51,.68),(.61,.69),(.72,.45),(.84,.34),(1.,0.)],
        [(.29,0.),(.32,.47),(.46,.62),(.59,.52),(.72,.43),(.84,.30),(.93,.15),(1.,0.)],
    ]
    profile = profiles[variant % 2]
    if not near:
        profile = [profile[i] for i in (0, 2, 4, 6, 7)]
    blocks = [(branch((0,0,-.015),(0,0,.94),.06,.012,8 if near else 5), "twig", False)]
    blocks += crown_shell(profile, 12 if near else 8, variant, "leaf_deep" if variant else "leaf_olive", near)
    if near:
        for i in range(3):
            angle = i*2.4 + variant
            blocks.append((branch((0,0,.32+i*.15),(.48*np.cos(angle),.48*np.sin(angle),.43+i*.14),.02,.005,5), "twig", False))
    return blocks


def pine_template(near):
    """Three open, staggered whorls with horizontal needle-bearing boughs.

    Foliage stays disconnected between tiers so sky shows through the crown.
    Unequal radial fans and rotated whorls avoid a stack of rotational cones.
    Both LODs preserve all twelve bough masses and their negative-space gaps.
    """
    blocks = [(branch((0, 0, -.015), (0, 0, .97), .06, .009, 8 if near else 5), "twig", False)]
    # Octahedral far fans retain the same center/extents as detailed near fans.
    octa = np.array([[1,0,0],[-1,0,0],[0,1,0],[0,-1,0],[0,0,1],[0,0,-1]], float)
    far_faces = np.array([[0,2,4],[2,1,4],[1,3,4],[3,0,4],
                          [2,0,5],[1,2,5],[3,1,5],[0,3,5]])
    for tier, (height, width) in enumerate(((.40, .94), (.65, .73), (.87, .47))):
        for arm in range(4):
            angle = arm * 2*np.pi/4 + tier*.83 + .13*np.sin(arm+tier)
            reach = width * (1.0 - .07*arm)
            radial = np.array([np.cos(angle), np.sin(angle), 0.])
            tangent = np.array([-np.sin(angle), np.cos(angle), 0.])
            center = radial*reach*.43 + np.array([0,0,height + .012*np.sin(arm*2+tier)])
            direction = ico(False) if near else octa[far_faces]
            # Horizontal asymmetrical sprays, slightly lifted at the branch tips.
            local = direction * np.array([reach*.55, reach*.40, .09 if tier < 2 else .07])
            local[..., 2] += local[..., 0]*.07
            triangles = (local[..., 0, None]*radial + local[..., 1, None]*tangent
                         + local[..., 2, None]*np.array([0,0,1.]) + center)
            blocks.append((triangles, "leaf_deep" if tier == 0 else "leaf_olive", True))
            if near:
                tip = center + radial*reach*.42
                blocks.append((branch((0,0,height-.045), tip, .022-.004*tier, .004, 3), "twig", False))
                blocks.append(leaf_sprig(tip, radial + np.array([0,0,.24]), .10, "leaf_olive"))
    # Small leader fan finishes the silhouette instead of exposing a bare spike.
    leader = ico(False) if near else octa[far_faces]
    blocks.append((leader * np.array([.11,.11,.065]) + np.array([.018,-.012,.93]), "leaf_olive", True))
    return blocks


def tree_kind(index,x,north,height,radius,grass):
    # Sparse, deterministic evergreen accents in broad grass, not every street
    # tree. Crown footprint remains within the source tree's surveyed envelope.
    seed=(round(x*10)*73856093) ^ (round(north*10)*19349663)
    if height>=6 and radius>=1.8 and seed%9==0 and grass.covers(shapely.Point(x,north).buffer(min(radius*.55,1.4))):
        return "tree"+str(4+(seed//9)%2)
    return "tree"+str(index%4)


def encode(blocks):
    vertices, normals, colors = [], [], []
    for triangles, material, smooth in blocks:
        tri = triangles.copy()
        normal = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
        normal /= np.maximum(np.linalg.norm(normal, axis=1, keepdims=True), 1e-9)
        normal = np.repeat(normal[:, None, :], 3, axis=1)
        if smooth:
            # Area-weighted shared corners follow actual bough contours.
            _, inverse = np.unique(np.round(tri.reshape(-1, 3), 8), axis=0, return_inverse=True)
            face = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
            summed = np.zeros((inverse.max() + 1, 3))
            np.add.at(summed, inverse, np.repeat(face, 3, axis=0))
            normal = summed[inverse].reshape(tri.shape)
            normal /= np.maximum(np.linalg.norm(normal, axis=2, keepdims=True), 1e-9)
        # Blender -> Godot (x, z, -y); reverse winding for Godot ArrayMesh faces.
        tri = tri[:, ::-1, :][..., [0, 2, 1]] * np.array([1, 1, -1])
        normal = normal[:, ::-1, :][..., [0, 2, 1]] * np.array([1, 1, -1])
        hx = MATERIALS[material][1].lstrip("#")
        rgb = [int(hx[i:i + 2], 16) / 255 for i in (0, 2, 4)]
        vertices.extend(np.round(tri, 5).ravel().tolist())
        normals.extend(np.round(normal, 5).ravel().tolist())
        if material.startswith("leaf"):
            # Broad tonal depth only: clean surfaces without stochastic grain.
            shade = .94 + .08 * np.clip(tri[..., 1], 0., 1.)
            rgba = np.ones((*shade.shape, 4))
            rgba[..., :3] = np.asarray(rgb) * shade[..., None]
            colors.extend(np.round(rgba, 5).ravel().tolist())
        else:
            colors.extend((rgb + [1.0]) * (len(tri) * 3))
    return {"vertices": vertices, "normals": normals, "colors": colors, "triangles": len(vertices) // 9}


def build(trees, grass, building_footprints, height, origin_y, tree_mesh, output_path):
    templates = {}
    raw = {}
    for bush, count in [(False, 6), (True, 3)]:
        for variant in range(count):
            key = ("bush" if bush else "tree") + str(variant)
            raw[key] = {lod: make_template(variant, bush, lod == "near") for lod in ["near", "far"]}
            templates[key] = {lod: encode(blocks) for lod, blocks in raw[key].items()}
    templates["bush_spire"] = {lod: encode(pointed_template(lod == "near")) for lod in ("near", "far")}
    rng = np.random.default_rng(1907)
    placements = []
    for index, (x, north, h, radius) in enumerate(trees):
        ground = float(height(np.array([x]), np.array([north]))[0])
        key = tree_kind(index,x,north,h,radius,grass)
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
               "counts": {"trees": len(trees), "bushes": len(bushes), "shared_variants": len(templates),
                          "conifers":sum(p["kind"] in ("tree4","tree5") for p in placements)}}
    Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    path = Path(output_path)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(payload, separators=(",", ":")), encoding="utf-8")
    temporary.replace(path)
    return payload["counts"]
