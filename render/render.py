"""Renders out/watch.obj in each case finish with Blender Cycles.

Run:  blender -b -P render/render.py -- [--samples N] [--size PX] [variant ...]

Blender's scripting interface is Python-only, so this scene setup is the one
non-Zig file in the project. All geometry comes from the Zig generator.
"""

import math
import os
import sys

import bpy
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# name: (label, base colour, roughness, bezel roughness, strap colour)
VARIANTS = {
    "titanium": ("01  blasted titanium", (0.36, 0.34, 0.32), 0.48, 0.40, (0.012, 0.012, 0.012)),
    "steel": ("02  brushed + polished steel", (0.72, 0.72, 0.73), 0.24, 0.07, (0.012, 0.012, 0.012)),
    "gunmetal": ("03  black DLC gunmetal", (0.075, 0.075, 0.085), 0.30, 0.16, (0.012, 0.012, 0.012)),
    "bronze": ("04  bronze", (0.70, 0.40, 0.19), 0.30, 0.14, (0.05, 0.022, 0.01)),
    "anodized": ("05  anodized titanium, deep blue", (0.03, 0.08, 0.42), 0.32, 0.20, (0.012, 0.012, 0.012)),
    "silver": ("06  cast silver", (0.93, 0.92, 0.89), 0.20, 0.06, (0.012, 0.012, 0.012)),
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
    return samples, size, names or list(VARIANTS)


def principled(name, color, metallic=0.0, roughness=0.5):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    return mat


def dial_material():
    """Matte black with a fine grid of cells, like a memory array."""
    mat = principled("dial", (0.006, 0.006, 0.007), 0.0, 0.55)
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    coord = nt.nodes.new("ShaderNodeTexCoord")
    brick = nt.nodes.new("ShaderNodeTexBrick")
    brick.offset = 0.0
    brick.inputs["Scale"].default_value = 0.55
    brick.inputs["Mortar Size"].default_value = 0.03
    brick.inputs["Brick Width"].default_value = 0.5
    brick.inputs["Row Height"].default_value = 0.5
    ramp = nt.nodes.new("ShaderNodeMapRange")
    ramp.inputs["To Min"].default_value = 0.7
    ramp.inputs["To Max"].default_value = 0.2
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.6
    bump.inputs["Distance"].default_value = 0.05
    bump.invert = True
    nt.links.new(coord.outputs["Object"], brick.inputs["Vector"])
    nt.links.new(brick.outputs["Fac"], ramp.inputs["Value"])
    nt.links.new(ramp.outputs["Result"], bsdf.inputs["Roughness"])
    nt.links.new(brick.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def glass_material():
    mat = bpy.data.materials.new("sapphire")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Transmission Weight"].default_value = 1.0
    bsdf.inputs["Roughness"].default_value = 0.0
    bsdf.inputs["IOR"].default_value = 1.22  # low value stands in for an anti-reflective coating
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


def set_color(mat, color, roughness):
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Roughness"].default_value = roughness


def look_at(obj, target):
    from mathutils import Vector
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


def text(body, size, location, mat, align="CENTER"):
    curve = bpy.data.curves.new(body, "FONT")
    curve.body = body
    curve.size = size
    curve.align_x = align
    curve.extrude = 0.01
    obj = bpy.data.objects.new(body, curve)
    obj.location = location
    obj.data.materials.append(mat)
    bpy.context.collection.objects.link(obj)
    return obj


def build_scene(samples, size):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.scale_length = 0.001

    bpy.ops.wm.obj_import(filepath=os.path.join(ROOT, "out", "watch.obj"), forward_axis="Y", up_axis="Z")

    mats = {
        "case": principled("case", (0.5, 0.5, 0.5), 1.0, 0.3),
        "bezel": principled("bezel", (0.5, 0.5, 0.5), 1.0, 0.1),
        "bright": principled("bright", (0.90, 0.90, 0.90), 1.0, 0.22),
        "dial": dial_material(),
        "rehaut": principled("rehaut", (0.012, 0.012, 0.013), 0.0, 0.35),
        "glass": glass_material(),
        "strap": principled("strap", (0.012, 0.012, 0.012), 0.0, 0.62),
        "accent": principled("accent", (0.80, 0.07, 0.015), 0.0, 0.4),
        "print": principled("print", (0.80, 0.80, 0.78), 0.0, 0.5),
        "floor": principled("floor", (0.60, 0.60, 0.58), 0.0, 0.55),
        "label": principled("label", (0.03, 0.03, 0.03), 0.0, 0.6),
    }
    assign = {
        "case_mid": "case", "case_back": "case", "lugs": "case", "crown": "case",
        "bezel": "bezel", "rehaut": "rehaut", "crystal": "glass", "dial": "dial",
        "emblem": "bright", "markers": "bright", "hand_hour": "bright",
        "hand_minute": "bright", "hand_cap": "bright", "hand_second": "accent",
        "strap": "strap",
    }
    for obj in list(scene.objects):
        if obj.type != "MESH":
            continue
        mesh = obj.data
        mesh.materials.clear()
        mesh.materials.append(mats[assign[obj.name]])
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.mesh.normals_make_consistent(inside=False)
        bpy.ops.object.mode_set(mode="OBJECT")
        obj.select_set(False)
        for poly in mesh.polygons:
            poly.use_smooth = True
        mesh.set_sharp_from_angle(angle=math.radians(24))

    # Wordmark on the dial, below the long blade of the emblem.
    text("semicentric", 1.15, (5.6, -7.2, 7.005), mats["print"])

    bpy.ops.mesh.primitive_plane_add(size=4000, location=(0, 0, -1.25))
    bpy.context.object.data.materials.append(mats["floor"])

    label = text("", 2.1, (-37, 33, -1.24), mats["label"], align="LEFT")

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

    target = (0, -1.0, 5.0)
    softbox("overhead", (0, 170, 250), target, (360, 240), 1.6)
    softbox("left", (-260, -30, 110), target, (160, 260), 3.0)
    softbox("right", (240, 60, 60), target, (60, 300), 4.5)
    softbox("front", (0, -260, 60), target, (320, 90), 2.2)

    cam_data = bpy.data.cameras.new("camera")
    cam_data.lens = 90
    cam_data.clip_start, cam_data.clip_end = 1, 5000
    cam = bpy.data.objects.new("camera", cam_data)
    cam.location = (0, -105, 165)
    bpy.context.collection.objects.link(cam)
    look_at(cam, target)
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
    return scene, mats, label


def contact_sheet(paths, out_path, cols=3):
    tiles = []
    for p in paths:
        img = bpy.data.images.load(p)
        w, h = img.size
        tiles.append(np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4))
    h, w = tiles[0].shape[:2]
    rows = math.ceil(len(tiles) / cols)
    sheet = np.ones((rows * h, cols * w, 4), dtype=np.float32)
    for i, tile in enumerate(tiles):
        r, c = divmod(i, cols)
        y0 = (rows - 1 - r) * h  # image rows run bottom-up
        sheet[y0 : y0 + h, c * w : (c + 1) * w] = tile
    out = bpy.data.images.new("sheet", cols * w, rows * h)
    out.pixels = sheet.ravel()
    out.filepath_raw = out_path
    out.file_format = "PNG"
    out.save()


def main():
    samples, size, names = args()
    scene, mats, label = build_scene(samples, size)
    out_dir = os.path.join(ROOT, "renders")
    os.makedirs(out_dir, exist_ok=True)
    paths = []
    for name in names:
        title, color, rough, bezel_rough, strap = VARIANTS[name]
        set_color(mats["case"], color, rough)
        set_color(mats["bezel"], color, bezel_rough)
        set_color(mats["strap"], strap, 0.62)
        label.data.body = title.replace("  ", "\n", 1)
        scene.render.filepath = os.path.join(out_dir, f"sc01-{name}.png")
        bpy.ops.render.render(write_still=True)
        paths.append(scene.render.filepath)
    if len(paths) > 1:
        contact_sheet(paths, os.path.join(out_dir, "sc01-all-finishes.png"))


main()
