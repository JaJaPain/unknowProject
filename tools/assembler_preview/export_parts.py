"""One-time Blender export: each kitbash part -> origin-centered GLB + manifest.

Run: blender --background --python export_parts.py -- <Shipyard.blend> <out_dir> <manifest.json>

Convention: Blender +Y is treated as ship FORWARD. glTF yup export maps
Blender (x,y,z) -> Godot (x, z, -y), so +Y(forward) -> -Z(Godot forward).
Manifest stores each part's Godot-space AABB so the GDScript assembler can
snap parts edge-to-edge without loading meshes first.
"""
import bpy, os, sys, json

argv = sys.argv[sys.argv.index("--")+1:]
blend, out_dir, manifest_path = argv[0], argv[1], argv[2]

bpy.ops.wm.open_mainfile(filepath=blend)

CATEGORY_BY_COLLECTION = {
    "Collection 2": "hulls",
    "Collection 4": "engines",
    "Collection 5": "weapons",
    "Collection 3": "greebles",
    "Collection 6": "detail",
}
PRIORITY = ["hulls", "engines", "weapons", "greebles", "detail"]

# Map object name -> chosen category (highest priority collection it is in)
obj_category = {}
for col in bpy.data.collections:
    cat = CATEGORY_BY_COLLECTION.get(col.name)
    if not cat:
        continue
    for o in col.objects:
        if o.type != 'MESH':
            continue
        prev = obj_category.get(o.name)
        if prev is None or PRIORITY.index(cat) < PRIORITY.index(prev):
            obj_category[o.name] = cat

scene = bpy.context.scene

def safe_filename(name):
    return name.replace(" ", "_").replace("/", "_")

for cat in PRIORITY:
    os.makedirs(os.path.join(out_dir, cat), exist_ok=True)

manifest = {}
errors = []

names = sorted(obj_category.keys())
for name in names:
    cat = obj_category[name]
    obj = bpy.data.objects.get(name)
    if obj is None:
        continue
    # Objects live in view-layer-excluded collections -> visible_get() False,
    # which makes use_selection export skip them. Link into the active scene
    # collection and force visible first (mirrors proven single-object flow).
    try:
        scene.collection.objects.link(obj)
    except RuntimeError:
        pass
    try:
        obj.hide_set(False)
    except RuntimeError:
        pass
    obj.hide_viewport = False
    obj.hide_render = False
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action='DESELECT')
    try:
        obj.select_set(True)
    except RuntimeError as e:
        errors.append((name, f"select: {e}"))
        continue
    bpy.context.view_layer.objects.active = obj

    # Bake modifiers + rotation/scale into the mesh
    try:
        bpy.ops.object.convert(target='MESH')
    except RuntimeError:
        pass
    obj = bpy.context.view_layer.objects.active
    try:
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    except RuntimeError:
        pass
    # Origin -> geometric bounds center, then move to world origin
    try:
        bpy.ops.object.origin_set(type='ORIGIN_GEOMETRY', center='BOUNDS')
    except RuntimeError:
        pass
    obj.location = (0.0, 0.0, 0.0)
    bpy.context.view_layer.update()

    # Local bbox (now identity transform, centered) -> Godot space
    bb = [tuple(v) for v in obj.bound_box]
    xs = [p[0] for p in bb]; ys = [p[1] for p in bb]; zs = [p[2] for p in bb]
    bx = (min(xs), max(xs)); by = (min(ys), max(ys)); bz = (min(zs), max(zs))
    # Godot: gx=bx, gy=bz, gz=-by  (so by.max(forward) -> gz.min)
    gmin = [bx[0], bz[0], -by[1]]
    gmax = [bx[1], bz[1], -by[0]]

    fname = safe_filename(name) + ".glb"
    rel = f"{cat}/{fname}"
    out_path = os.path.join(out_dir, rel)

    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    try:
        bpy.ops.export_scene.gltf(
            filepath=out_path, use_selection=True,
            export_yup=True,
            export_materials='NONE',
        )
    except Exception as e:
        errors.append((name, f"export: {e}"))
        continue

    manifest.setdefault(cat, []).append({
        "name": name,
        "file": rel,
        "aabb_min": [round(v, 4) for v in gmin],
        "aabb_max": [round(v, 4) for v in gmax],
        "size": [round(gmax[i]-gmin[i], 4) for i in range(3)],
        "verts": len(obj.data.vertices),
    })

with open(manifest_path, "w") as f:
    json.dump(manifest, f, indent=1)

print("=== EXPORT SUMMARY ===")
for cat in PRIORITY:
    print(f"  {cat}: {len(manifest.get(cat, []))} parts")
if errors:
    print("ERRORS:")
    for n, e in errors[:30]:
        print("  ", n, e)
print("WROTE", manifest_path)
