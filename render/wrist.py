"""A realistic human forearm + hand for wrist-shot renders of the watch.

Builds a MakeHuman (MPFB 2) body, poses the left hand, bakes the left forearm and
hand into a standalone mesh and places it in the watch's coordinate frame:

  * units are millimetres (the caller sets scene.unit_settings.scale_length = 0.001)
  * +X = 3 o'clock = along the forearm toward the fingers (crown side on a left wrist)
  * +Z = out of the dial = the back (dorsal side) of the wrist
  * +Y = Z x X = 12 o'clock = the pinky (ulnar) side; the thumb is on -Y
  * the dorsal skin under the watch centre touches the case back at z = case_back_z,
    about 22 mm from the wrist joint toward the elbow.

Usage (MPFB must be enabled first):

    import addon_utils; addon_utils.enable("bl_ext.user_default.mpfb", default_set=True)
    import wrist
    dims = wrist.add_wrist()      # {'half_width': .., 'half_depth': .., 'centre_z': ..}

Run directly for a preview render:

    blender -b -P render/wrist.py -- [--size PX] [--samples N] [--out file.png] [--skin NAME] [--curl C]
"""

import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

SKIN_DIRS = [
    "/root/.config/blender/4.5/extensions/.user/user_default/mpfb/data/skins",
]

# Where on the forearm the watch sits, measured from the wrist joint toward the elbow (mm).
WATCH_FROM_WRIST = 22.0

# Bones whose skin we keep (left forearm and hand).
ARM_BONES = (
    ["lowerarm01.L", "lowerarm02.L", "wrist.L"]
    + ["metacarpal%d.L" % i for i in range(1, 5)]
    + ["finger%d-%d.L" % (f, j) for f in range(1, 6) for j in range(1, 4)]
)


# --------------------------------------------------------------------------- helpers


def _skin_path(skin):
    if os.path.isfile(skin):
        return skin
    for d in SKIN_DIRS:
        p = os.path.join(d, skin, skin + ".mhmat")
        if os.path.isfile(p):
            return p
    raise FileNotFoundError("MPFB skin not found: %r" % skin)


def _macros_for_skin(skin):
    """Phenotype sliders that match the skin's name (young_caucasian_male, ...)."""
    name = os.path.basename(skin).lower()
    female = "female" in name
    age = 0.5  # MakeHuman: 0.5 = 25 years, 1.0 = 90 years
    if "middleage" in name:
        age = 0.69
    elif "old" in name:
        age = 0.88
    race = {"asian": 0.0, "caucasian": 0.0, "african": 0.0}
    for r in race:
        if r in name:
            race[r] = 1.0
    if not any(race.values()):
        race = {"asian": 0.0, "caucasian": 1.0, "african": 0.0}
    return {
        "gender": 0.0 if female else 1.0,
        "age": age,
        "muscle": 0.55,
        "weight": 0.5,
        "proportions": 0.6,
        "height": 0.55,
        "cupsize": 0.5,
        "firmness": 0.5,
        "race": race,
    }


def _bone_frame(rig):
    """Watch frame from the rest-pose bones, in the armature's local (decimetre) space.

    Returns (origin, R) with R's columns = watch X, Y, Z axes; origin = point on the
    forearm axis WATCH_FROM_WRIST mm toward the elbow from the wrist joint."""
    bones = rig.data.bones
    wrist = bones["wrist.L"].head_local
    elbow = bones["lowerarm01.L"].head_local
    f = (wrist - elbow).normalized()
    idx = bones["metacarpal1.L"].tail_local  # index-finger side
    pinky = bones["metacarpal4.L"].tail_local
    l_thumb = idx - pinky
    l_thumb = (l_thumb - l_thumb.dot(f) * f).normalized()
    d = l_thumb.cross(f).normalized()  # dorsal
    x, z = f, d
    y = z.cross(x)
    r = Matrix((x, y, z)).transposed()  # columns
    origin = wrist - f * (WATCH_FROM_WRIST / 100.0)  # mm -> dm
    return origin, r, (wrist - elbow).length * 100.0


def _rotate_pbone(pb, axis, angle):
    """Rotate a pose bone about its head by angle around an armature-space axis."""
    if abs(angle) < 1e-6:
        return
    m = pb.matrix.copy()
    head = m.translation.copy()
    pb.matrix = Matrix.Translation(head) @ Matrix.Rotation(angle, 4, axis) @ Matrix.Translation(-head) @ m
    bpy.context.view_layer.update()


def _signed_angle(v, target, axis):
    """Angle that rotates v about axis toward target (both projected on the plane normal to axis)."""
    a = (v - v.dot(axis) * axis).normalized()
    b = (target - target.dot(axis) * axis).normalized()
    return math.atan2(axis.dot(a.cross(b)), a.dot(b))


def _pose_hand(rig, rot, curl):
    """Straight wrist (hand in line with the forearm, palm down) and a relaxed hand:
    fingers gathered and gently curled (more toward the pinky), thumb resting by the index."""
    pb = rig.pose.bones
    for b in pb:
        b.rotation_mode = "XYZ"
        b.rotation_euler = (0, 0, 0)
    bpy.context.view_layer.update()
    f_ax, y_ax, d_ax = rot.col[0].copy(), rot.col[1].copy(), rot.col[2].copy()
    l_ax = -y_ax  # toward the thumb

    def head(n):
        return pb[n].head.copy()

    def tail(n):
        return pb[n].tail.copy()

    # 1. wrist: remove the rest pose's palmar flexion and most of the ulnar deviation.
    w = pb["wrist.L"]
    m = tail("metacarpal2.L") - head("wrist.L")
    flex = math.atan2(m.dot(d_ax), m.dot(f_ax))
    _rotate_pbone(w, l_ax, -flex + math.radians(16.0))
    m = tail("metacarpal2.L") - head("wrist.L")
    dev = math.atan2(m.dot(y_ax), m.dot(f_ax))
    _rotate_pbone(w, d_ax, -0.7 * dev)

    # hand frame after the wrist correction
    hd = w.matrix.to_3x3() @ (rig.data.bones["wrist.L"].matrix_local.to_3x3().inverted() @ d_ax)
    hd.normalize()
    middle = (tail("finger3-1.L") - head("finger3-1.L")).normalized()

    # 2. gather the fingers toward the middle finger
    for f, k in ((2, 0.9), (4, 0.9), (5, 0.85)):
        b = pb["finger%d-1.L" % f]
        v = (b.tail - b.head).normalized()
        _rotate_pbone(b, hd, k * _signed_angle(v, middle, hd))

    # 3. curl: flex every phalanx toward the palm (axis = dorsal x bone direction)
    flexes = {2: 0.50, 3: 0.60, 4: 0.72, 5: 0.85}
    for f, k in flexes.items():
        for j, wj in ((1, 0.55), (2, 1.0), (3, 0.65)):
            b = pb["finger%d-%d.L" % (f, j)]
            v = (b.tail - b.head).normalized()
            _rotate_pbone(b, hd.cross(v).normalized(), curl * k * wj * 1.5)

    # 4. thumb: bring it in toward the index finger and bend it slightly
    t1 = pb["finger1-1.L"]
    tv = (t1.tail - t1.head).normalized()
    idx = (tail("finger2-1.L") - head("finger2-1.L")).normalized()
    ax = tv.cross(idx)
    if ax.length > 1e-6:
        _rotate_pbone(t1, ax.normalized(), 0.45 * tv.angle(idx))
    for j, a in ((2, 0.25), (3, 0.45)):
        b = pb["finger1-%d.L" % j]
        v = (b.tail - b.head).normalized()
        _rotate_pbone(b, hd.cross(v).normalized(), curl * a * 1.5)


def _skin_microdetail(nt, bsdf, bump, base_link_from):
    """Adds mm-scale skin relief (polygonal micro-furrows + pores), roughness and tone variation.

    Works in Object coordinates, which are millimetres for the baked wrist mesh."""
    N, L = nt.nodes, nt.links

    def node(t, **inputs):
        n = N.new(t)
        for k, v in inputs.items():
            n.inputs[k].default_value = v
        return n

    def math_node(op, *args, clamp=False):
        n = N.new("ShaderNodeMath")
        n.operation = op
        n.use_clamp = clamp
        for i, v in enumerate(args):
            if isinstance(v, (int, float)):
                n.inputs[i].default_value = v
            else:
                if isinstance(v, bpy.types.Node):
                    v = v.outputs[0]
                L.new(v, n.inputs[i])
        return n

    co = N.new("ShaderNodeTexCoord").outputs["Object"]
    # macro warp so the cell pattern is not perfectly regular
    warp = node("ShaderNodeTexNoise", Scale=0.35, Detail=2.0)
    L.new(co, warp.inputs["Vector"])
    wco = N.new("ShaderNodeVectorMath")
    wco.operation = "MULTIPLY_ADD"
    L.new(warp.outputs["Color"], wco.inputs[0])
    wco.inputs[1].default_value = (0.6, 0.6, 0.6)
    L.new(co, wco.inputs[2])
    # furrow network: Voronoi distance-to-edge, ~0.7 mm cells
    cells = node("ShaderNodeTexVoronoi", Scale=1.4, Randomness=1.0)
    cells.feature = "DISTANCE_TO_EDGE"
    L.new(wco.outputs["Vector"], cells.inputs["Vector"])
    furrow = math_node("DIVIDE", cells.outputs["Distance"], 0.09, clamp=True)
    # pores: small dimples
    pores = node("ShaderNodeTexVoronoi", Scale=2.6, Randomness=0.9)
    L.new(co, pores.inputs["Vector"])
    pore = math_node("DIVIDE", pores.outputs["Distance"], 0.16, clamp=True)
    # fine noise + gentle large-scale unevenness (soft tissue, veins)
    fine = node("ShaderNodeTexNoise", Scale=9.0, Detail=2.0)
    L.new(co, fine.inputs["Vector"])
    lumps = node("ShaderNodeTexNoise", Scale=0.06, Detail=2.0)
    L.new(co, lumps.inputs["Vector"])
    h = math_node("MULTIPLY", furrow, 0.4)
    h = math_node("MULTIPLY_ADD", pore.outputs[0], 0.3, h.outputs[0])
    h = math_node("MULTIPLY_ADD", fine.outputs["Fac"], 0.15, h.outputs[0])
    h = math_node("MULTIPLY_ADD", lumps.outputs["Fac"], 5.0, h.outputs[0])
    for l in list(bump.inputs["Height"].links):
        nt.links.remove(l)
    L.new(h.outputs[0], bump.inputs["Height"])
    for l in list(bump.inputs["Strength"].links):
        nt.links.remove(l)
    bump.inputs["Strength"].default_value = 0.6
    bump.inputs["Distance"].default_value = 0.1  # mm

    # roughness: oilier/smoother on the plateaus, rougher in furrows, slow blotches
    blot = node("ShaderNodeTexNoise", Scale=0.04, Detail=3.0)
    L.new(co, blot.inputs["Vector"])
    r = math_node("MULTIPLY_ADD", blot.outputs["Fac"], 0.18, 0.30)
    r = math_node("MULTIPLY_ADD", furrow.outputs[0], -0.08, r.outputs[0])
    r = math_node("ADD", r.outputs[0], 0.1)
    for l in list(bsdf.inputs["Roughness"].links):
        nt.links.remove(l)
    L.new(r.outputs[0], bsdf.inputs["Roughness"])

    # tone: subtle blotchy redness / darker furrows on top of the MPFB texture
    if base_link_from is not None:
        tone = node("ShaderNodeTexNoise", Scale=0.08, Detail=4.0)
        L.new(co, tone.inputs["Vector"])
        ramp = N.new("ShaderNodeValToRGB")
        ramp.color_ramp.elements[0].color = (0.93, 0.86, 0.84, 1)
        ramp.color_ramp.elements[1].color = (1.04, 1.0, 0.98, 1)
        ramp.color_ramp.elements[0].position = 0.35
        ramp.color_ramp.elements[1].position = 0.65
        L.new(tone.outputs["Fac"], ramp.inputs["Fac"])
        hs = N.new("ShaderNodeHueSaturation")
        hs.inputs["Saturation"].default_value = 0.88
        L.new(base_link_from, hs.inputs["Color"])
        mul = N.new("ShaderNodeMix")
        mul.data_type = "RGBA"
        mul.blend_type = "MULTIPLY"
        mul.inputs["Factor"].default_value = 1.0
        L.new(hs.outputs["Color"], mul.inputs["A"])
        L.new(ramp.outputs["Color"], mul.inputs["B"])
        L.new(mul.outputs["Result"], bsdf.inputs["Base Color"])

    bsdf.inputs["Coat Weight"].default_value = 0.0
    for l in list(bsdf.inputs["Coat Weight"].links):
        nt.links.remove(l)


def _fix_skin(obj, sss_mm=1.4, sss_weight=0.7):
    """Re-tune the MPFB enhanced-SSS materials for a millimetre scene and add micro detail."""
    done = set()
    for slot in obj.material_slots:
        mat = slot.material
        if mat is None or not mat.use_nodes:
            continue
        for n in mat.node_tree.nodes:
            if n.type != "GROUP" or n.node_tree is None or n.node_tree in done:
                continue
            done.add(n.node_tree)
            if "SSS radius scale" in n.inputs:
                n.inputs["SSS radius R"].default_value = 1.0
                n.inputs["SSS radius G"].default_value = 0.42
                n.inputs["SSS radius B"].default_value = 0.22
                n.inputs["SSS radius scale"].default_value = 1.0
            nt = n.node_tree
            bsdf = next((g for g in nt.nodes if g.type == "BSDF_PRINCIPLED"), None)
            bump = next((g for g in nt.nodes if g.type == "BUMP"), None)
            if bsdf is None:
                continue
            bsdf.subsurface_method = "RANDOM_WALK_SKIN"
            bsdf.inputs["Subsurface Scale"].default_value = sss_mm
            # SSS weight: MPFB multiplies a mask texture by "SSS strength"; replace with a constant.
            for l in list(bsdf.inputs["Subsurface Weight"].links):
                nt.links.remove(l)
            bsdf.inputs["Subsurface Weight"].default_value = sss_weight
            is_body = mat.name.endswith("body") or ".body" in mat.name
            if bump is not None:
                bump.inputs["Distance"].default_value = 0.03
                if is_body:
                    base = bsdf.inputs["Base Color"].links[0].from_socket if bsdf.inputs["Base Color"].is_linked else None
                    _skin_microdetail(nt, bsdf, bump, base)


def _smoothstep(e0, e1, x):
    t = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
    return t * t * (3 - 2 * t)


def _add_hair(obj, density, melanin, knuckle_x, clear_x=24.0):
    """Sparse, fine body hair lying along the forearm (and a little on the back of the hand).

    No hair within |x| < clear_x (under the watch head/bracelet) or on the palm and fingers."""
    me = obj.data
    vg = obj.vertex_groups.new(name="hair")
    for v in me.vertices:
        x, n = v.co.x, v.normal
        band = _smoothstep(clear_x, clear_x + 16.0, abs(x))
        if x < 0:
            w = (0.3 + 0.7 * max(n.z, 0.0) + 0.35 * max(n.y, 0.0)) * _smoothstep(-5.0, 0.4, n.z + 0.35 * n.y)
        else:
            w = 0.45 * max(n.z, 0.0) ** 1.5 * (1.0 - _smoothstep(knuckle_x - 30.0, knuckle_x - 5.0, x))
        w = min(w * band, 1.0)
        if w > 0.001:
            vg.add([v.index], w, "REPLACE")

    mod = obj.modifiers.new("Hair", "PARTICLE_SYSTEM")
    ps = mod.particle_system
    ps.vertex_group_density = "hair"
    st = ps.settings
    st.name = "ArmHair"
    st.type = "HAIR"
    st.use_advanced_hair = True
    st.count = int(2500 * density)
    st.hair_length = 8.0
    st.emit_from = "FACE"
    st.use_emit_random = True
    st.distribution = "RAND"
    st.use_even_distribution = True
    st.normal_factor = 0.22
    st.object_align_factor = (1.0, 0.0, 0.0)
    st.factor_random = 0.25
    st.hair_step = 5
    st.display_step = 3
    st.render_step = 4
    st.child_type = "INTERPOLATED"
    st.child_percent = 3
    st.rendered_child_count = 4
    st.child_radius = 2.0
    st.child_length = 1.0
    st.child_length_threshold = 0.4
    st.roughness_1 = 0.25
    st.roughness_1_size = 1.0
    st.roughness_endpoint = 0.4
    st.roughness_end_shape = 1.0
    st.kink = "NO"
    st.radius_scale = 0.022  # mm (radius at root)
    st.root_radius = 1.0
    st.tip_radius = 0.15
    st.shape = -0.3
    st.use_close_tip = True

    mat = bpy.data.materials.new("ArmHair")
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        if n.type != "OUTPUT_MATERIAL":
            nt.nodes.remove(n)
    hb = nt.nodes.new("ShaderNodeBsdfHairPrincipled")
    hb.parametrization = "MELANIN"
    hb.inputs["Melanin"].default_value = melanin
    hb.inputs["Melanin Redness"].default_value = 0.35
    hb.inputs["Roughness"].default_value = 0.35
    hb.inputs["Radial Roughness"].default_value = 0.4
    hb.inputs["Coat"].default_value = 0.1
    hb.inputs["Random Roughness"].default_value = 0.2
    nt.links.new(hb.outputs[0], nt.nodes["Material Output"].inputs["Surface"])
    obj.data.materials.append(mat)
    st.material = len(obj.data.materials)


def _cross_section(obj, eps=60.0):
    """Section of the evaluated mesh with the plane x = 0 (points within eps of the axis)."""
    dg = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(dg)
    me = ev.to_mesh()
    mw = obj.matrix_world
    co = [mw @ v.co for v in me.vertices]
    pts = []
    for e in me.edges:
        a, b = co[e.vertices[0]], co[e.vertices[1]]
        if (a.x < 0) != (b.x < 0):
            t = a.x / (a.x - b.x)
            p = a.lerp(b, t)
            if abs(p.y) < eps and abs(p.z) < eps:
                pts.append(p)
    ev.to_mesh_clear()
    return pts


def _top_at_y0(pts, band=1.5):
    near = [p for p in pts if abs(p.y) < band]
    return max(p.z for p in near)


# --------------------------------------------------------------------------- main API


def add_wrist(skin="young_caucasian_male", case_back_z=-0.3, keep_radius=260.0, curl=0.35,
              subdiv=2, macros=None, hair=None):
    """Builds the arm in the current scene (assumes MPFB is enabled), in the watch frame.

    Only the left forearm + hand within keep_radius mm of the watch centre are kept
    (cut cleanly across the forearm, before the elbow). curl = 0..1 relaxed finger curl.
    Returns dict(half_width, half_depth, centre_z) of the wrist cross-section at the
    watch position in mm (half_width along Y, half_depth along Z).

    Extras: subdiv = render/viewport subdivision levels; macros = MPFB phenotype dict
    (default derived from the skin name); hair = arm-hair density 0..1 (None = by skin:
    1.0 male, 0.25 female; 0 disables). Hair is kept clear of |x| < 24 mm (watch/bracelet)."""
    from bl_ext.user_default.mpfb.services.humanservice import HumanService

    scene = bpy.context.scene
    if macros is None:
        macros = _macros_for_skin(skin)
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")

    human = HumanService.create_human(scale=1.0, feet_on_ground=False, macro_detail_dict=macros)
    rig = HumanService.add_builtin_rig(human, "default")
    HumanService.set_character_skin(_skin_path(skin), human, skin_type="ENHANCED_SSS")

    origin, rot, forearm_len = _bone_frame(rig)
    _pose_hand(rig, rot, curl)

    # Drop the helper mask so evaluated vertex indices match the base mesh.
    for m in list(human.modifiers):
        if m.type == "MASK":
            human.modifiers.remove(m)
    bpy.context.view_layer.update()

    # Which base-mesh vertices belong to the left forearm/hand skin.
    gi = {g.name: g.index for g in human.vertex_groups}
    body_i = gi["body"]
    arm_i = {gi[b] for b in ARM_BONES if b in gi}
    keep = []
    for v in human.data.vertices:
        in_body, arm_w = False, 0.0
        for g in v.groups:
            if g.group == body_i and g.weight > 0:
                in_body = True
            elif g.group in arm_i:
                arm_w += g.weight
        keep.append(in_body and arm_w > 0.45)

    dg = bpy.context.evaluated_depsgraph_get()
    mesh = bpy.data.meshes.new_from_object(human.evaluated_get(dg), preserve_all_data_layers=False, depsgraph=dg)
    mesh.name = "Wrist"

    # rig-local (dm) -> watch frame (mm), before the final translation
    to_watch = Matrix.Diagonal((100.0, 100.0, 100.0, 1.0)) @ rot.transposed().to_4x4() @ Matrix.Translation(-origin)
    to_watch = to_watch @ rig.matrix_world.inverted() @ human.matrix_world

    knuckle = to_watch @ rig.pose.bones["metacarpal2.L"].tail  # (human and rig share a transform)
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.verts.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not keep[v.index]], context="VERTS")
    bm.transform(to_watch)
    # Keep only the biggest connected piece (the arm), dropping stray islands.
    bm.verts.ensure_lookup_table()
    seen, best = set(), []
    for v in bm.verts:
        if v in seen:
            continue
        comp, stack = [], [v]
        seen.add(v)
        while stack:
            u = stack.pop()
            comp.append(u)
            for e in u.link_edges:
                w = e.other_vert(u)
                if w not in seen:
                    seen.add(w)
                    stack.append(w)
        if len(comp) > len(best):
            best = comp
    bs = set(best)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v not in bs], context="VERTS")
    # Clean planar cut across the forearm, short of the elbow and inside keep_radius.
    x_cut = -min(math.sqrt(max(keep_radius ** 2 - 45.0 ** 2, 1.0)), forearm_len - WATCH_FROM_WRIST - 25.0)
    geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
    bmesh.ops.bisect_plane(bm, geom=geom, plane_co=(x_cut, 0, 0), plane_no=(1, 0, 0),
                         clear_inner=True, dist=1e-4)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.length > keep_radius], context="VERTS")
    # Cap the cut so it never shows a hollow tube.
    boundary = [e for e in bm.edges if e.is_boundary]
    if boundary:
        bmesh.ops.holes_fill(bm, edges=boundary, sides=0)
    bm.to_mesh(mesh)
    bm.free()
    for p in mesh.polygons:
        p.use_smooth = True

    obj = bpy.data.objects.new("Wrist", mesh)
    scene.collection.objects.link(obj)
    sub = obj.modifiers.new("Subdivision", "SUBSURF")
    sub.levels = subdiv
    sub.render_levels = subdiv
    _fix_skin(obj)

    # Remove the MakeHuman source objects.
    arm_data = rig.data
    hmesh = human.data
    bpy.data.objects.remove(human)
    bpy.data.objects.remove(rig)
    bpy.data.meshes.remove(hmesh)
    bpy.data.armatures.remove(arm_data)

    # Centre the cross-section on y = 0 and seat the dorsal skin on the case back
    # (measured on the subdivided surface), then bake the offset into the mesh.
    bpy.context.view_layer.update()
    pts = _cross_section(obj)
    dy = -(min(p.y for p in pts) + max(p.y for p in pts)) / 2
    obj.location.y += dy
    bpy.context.view_layer.update()
    dz = case_back_z - _top_at_y0(_cross_section(obj))
    obj.location = (0.0, 0.0, 0.0)
    mesh.transform(Matrix.Translation((0.0, dy, dz)))
    bpy.context.view_layer.update()
    pts = _cross_section(obj)
    ymin, ymax = min(p.y for p in pts), max(p.y for p in pts)
    zmin, zmax = min(p.z for p in pts), max(p.z for p in pts)

    if hair is None:
        hair = 0.25 if "female" in os.path.basename(skin).lower() else 1.0
    if hair > 0:
        name = os.path.basename(skin).lower()
        melanin = 0.9 if ("african" in name or "asian" in name) else 0.6
        if "old" in name:
            melanin *= 0.6
        _add_hair(obj, hair, melanin, knuckle.x)

    return dict(half_width=(ymax - ymin) / 2, half_depth=(zmax - zmin) / 2, centre_z=(zmax + zmin) / 2)


# --------------------------------------------------------------------------- preview

HDRI_DIR = "/tmp/claude-0/-home-user-watch/2e7a6eb5-2ed1-5d58-a640-192c24a782e6/scratchpad/assets/hdri"
SCRATCH = "/tmp/claude-0/-home-user-watch/2e7a6eb5-2ed1-5d58-a640-192c24a782e6/scratchpad/wrist"


def _preview_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    o = {"size": 512, "samples": 24, "out": os.path.join(SCRATCH, "preview.png"),
         "skin": "young_caucasian_male", "curl": 0.35, "hdri": "studio_small_09", "view": "eye", "fstop": 0.0}
    for i in range(0, len(argv) - 1, 2):
        k, v = argv[i].lstrip("-"), argv[i + 1]
        o[k] = type(o[k])(v) if k in o else v
    return o


def _preview():
    import time

    import addon_utils

    o = _preview_args()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    addon_utils.enable("bl_ext.user_default.mpfb", default_set=True)
    scene = bpy.context.scene
    scene.unit_settings.scale_length = 0.001
    case_back_z = -0.3

    t = time.time()
    dims = add_wrist(skin=o["skin"], case_back_z=case_back_z, curl=o["curl"])
    print("add_wrist: %.2f s" % (time.time() - t), dims)

    # stand-in watch
    def mat(name, color, metallic, rough):
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        b = m.node_tree.nodes["Principled BSDF"]
        b.inputs["Base Color"].default_value = (*color, 1)
        b.inputs["Metallic"].default_value = metallic
        b.inputs["Roughness"].default_value = rough
        return m

    steel = mat("steel", (0.8, 0.8, 0.8), 1.0, 0.18)
    bpy.ops.mesh.primitive_cylinder_add(vertices=96, radius=20.0, depth=12.0, location=(0, 0, case_back_z + 6.0))
    case = bpy.context.object
    case.data.materials.append(steel)
    bpy.ops.object.shade_smooth()
    bpy.ops.mesh.primitive_cylinder_add(vertices=96, radius=17.5, depth=0.5, location=(0, 0, case_back_z + 12.0))
    dial = bpy.context.object
    dial.data.materials.append(mat("dial", (0.02, 0.05, 0.12), 0.0, 0.3))
    # 12 o'clock marker (+Y) and crown (+X)
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 14.5, case_back_z + 12.4), scale=(1.5, 4, 0.4))
    bpy.context.object.data.materials.append(steel)
    bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=2.8, depth=4, location=(21.5, 0, case_back_z + 6.0),
                                        rotation=(0, math.pi / 2, 0))
    bpy.context.object.data.materials.append(steel)

    # band: 20 mm wide elliptical loop around the wrist (slightly outside the skin)
    hw, hd, cz = dims["half_width"], dims["half_depth"], dims["centre_z"]
    bm = bmesh.new()
    n, th = 128, 2.0
    rings = []
    for xo in (-10.0, 10.0):
        for off in (0.4, 0.4 + th):
            ring = []
            for i in range(n):
                a = 2 * math.pi * i / n
                ring.append(bm.verts.new((xo, (hw + off) * math.cos(a), cz + (hd + off) * math.sin(a))))
            rings.append(ring)
    for ra, rb in ((rings[0], rings[2]), (rings[1], rings[3]), (rings[0], rings[1]), (rings[2], rings[3])):
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((ra[i], ra[j], rb[j], rb[i]))
    me = bpy.data.meshes.new("Band")
    bm.to_mesh(me)
    bm.free()
    band = bpy.data.objects.new("Band", me)
    scene.collection.objects.link(band)
    band.data.materials.append(mat("leather", (0.08, 0.035, 0.015), 0.0, 0.55))
    for p in me.polygons:
        p.use_smooth = True

    # world
    world = bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    nt = world.node_tree
    env = nt.nodes.new("ShaderNodeTexEnvironment")
    env.image = bpy.data.images.load(os.path.join(HDRI_DIR, o["hdri"] + ".exr"))
    nt.links.new(env.outputs["Color"], nt.nodes["Background"].inputs["Color"])
    nt.nodes["Background"].inputs["Strength"].default_value = 1.0

    # camera from the wearer's eye: -Y side, ~45 deg above, looking at the watch
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.lens = 80
    cam_data.clip_start = 5
    cam_data.clip_end = 5000
    cam = bpy.data.objects.new("Cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    target = Vector((25.0, 0.0, 5.0))
    views = {"eye": (Vector((25.0, -300.0, 300.0)), target),
             "macro": (Vector((60.0, -170.0, 150.0)), Vector((45.0, -10.0, -5.0))),
             "wide": (Vector((60.0, -480.0, 420.0)), Vector((60.0, 0.0, -5.0))),
             "elbow": (Vector((-480.0, -260.0, 160.0)), Vector((-150.0, 0.0, -20.0))),
             "top": (Vector((40.0, 0.0, 520.0)), Vector((40.0, 0.0, 0.0))),
             "side": (Vector((40.0, -520.0, 0.0)), Vector((40.0, 0.0, 0.0))),
             "palm": (Vector((60.0, 0.0, -520.0)), Vector((60.0, 0.0, 0.0)))}
    loc, tgt = views[o["view"]]
    cam.location = loc
    cam.rotation_euler = (tgt - loc).to_track_quat("-Z", "Y").to_euler()
    if o["view"] in ("top", "side", "palm"):
        cam_data.lens = 50
    cam_data.dof.use_dof = True
    cam_data.dof.focus_distance = (Vector((0, 0, case_back_z + 12)) - loc).length
    # Cycles derives the aperture from the lens in metres and ignores unit scale, so a
    # physical f-number N must be given as N * scale_length in a millimetre scene.
    f_number = o["fstop"] or (4.0 if o["view"] in ("eye", "wide", "macro") else 22.0)
    cam_data.dof.aperture_fstop = f_number * scene.unit_settings.scale_length

    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = o["samples"]
    scene.cycles.use_denoising = True
    scene.render.resolution_x = o["size"]
    scene.render.resolution_y = int(o["size"] * 0.75)
    scene.render.filepath = o["out"]
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Medium High Contrast"
    t = time.time()
    bpy.ops.render.render(write_still=True)
    print("render: %.1f s -> %s" % (time.time() - t, o["out"]))


if __name__ == "__main__":
    _preview()
