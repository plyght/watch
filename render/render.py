"""Renders out/watch.obj with Blender Cycles.

Run:  blender -b -P render/render.py -- [--samples N] [--size PX] [view ...]

Blender's scripting interface is Python-only, so this scene setup is the one
non-Zig file in the project. All geometry comes from the Zig generator.
"""

import math
import os
import sys

import bpy
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# view name: (camera position, look-at point, lens in mm)
VIEWS = {
    "hero": ((38, -112, 118), (0, 1, 4), 85),
    "face": ((0, -4, 230), (0, 0, 5), 110),
    "side": ((120, -95, 42), (0, 0, 4), 85),
}


def args():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    samples, size, names = 128, 1400, []
    i = 0
    while i < len(argv):
        if argv[i] == "--samples":
            samples = int(argv[i + 1]); i += 2
        elif argv[i] == "--size":
            size = int(argv[i + 1]); i += 2
        else:
            names.append(argv[i]); i += 1
    return samples, size, names or list(VIEWS)


def principled(name, color, metallic=0.0, roughness=0.5):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    return mat


def brushed(name, color, roughness, direction):
    """Metal with a fine directional grain, like a brushed finish."""
    mat = principled(name, color, 1.0, roughness)
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    coord = nt.nodes.new("ShaderNodeTexCoord")
    mapping = nt.nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = direction
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 1.0
    noise.inputs["Detail"].default_value = 3.0
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.12
    bump.inputs["Distance"].default_value = 0.02
    nt.links.new(coord.outputs["Object"], mapping.inputs["Vector"])
    nt.links.new(mapping.outputs["Vector"], noise.inputs["Vector"])
    nt.links.new(noise.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def glass_material():
    mat = bpy.data.materials.new("sapphire")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Transmission Weight"].default_value = 1.0
    bsdf.inputs["Roughness"].default_value = 0.0
    bsdf.inputs["IOR"].default_value = 1.25  # low value stands in for an anti-reflective coating
    # Let light reach the dial directly instead of relying on caustics.
    out = nt.nodes["Material Output"]
    path = nt.nodes.new("ShaderNodeLightPath")
    clear = nt.nodes.new("ShaderNodeBsdfTransparent")
    mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(path.outputs["Is Shadow Ray"], mix.inputs["Fac"])
    nt.links.new(bsdf.outputs["BSDF"], mix.inputs[1])
    nt.links.new(clear.outputs["BSDF"], mix.inputs[2])
    nt.links.new(mix.outputs["Shader"], out.inputs["Surface"])
    return mat


def look_at(obj, target):
    direction = Vector(target) - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def softbox(name, location, target, size, strength):
    """An emissive panel; brightness does not depend on distance or scene scale."""
    bpy.ops.mesh.primitive_plane_add(size=1, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = (size[0], size[1], 1)
    look_at(obj, target)
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
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


def build_scene(samples, size):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    bpy.ops.wm.obj_import(filepath=os.path.join(ROOT, "out", "watch.obj"), forward_axis="Y", up_axis="Z")

    steel = (0.74, 0.74, 0.75)
    mats = {
        "brushed": brushed("brushed", steel, 0.30, (0.4, 60, 60)),
        "polished": principled("polished", (0.80, 0.80, 0.81), 1.0, 0.06),
        "satin": principled("satin", steel, 1.0, 0.26),
        "insert": principled("insert", (0.006, 0.006, 0.007), 0.0, 0.07),
        "dial": principled("dial", (0.004, 0.004, 0.005), 0.0, 0.75),
        "rehaut": principled("rehaut", (0.01, 0.01, 0.011), 0.0, 0.3),
        "lume": principled("lume", (0.82, 0.86, 0.78), 0.0, 0.7),
        "print": principled("print", (0.85, 0.85, 0.83), 0.0, 0.5),
        "glass": glass_material(),
        "brass": principled("brass", (0.83, 0.61, 0.27), 1.0, 0.25),
        "plate": brushed("plate", (0.78, 0.60, 0.30), 0.35, (40, 40, 40)),
        "ruby": principled("ruby", (0.55, 0.01, 0.05), 0.0, 0.1),
        "floor": principled("floor", (0.55, 0.55, 0.53), 0.0, 0.5),
    }
    assign = {
        "case_mid": "brushed", "case_back": "satin", "crown_guard": "brushed", "crown": "polished",
        "bezel": "polished", "insert": "insert", "insert_pip": "lume", "rehaut": "rehaut",
        "crystal": "glass", "dial": "dial", "cut_emblem": "polished", "print": "print",
        "marker_steel": "polished", "marker_lume": "lume", "hand_steel": "polished", "hand_lume": "lume",
        "mov_plate": "plate", "mov_brass": "brass", "mov_steel": "satin", "mov_ruby": "ruby",
        "bracelet": "brushed", "bracelet_mid": "satin",
    }

    # Objects that share a name arrive as name, name.001, ...; join them.
    groups = {}
    for obj in scene.objects:
        if obj.type == "MESH":
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
        parts[name] = part

    for name, obj in parts.items():
        mesh = obj.data
        mesh.materials.clear()
        mesh.materials.append(mats[assign[name]])
        bpy.ops.object.select_all(action="DESELECT")
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.mesh.normals_make_consistent(inside=False)
        bpy.ops.object.mode_set(mode="OBJECT")

    # Cut the emblem out of the dial. The cut walls take the cutter's
    # polished material, so the windows get a bright machined edge.
    dial, cutter = parts["dial"], parts["cut_emblem"]
    dial.data.materials.append(mats["polished"])
    mod = dial.modifiers.new("emblem", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.object = cutter
    mod.solver = "EXACT"
    mod.material_mode = "TRANSFER"
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = dial
    dial.select_set(True)
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.data.objects.remove(cutter)
    del parts["cut_emblem"]

    for obj in parts.values():
        for poly in obj.data.polygons:
            poly.use_smooth = True
        obj.data.set_sharp_from_angle(angle=math.radians(28))

    # Printed text: the wordmark on the dial and the minute scale on the bezel.
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

    bpy.ops.mesh.primitive_plane_add(size=4000, location=(0, 0, -0.3))
    bpy.context.object.data.materials.append(mats["floor"])

    world = bpy.data.worlds.new("world")
    world.use_nodes = True
    scene.world = world
    nt = world.node_tree
    env = nt.nodes.new("ShaderNodeTexEnvironment")
    env.image = bpy.data.images.load(os.path.join(
        bpy.utils.resource_path("LOCAL"), "datafiles", "studiolights", "world", "studio.exr"))
    mapping = nt.nodes.new("ShaderNodeMapping")
    mapping.inputs["Rotation"].default_value = (0, 0, math.radians(110))
    coord = nt.nodes.new("ShaderNodeTexCoord")
    nt.links.new(coord.outputs["Generated"], mapping.inputs["Vector"])
    nt.links.new(mapping.outputs["Vector"], env.inputs["Vector"])
    nt.links.new(env.outputs["Color"], nt.nodes["Background"].inputs["Color"])
    nt.nodes["Background"].inputs["Strength"].default_value = 0.45

    target = (0, 0, 5)
    softbox("overhead", (0, 170, 250), target, (360, 240), 1.1)
    softbox("left", (-260, -30, 110), target, (160, 260), 3.0)
    softbox("right", (240, 60, 60), target, (60, 300), 4.5)
    softbox("front", (0, -260, 60), target, (320, 90), 2.2)

    cam = bpy.data.objects.new("camera", bpy.data.cameras.new("camera"))
    cam.data.clip_start, cam.data.clip_end = 1, 5000
    bpy.context.collection.objects.link(cam)
    scene.camera = cam

    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.cycles.max_bounces = 10
    scene.render.resolution_x = scene.render.resolution_y = size
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Medium High Contrast"
    return scene, cam


def main():
    samples, size, names = args()
    scene, cam = build_scene(samples, size)
    out_dir = os.path.join(ROOT, "renders")
    os.makedirs(out_dir, exist_ok=True)
    for name in names:
        position, target, lens = VIEWS[name]
        cam.location = position
        cam.data.lens = lens
        look_at(cam, target)
        scene.render.filepath = os.path.join(out_dir, f"diver-{name}.png")
        bpy.ops.render.render(write_still=True)


main()
