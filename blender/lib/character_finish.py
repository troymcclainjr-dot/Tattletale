"""Deterministic anatomical finish for the legacy segmented character rig.

Legacy H was a rig unit: the bald skull reached 1.114H, while city adults use
actual metres. Refit anatomy at export, rather than shrinking the actor root.
The mesh and every held-prop/joint origin are mapped together in rest pose.
"""
import numpy as np

VERSION = 1
ASSET_VERSIONS = {"baby": 2, "timmy": 2}
HEIGHTS = {"two_pack": 1.8, "ricky": 1.76, "granny": 1.5, "gary": 1.72,
           "timmy": .95, "mailman": 1.75, "cop_dan": 1.8, "cop_steve": 1.88,
           "mama": 1.68, "dad": 1.8, "vendor": 1.78, "liner_1": 1.7,
           "liner_2": 1.85, "liner_3": 1.6, "liner_4": 1.78, "baby": .55}


def dimensions(asset_id):
    """Source/target Y landmarks and width/depth profiles, in nominal H."""
    if asset_id == "baby":
        # Infant-specific anatomy: about four heads tall, short chubby lower
        # limbs, round diaper and a clearly larger head than an older child.
        return ([0, .47, .78, .83, 1.114], [0, .34, .65, .69, 1.0],
                [1.06, 1.14, 1.00, 1.12, 1.14], [1.08, 1.12, 1.00, 1.10, 1.12])
    if asset_id == "timmy":
        return ([0, .47, .78, .83, 1.114], [0, .42, .70, .75, 1.0],
                [.96, .95, .94, 1.00, 1.00], [.96, .95, .94, 1.00, 1.00])
    return ([0, .47, .78, .83, 1.114], [0, .49, .77, .81, 1.0],
            [.90, .88, .84, .82, .82], [.90, .87, .86, .85, .85])


def map_points(points, asset_id, jacobian=False):
    """Map Blender Z-up points; also return exact local deformation Jacobians."""
    p = np.atleast_2d(np.asarray(points, dtype=float))
    h = HEIGHTS[asset_id]
    source, target, widths, depths = [np.asarray(v) for v in dimensions(asset_id)]
    y = p[:, 2] / h
    seg = np.clip(np.searchsorted(source, y, side="right") - 1, 0, len(source)-2)
    t = (y-source[seg]) / (source[seg+1]-source[seg])
    # Continue the terminal head segment above the skull for hair and hats.
    sy = (target[seg+1]-target[seg]) / (source[seg+1]-source[seg])
    sx = widths[seg] + t*(widths[seg+1]-widths[seg])
    sz = depths[seg] + t*(depths[seg+1]-depths[seg])
    result = p.copy()
    result[:, 0] *= sx
    result[:, 1] *= sz
    result[:, 2] = (target[seg]+t*(target[seg+1]-target[seg]))*h
    if not jacobian:
        return result
    j = np.zeros((len(p), 3, 3))
    j[:, 0, 0], j[:, 1, 1], j[:, 2, 2] = sx, sz, sy
    j[:, 0, 2] = p[:, 0]*(widths[seg+1]-widths[seg])/(h*(source[seg+1]-source[seg]))
    j[:, 1, 2] = p[:, 1]*(depths[seg+1]-depths[seg])/(h*(source[seg+1]-source[seg]))
    return result, j


def apply_scene(asset_id):
    """Bake rest anatomy, preserving materials, topology, node names and normals.

    Safe to call on an already finished scene. Rig metadata makes this idempotent.
    No modifiers, extra draw calls, textures, or runtime deformation are added.
    """
    import bpy
    from mathutils import Matrix
    rig = bpy.data.objects.get("Rig")
    if rig is None or asset_id not in HEIGHTS:
        raise ValueError("Unknown character or missing Rig: " + asset_id)
    version = ASSET_VERSIONS.get(asset_id, VERSION)
    previous_version = int(rig.get("anatomy_version", 0))
    if previous_version == version:
        return False
    if previous_version:
        raise ValueError(f"{asset_id} is already anatomically baked at v{previous_version}; "
                         "load its frozen original GLB with --source-dir, never deform cumulatively")
    objects = [rig] + list(rig.children_recursive)
    bpy.context.view_layer.update()
    old = {o: np.array(o.matrix_world) for o in objects}
    new = {}
    for ob in objects:
        m = old[ob].copy()
        m[:3, 3] = map_points(m[:3, 3], asset_id)[0]
        new[ob] = m
    for ob in objects:
        if ob.type != "MESH":
            continue
        mesh = ob.data
        xyz = np.empty(len(mesh.vertices)*3)
        mesh.vertices.foreach_get("co", xyz)
        xyz = xyz.reshape(-1, 3)
        world = xyz @ old[ob][:3, :3].T + old[ob][:3, 3]
        mapped, j = map_points(world, asset_id, True)
        inv = np.linalg.inv(new[ob])
        local = mapped @ inv[:3, :3].T + inv[:3, 3]
        # Preserve analytical SDF normals after the nonuniform refit.
        norms = np.empty(len(mesh.loops)*3)
        mesh.corner_normals.foreach_get("vector", norms)
        norms = norms.reshape(-1, 3) @ np.linalg.inv(old[ob][:3, :3])
        indices = np.empty(len(mesh.loops), dtype=np.int32)
        mesh.loops.foreach_get("vertex_index", indices)
        norms = np.einsum("nij,nj->ni", np.linalg.inv(j[indices]).transpose(0, 2, 1), norms)
        norms = norms @ new[ob][:3, :3]
        norms /= np.maximum(np.linalg.norm(norms, axis=1, keepdims=True), 1e-12)
        mesh.vertices.foreach_set("co", local.ravel())
        mesh.update()
        mesh.normals_split_custom_set(norms.tolist())
    # Set parents before descendants so child translations remain correct.
    def depth(ob):
        return 0 if ob == rig else 1 + depth(ob.parent)
    for ob in sorted(objects, key=depth):
        ob.matrix_world = Matrix(new[ob].tolist())
        bpy.context.view_layer.update()
    rig["anatomy_version"] = version
    rig["nominal_height"] = HEIGHTS[asset_id]
    rig["anatomy_id"] = asset_id
    h = HEIGHTS[asset_id]
    head_center = map_points((0, 0, .995*h), asset_id)[0, 2]
    head_pivot = map_points((0, 0, .83*h), asset_id)[0, 2]
    rig["head_center_y"] = float(head_center-head_pivot)
    rig["head_radius"] = float(.115*h*dimensions(asset_id)[2][-1])
    print(f"[character_finish] {asset_id}: anatomy v{version}; nominal H={HEIGHTS[asset_id]:.2f}m")
    return True
