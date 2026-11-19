"""Renders a watch from the Zig generator with Blender Cycles.

Run:  blender -b -P render/render.py -- MODEL [--samples N] [--size PX] [VIEW ...]

MODEL is diver, chamber or impact. VIEWs are hero, face, side and wrist
(default: hero face wrist). Images go to renders/MODEL-VIEW.png.

Blender's scripting interface is Python-only, so scene setup lives here; all
watch geometry comes from the Zig generator (`zig build run -- MODEL ...`).
"""

import math
import os
import subprocess
import sys

import bpy
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
HDRI_DIR = os.environ.get(
    "WATCH_HDRI_DIR",
    "/tmp/claude-0/-home-user-watch/2e7a6eb5-2ed1-5d58-a640-192c24a782e6/scratchpad/assets/hdri",
)

# view: (camera position, look-at point, lens mm, f-stop)
VIEWS = {
    "hero": ((40, -118, 112), (0, 2, 4), 90, 11.0),
    "face": ((0, -3, 235), (0, 0, 5), 110, 16.0),
    "side": ((125, -92, 38), (0, 0, 4), 90, 11.0),
    "wrist": ((-6, -150, 128), (14, -2, 2), 70, 5.6),
}

LINK_HALF = 1.6  # half the bracelet link thickness, mm


def args():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    model, samples, size, views = "diver", 128, 1400, []
    i = 0
    while i < len(argv):
        if argv[i] == "--samples":
            samples = int(argv[i + 1]); i += 2
        elif argv[i] == "--size":
            size = int(argv[i + 1]); i += 2
        elif argv[i] in VIEWS:
            views.append(argv[i]); i += 1
        else:
            model = argv[i]; i += 1
    return model, samples, size, views or ["hero", "face", "wrist"]


# ---------------------------------------------------------------- materials

def node_material(name):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    return mat, mat.node_tree, mat.node_tree.nodes["Principled BSDF"]


def principled(name, color, metallic=0.0, roughness=0.5, coat=0.0):
    mat, _, bsdf = node_material(name)
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Coat Weight"].default_value = coat
    return mat


def brushed(name, color, roughness, axis="Z", anisotropy=0.6, grain=(0.4, 60, 60)):
    """Metal with directional brushing: anisotropic highlights around `axis`
    plus a fine grain bump."""
    mat, nt, bsdf = node_material(name)
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Metallic"].default_value = 1.0
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Anisotropic"].default_value = anisotropy
    tangent = nt.nodes.new("ShaderNodeTangent")
    tangent.direction_type = "RADIAL"
    tangent.axis = axis
    nt.links.new(tangent.outputs["Tangent"], bsdf.inputs["Tangent"])
    coord = nt.nodes.new("ShaderNodeTexCoord")
    mapping = nt.nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = grain
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 1.0
    noise.inputs["Detail"].default_value = 4.0
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.08
    bump.inputs["Distance"].default_value = 0.01
    nt.links.new(coord.outputs["Object"], mapping.inputs["Vector"])
    nt.links.new(mapping.outputs["Vector"], noise.inputs["Vector"])
    nt.links.new(noise.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def antique(name, dark, bright, contrast=1.0, ao_distance=0.6):
    """Aged gunmetal: recesses blackened, exposed high points worn bright and
    smoother, driven by ambient occlusion so engraving reads strongly."""
    mat, nt, bsdf = node_material(name)
    bsdf.inputs["Metallic"].default_value = 1.0
    ao = nt.nodes.new("ShaderNodeAmbientOcclusion")
    ao.inputs["Distance"].default_value = ao_distance
    ao.samples = 12
    shape = nt.nodes.new("ShaderNodeMapRange")
    shape.inputs["From Min"].default_value = 0.35
    shape.inputs["From Max"].default_value = 1.0
    gamma = nt.nodes.new("ShaderNodeMath")
    gamma.operation = "POWER"
    gamma.inputs[1].default_value = 2.2 * contrast
    nt.links.new(ao.outputs["AO"], shape.inputs["Value"])
    nt.links.new(shape.outputs["Result"], gamma.inputs[0])

    # Mottled wear so the patina is not uniform.
    coord = nt.nodes.new("ShaderNodeTexCoord")
    mottle = nt.nodes.new("ShaderNodeTexNoise")
    mottle.inputs["Scale"].default_value = 1.6
    mottle.inputs["Detail"].default_value = 6.0
    nt.links.new(coord.outputs["Object"], mottle.inputs["Vector"])
    wear = nt.nodes.new("ShaderNodeMath")
    wear.operation = "MULTIPLY"
    nt.links.new(gamma.outputs["Value"], wear.inputs[0])
    blend = nt.nodes.new("ShaderNodeMapRange")
    blend.inputs["To Min"].default_value = 0.9
    blend.inputs["To Max"].default_value = 1.05
    nt.links.new(mottle.outputs["Fac"], blend.inputs["Value"])
    nt.links.new(blend.outputs["Result"], wear.inputs[1])

    color = nt.nodes.new("ShaderNodeMix")
    color.data_type = "RGBA"
    color.clamp_factor = True
    color.inputs["A"].default_value = (*dark, 1)
    color.inputs["B"].default_value = (*bright, 1)
    nt.links.new(wear.outputs["Value"], color.inputs["Factor"])
    nt.links.new(color.outputs["Result"], bsdf.inputs["Base Color"])

    rough = nt.nodes.new("ShaderNodeMapRange")
    rough.inputs["To Min"].default_value = 0.62
    rough.inputs["To Max"].default_value = 0.26
    nt.links.new(wear.outputs["Value"], rough.inputs["Value"])
    nt.links.new(rough.outputs["Result"], bsdf.inputs["Roughness"])

    # Fine satin grain.
    grain = nt.nodes.new("ShaderNodeTexNoise")
    grain.inputs["Scale"].default_value = 18.0
    grain.inputs["Detail"].default_value = 3.0
    nt.links.new(coord.outputs["Object"], grain.inputs["Vector"])
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.06
    bump.inputs["Distance"].default_value = 0.01
    nt.links.new(grain.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def glass_material():
    mat, nt, bsdf = node_material("sapphire")
    bsdf.inputs["Transmission Weight"].default_value = 1.0
    bsdf.inputs["Roughness"].default_value = 0.0
    bsdf.inputs["IOR"].default_value = 1.3  # stands in for an anti-reflective coating
    bsdf.inputs["Base Color"].default_value = (0.96, 0.98, 1.0, 1)
    out = nt.nodes["Material Output"]
    path = nt.nodes.new("ShaderNodeLightPath")
    clear = nt.nodes.new("ShaderNodeBsdfTransparent")
    mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(path.outputs["Is Shadow Ray"], mix.inputs["Fac"])
    nt.links.new(bsdf.outputs["BSDF"], mix.inputs[1])
    nt.links.new(clear.outputs["BSDF"], mix.inputs[2])
    nt.links.new(mix.outputs["Shader"], out.inputs["Surface"])
    return mat


def make_materials():
    steel = (0.74, 0.74, 0.75)
    gunmetal_dark = (0.025, 0.025, 0.028)
    gunmetal_bright = (0.52, 0.52, 0.53)
    return {
        # diver
        "brushed": brushed("brushed", steel, 0.28),
        "bracelet_brushed": brushed("bracelet_brushed", steel, 0.3, axis="X"),
        "polished": principled("polished", (0.82, 0.82, 0.83), 1.0, 0.05),
        "satin": principled("satin", steel, 1.0, 0.26),
        "insert": principled("insert", (0.006, 0.006, 0.007), 0.0, 0.06, coat=1.0),
        "dial": principled("dial", (0.004, 0.004, 0.005), 0.0, 0.75),
        "rehaut": principled("rehaut", (0.01, 0.01, 0.011), 0.0, 0.3),
        "lume": principled("lume", (0.84, 0.88, 0.80), 0.0, 0.65),
        "print": principled("print", (0.86, 0.86, 0.84), 0.0, 0.5),
        "print_dark": principled("print_dark", (0.02, 0.02, 0.02), 0.0, 0.5),
        "glass": glass_material(),
        "bright": principled("bright", (0.85, 0.85, 0.86), 0.5, 0.35),
        "dark": principled("dark", (0.16, 0.16, 0.17), 1.0, 0.3),
        "accent": principled("accent", (0.80, 0.07, 0.015), 0.0, 0.4),
        "plate": principled("plate", (0.62, 0.62, 0.63), 0.0, 0.6),
        "ruby": principled("ruby", (0.55, 0.01, 0.05), 0.0, 0.1),
        # chamber family
        "antique": antique("antique", gunmetal_dark, gunmetal_bright),
        "antique_bezel": antique("antique_bezel", gunmetal_dark, (0.6, 0.6, 0.61), contrast=1.3, ao_distance=0.8),
        "engraved": antique("engraved", (0.008, 0.008, 0.009), (0.48, 0.48, 0.49), contrast=1.6, ao_distance=0.25),
        "silver_disc": brushed("silver_disc", (0.80, 0.80, 0.80), 0.3, axis="Z", anisotropy=0.7),
        "black_disc": principled("black_disc", (0.01, 0.01, 0.01), 0.0, 0.8),
        "brass": principled("brass", (0.93, 0.72, 0.36), 1.0, 0.2),
        "primer": principled("primer", (0.86, 0.80, 0.66), 1.0, 0.25),
        "gold": principled("gold", (1.0, 0.76, 0.33), 1.0, 0.1),
        "case_back": principled("case_back", (0.5, 0.5, 0.51), 1.0, 0.35),
        "floor": principled("floor", (0.89, 0.89, 0.87), 0.0, 0.6),
    }


ASSIGN = {
    # diver
    "case_mid": "brushed", "case_back": "satin", "crown": "polished", "bezel": "polished",
    "insert": "insert", "insert_pip": "lume", "rehaut": "rehaut", "crystal": "glass",
    "dial": "dial", "cut_emblem": "polished", "print": "print", "print_dark": "print_dark",
    "marker_steel": "polished", "marker_lume": "lume", "hand_steel": "polished", "hand_lume": "lume",
    "mov_plate": "plate", "mov_bright": "bright", "mov_steel": "dark", "mov_ruby": "ruby",
    "fracture": "polished", "hand_accent": "accent",
    "bracelet": "bracelet_brushed", "bracelet_mid": "polished",
    # chamber family
    "antique": "antique", "antique_bezel": "antique_bezel", "engraved": "engraved",
    "silver_disc": "silver_disc", "black_disc": "black_disc", "brass": "brass",
    "primer": "primer", "gold": "gold", "polished": "polished",
}

# Parts whose hard edges get a small rounded bevel, as machined metal has.
BEVEL = {"case_mid", "crown", "bezel", "bracelet", "bracelet_mid", "marker_steel", "hand_steel", "antique", "gold", "polished"}


# ---------------------------------------------------------------- scene

def look_at(obj, target):
    direction = Vector(target) - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def softbox(name, location, target, size, strength):
    """An emissive panel for reflections and highlights, unseen by the camera."""
    bpy.ops.mesh.primitive_plane_add(size=1, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = (size[0], size[1], 1)
    look_at(obj, target)
    mat, nt, _ = node_material(name)
    emit = nt.nodes.new("ShaderNodeEmission")
    emit.inputs["Strength"].default_value = strength
    nt.links.new(emit.outputs["Emission"], nt.nodes["Material Output"].inputs["Surface"])
    obj.data.materials.append(mat)
    obj.visible_camera = False
    return obj


def text(body, size, location, mat, rotation=0.0, weight=0.0):
    curve = bpy.data.curves.new(body, "FONT")
    curve.body = body
    curve.size = size
    curve.align_x = "CENTER"
    curve.align_y = "CENTER"
    curve.extrude = 0.008
    curve.offset = weight
    obj = bpy.data.objects.new(body, curve)
    obj.location = location
    obj.rotation_euler = (0, 0, rotation)
    obj.data.materials.append(mat)
    bpy.context.collection.objects.link(obj)
    return obj


def world(hdri, strength, rotation, visible):
    w = bpy.data.worlds.new("world")
    w.use_nodes = True
    bpy.context.scene.world = w
    nt = w.node_tree
    env = nt.nodes.new("ShaderNodeTexEnvironment")
    env.image = bpy.data.images.load(os.path.join(HDRI_DIR, hdri + ".exr"))
    mapping = nt.nodes.new("ShaderNodeMapping")
    mapping.inputs["Rotation"].default_value = (0, 0, math.radians(rotation))
    coord = nt.nodes.new("ShaderNodeTexCoord")
    nt.links.new(coord.outputs["Generated"], mapping.inputs["Vector"])
    nt.links.new(mapping.outputs["Vector"], env.inputs["Vector"])
    nt.links.new(env.outputs["Color"], nt.nodes["Background"].inputs["Color"])
    nt.nodes["Background"].inputs["Strength"].default_value = strength
    w.cycles_visibility.camera = visible


def generate(model, wrist=None):
    """Runs the Zig generator and returns the OBJ path."""
    path = os.path.join(ROOT, "out", f"{model}{'-wrist' if wrist else ''}.obj")
    if os.environ.get("WATCH_SKIP_GEN"):
        return path
    cmd = ["zig", "build", "run", "-Doptimize=ReleaseFast", "--", model]
    if wrist:
        cmd += ["wrist", f"{wrist[0]:.3f}", f"{wrist[1]:.3f}", f"{wrist[2]:.3f}"]
    subprocess.run(cmd, cwd=ROOT, check=True)
    return path


def import_watch(path, mats):
    bpy.ops.wm.obj_import(filepath=path, forward_axis="Y", up_axis="Z")
    scene = bpy.context.scene
    groups = {}
    for obj in list(scene.objects):
        if obj.type == "MESH" and obj.get("watch_part") is None and obj.name.split(".")[0] in ASSIGN:
            groups.setdefault(obj.name.split(".")[0], []).append(obj)
    parts = {}
    for name, objs in groups.items():
        bpy.ops.object.select_all(action="DESELECT")
        for obj in objs:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        if len(objs) > 1:
            bpy.ops.object.join()
        part = bpy.context.view_layer.objects.active
        part.name = name
        part["watch_part"] = True
        parts[name] = part

    for name, obj in parts.items():
        mesh = obj.data
        mesh.materials.clear()
        mesh.materials.append(mats[ASSIGN[name]])
        bpy.ops.object.select_all(action="DESELECT")
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.mesh.remove_doubles(threshold=0.0005)
        bpy.ops.mesh.normals_make_consistent(inside=False)
        bpy.ops.object.mode_set(mode="OBJECT")

    # Cut the diver's emblem out of its dial; the cut walls take the cutter's
    # polished material, giving the windows a bright machined edge.
    if "cut_emblem" in parts:
        dial, cutter = parts["dial"], parts["cut_emblem"]
        dial.data.materials.append(mats["polished"])
        mod = dial.modifiers.new("emblem", "BOOLEAN")
        mod.operation = "DIFFERENCE"
        mod.object = cutter
        mod.solver = "EXACT"
        mod.material_mode = "TRANSFER"
        bpy.context.view_layer.objects.active = dial
        bpy.ops.object.modifier_apply(modifier=mod.name)
        bpy.data.objects.remove(cutter)
        del parts["cut_emblem"]

    for name, obj in parts.items():
        for poly in obj.data.polygons:
            poly.use_smooth = True
        obj.data.set_sharp_from_angle(angle=math.radians(28 if name != "antique_bezel" else 50))
        if name in BEVEL:
            bevel = obj.modifiers.new("edges", "BEVEL")
            bevel.width = 0.12 if name in {"marker_steel", "hand_steel", "gold", "polished"} else 0.25
            bevel.segments = 3
            bevel.limit_method = "ANGLE"
            bevel.angle_limit = math.radians(35)
            bevel.harden_normals = True
    return parts


def diver_extras(mats):
    """Printed text the generator does not model: the dial wordmark and the
    bezel's minute scale."""
    text("semicentric", 1.2, (5.4, -8.6, 7.41), mats["print"])
    for minutes in (10, 20, 30, 40, 50):
        a = math.radians(minutes * 6)
        text(str(minutes), 2.1, (17.6 * math.sin(a), 17.6 * math.cos(a), 9.93), mats["print"], rotation=-a, weight=0.02)
    for minute in range(60):
        if minute % 10 == 0:
            continue
        a = math.radians(minute * 6)
        long = minute % 5 == 0
        bpy.ops.mesh.primitive_cube_add(size=1, location=(17.6 * math.sin(a), 17.6 * math.cos(a), 9.92))
        tick = bpy.context.object
        tick.scale = (0.28 if long else 0.12, 1.9 if long else 0.9, 0.02)
        tick.rotation_euler = (0, 0, -a)
        tick.data.materials.append(mats["print"])


def backdrop(mats):
    """A seamless sweep, like a product-photography paper backdrop."""
    bpy.ops.mesh.primitive_plane_add(size=1)
    sweep = bpy.context.object
    mesh = sweep.data
    import bmesh
    bm = bmesh.new()
    rows = []
    for k in range(25):
        t = k / 24
        if t < 0.6:
            y, z = -900 + 1500 * t / 0.6, -0.3
        else:
            a = (t - 0.6) / 0.4 * math.pi / 2
            y, z = 600 + 400 * math.sin(a), -0.3 + 400 * (1 - math.cos(a))
        rows.append((bm.verts.new((-900, y, z)), bm.verts.new((900, y, z))))
    for (a0, a1), (b0, b1) in zip(rows, rows[1:]):
        bm.faces.new((a0, a1, b1, b0))
    bm.to_mesh(mesh)
    bm.free()
    for poly in mesh.polygons:
        poly.use_smooth = True
    mesh.materials.clear()
    mesh.materials.append(mats["floor"])


def setup(model, view, samples, size):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.scale_length = 0.001  # 1 unit = 1 mm, so depth of field is physical
    mats = make_materials()

    if view == "wrist":
        import addon_utils
        addon_utils.enable("bl_ext.user_default.mpfb", default_set=True)
        import wrist
        dims = wrist.add_wrist(case_back_z=-0.3)
        band = (dims["half_width"] + LINK_HALF + 0.25, dims["half_depth"] + LINK_HALF + 0.25, dims["centre_z"])
        import_watch(generate(model, band), mats)
        world("brown_photostudio_02", 1.0, 200, True)
    else:
        import_watch(generate(model), mats)
        backdrop(mats)
        world("studio_small_09", 0.8, 110, False)
        target = (0, 0, 5)
        softbox("key", (-260, -30, 160), target, (160, 260), 2.4)
        softbox("strip", (240, 60, 70), target, (50, 300), 3.5)
        softbox("front", (0, -260, 60), target, (320, 80), 1.4)
    if model == "diver":
        diver_extras(mats)

    position, target, lens, fstop = VIEWS[view]
    cam = bpy.data.objects.new("camera", bpy.data.cameras.new("camera"))
    cam.data.clip_start, cam.data.clip_end = 1, 20000
    cam.data.lens = lens
    cam.location = position
    look_at(cam, target)
    bpy.context.collection.objects.link(cam)
    scene.camera = cam
    focus = bpy.data.objects.new("focus", None)
    focus.location = (0, 0, 8)
    bpy.context.collection.objects.link(focus)
    cam.data.dof.use_dof = True
    cam.data.dof.focus_object = focus
    cam.data.dof.aperture_fstop = fstop

    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.cycles.max_bounces = 12
    scene.render.resolution_x = scene.render.resolution_y = size
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Medium High Contrast"
    return scene


def main():
    model, samples, size, views = args()
    out_dir = os.path.join(ROOT, "renders")
    os.makedirs(out_dir, exist_ok=True)
    for view in views:
        scene = setup(model, view, samples, size)
        scene.render.filepath = os.path.join(out_dir, f"{model}-{view}.png")
        bpy.ops.render.render(write_still=True)


main()
