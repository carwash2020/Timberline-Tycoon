"""Render one GLB per tile, headless, for registry contact sheets.

    blender -b --factory-startup -P tools/blender/render_tiles.py -- <out dir> <size> <a.glb> [b.glb ...]

Each GLB is imported as exported (vertex colours carry the look), its
Collision and HumanoidRootPart nodes hidden (invisible in game), and shot from a 3/4 view about
28 degrees up on a light ground, framed to its bounds. Writes
<out dir>/<group>__<Name>.png (or <Name>__<piece>.png for multi-file trees).
"""

import math
import os
import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1 :]
out_dir, size, files = argv[0], int(argv[1]), argv[2:]
os.makedirs(out_dir, exist_ok=True)


def clear():
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.cameras, bpy.data.lights, bpy.data.images):
        for item in list(coll):
            if item.users == 0:
                coll.remove(item)


def setup_scene():
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    try:
        scene.eevee.taa_render_samples = 24
    except Exception:
        pass
    scene.view_settings.view_transform = "Standard"
    scene.render.resolution_x = size
    scene.render.resolution_y = size
    world = bpy.data.worlds.get("World") or bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (0.78, 0.84, 0.9, 1)
    bg.inputs["Strength"].default_value = 1.0
    return scene


scene = setup_scene()
for path in files:
    clear()
    bpy.ops.import_scene.gltf(filepath=path)
    meshes = [o for o in scene.objects if o.type == "MESH"]
    for o in meshes:
        if o.name.split(".")[0] in ("Collision", "HumanoidRootPart"):
            o.hide_render = True
    visible = [o for o in meshes if not o.hide_render]
    bpy.context.view_layer.update()
    pts = [o.matrix_world @ Vector(c) for o in visible for c in o.bound_box]
    if not pts:
        continue
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    center = (lo + hi) / 2
    span = max((hi - lo).length, 0.5)
    ground_mat = bpy.data.materials.new("ground")
    ground_mat.use_nodes = True
    ground_mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.62, 0.6, 0.56, 1)
    bpy.ops.mesh.primitive_plane_add(size=span * 6, location=(center.x, center.y, lo.z - 0.002))
    bpy.context.object.data.materials.append(ground_mat)
    # Roblox front is -Z, which glTF/Blender import puts at +Y in Blender. View from the front-right.
    yaw, pitch = math.radians(35), math.radians(28)
    fwd = Vector((math.sin(yaw) * math.cos(pitch), math.cos(yaw) * math.cos(pitch), math.sin(pitch)))
    cam_d = bpy.data.cameras.new("cam")
    cam_d.lens = 50
    cam = bpy.data.objects.new("cam", cam_d)
    scene.collection.objects.link(cam)
    cam.rotation_euler = (-fwd).to_track_quat("-Z", "Y").to_euler()
    fov = 2 * math.atan(18 / cam_d.lens)
    dist = (span / 2) / math.tan(fov / 2) * 1.08
    cam.location = center + fwd * dist
    cam_d.clip_end = dist * 10
    cam_d.clip_start = max(0.01, dist / 1000)
    scene.camera = cam
    sun_d = bpy.data.lights.new("sun", "SUN")
    sun_d.energy = 3.0
    sun = bpy.data.objects.new("sun", sun_d)
    sun.rotation_euler = (math.radians(45), math.radians(10), math.radians(140))
    scene.collection.objects.link(sun)
    parts = os.path.normpath(path).split(os.sep)
    name = f"{parts[-3]}__{parts[-2]}" if parts[-1][:-4] == parts[-2] else f"{parts[-2]}__{parts[-1][:-4]}"
    scene.render.filepath = os.path.join(out_dir, name + ".png")
    bpy.ops.render.render(write_still=True)
