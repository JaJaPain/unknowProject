"""
Generate pre-shattered solid asteroid fragment GLBs using Blender's Cell Fracture.

Run with:
    "C:\Program Files\Blender Foundation\Blender 5.1\blender.exe" --background --python tools/generate_asteroid_fragments.py
"""

import json
import os
import bpy
import addon_utils

ROOT_DIR = os.path.dirname(os.path.dirname(__file__))
ASTEROID_DIR = os.path.join(ROOT_DIR, "assets", "asteroids")
MODELS_JSON = os.path.join(ASTEROID_DIR, "asteroid_models.json")
TARGET_SHARDS = 25


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for collection in (
        bpy.data.meshes,
        bpy.data.materials,
        bpy.data.textures,
        bpy.data.images,
        bpy.data.cameras,
        bpy.data.lights,
    ):
        for block in list(collection):
            collection.remove(block)


def import_mesh(filepath):
    clear_scene()
    bpy.ops.import_scene.gltf(filepath=filepath)
    mesh_objects = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    if not mesh_objects:
        raise RuntimeError(f"No mesh found in {filepath}")
    if len(mesh_objects) == 1:
        obj = mesh_objects[0]
    else:
        bpy.ops.object.select_all(action="DESELECT")
        for obj in mesh_objects:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = mesh_objects[0]
        bpy.ops.object.join()
        obj = bpy.context.view_layer.objects.active
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return obj


def export_fragments(source_path, output_path, model_index):
    # Ensure cell fracture extension is enabled (using Blender 4.2+ extension namespace)
    try:
        bpy.ops.preferences.addon_enable(module="bl_ext.blender_org.cell_fracture")
    except Exception as e:
        # Fallback to legacy namespace if needed
        try:
            bpy.ops.preferences.addon_enable(module="object_fracture_cell")
        except Exception as e2:
            print(f"Failed to enable cell fracture: {e2}")

    # Import the source mesh
    orig_obj = import_mesh(source_path)
    orig_name = orig_obj.name
    orig_mesh = orig_obj.data

    # Perform Cell Fracture
    bpy.ops.object.add_fracture_cell_objects(
        source={'VERT_OWN'},
        source_limit=TARGET_SHARDS,
        use_recenter=True,
        use_remove_original=True,
        margin=0.0
    )

    # Clean up original object if it remains in scene
    if orig_name in bpy.context.scene.objects:
        bpy.data.objects.remove(bpy.context.scene.objects[orig_name], do_unlink=True)
    if orig_mesh.name in bpy.data.meshes:
        bpy.data.meshes.remove(orig_mesh)

    cells = [o for o in bpy.context.scene.objects if o.type == "MESH"]

    # Filter out empty/invalid cells
    for o in list(cells):
        if len(o.data.vertices) == 0 or len(o.data.polygons) == 0:
            mesh_data = o.data
            bpy.data.objects.remove(o, do_unlink=True)
            bpy.data.meshes.remove(mesh_data)

    cells = [o for o in bpy.context.scene.objects if o.type == "MESH"]

    # Adjust count to exactly TARGET_SHARDS
    if len(cells) > TARGET_SHARDS:
        while len(cells) > TARGET_SHARDS:
            # Sort by face count (smallest first) and merge smallest two
            cells.sort(key=lambda o: len(o.data.polygons))
            c1 = cells[0]
            c2 = cells[1]
            
            bpy.ops.object.select_all(action='DESELECT')
            c1.select_set(True)
            c2.select_set(True)
            bpy.context.view_layer.objects.active = c2
            bpy.ops.object.join()
            
            cells = [o for o in bpy.context.scene.objects if o.type == "MESH"]
            
    elif len(cells) < TARGET_SHARDS and len(cells) > 0:
        while len(cells) < TARGET_SHARDS:
            # Sort by face count (largest first) and split the largest
            cells.sort(key=lambda o: len(o.data.polygons), reverse=True)
            target = cells[0]
            target_name = target.name
            target_mesh = target.data
            
            bpy.ops.object.select_all(action='DESELECT')
            target.select_set(True)
            bpy.context.view_layer.objects.active = target
            
            needed = TARGET_SHARDS - len(cells) + 1
            
            bpy.ops.object.add_fracture_cell_objects(
                source={'VERT_OWN'},
                source_limit=needed,
                use_recenter=True,
                use_remove_original=True,
                margin=0.0
            )
            
            if target_name in bpy.context.scene.objects:
                bpy.data.objects.remove(bpy.context.scene.objects[target_name], do_unlink=True)
            if target_mesh.name in bpy.data.meshes:
                bpy.data.meshes.remove(target_mesh)
                
            cells = [o for o in bpy.context.scene.objects if o.type == "MESH"]

    # Individually UV unwrap each shard and scale to bounds
    for shard in cells:
        bpy.ops.object.select_all(action='DESELECT')
        shard.select_set(True)
        bpy.context.view_layer.objects.active = shard
        
        # Enter Edit Mode
        bpy.ops.object.mode_set(mode='EDIT')
        # Select all geometry in Edit Mode
        bpy.ops.mesh.select_all(action='SELECT')
        # Smart UV Project with scale_to_bounds=True
        bpy.ops.uv.smart_project(
            angle_limit=1.15192,  # ~66 degrees in radians
            island_margin=0.0,
            correct_aspect=True,
            scale_to_bounds=True
        )
        # Return to Object Mode
        bpy.ops.object.mode_set(mode='OBJECT')

    # Sort, rename and apply smooth shading to shards
    cells.sort(key=lambda o: o.location.length)
    for index, shard in enumerate(cells):
        shard.name = f"Shard_{index:03d}"
        shard.data.name = f"Shard_{index:03d}_mesh"
        bpy.context.view_layer.objects.active = shard
        shard.select_set(True)
        bpy.ops.object.shade_smooth()
        shard.select_set(False)

    # Export shards
    bpy.ops.object.select_all(action="DESELECT")
    for shard in cells:
        shard.select_set(True)
    if cells:
        bpy.context.view_layer.objects.active = cells[0]

    bpy.ops.export_scene.gltf(
        filepath=output_path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
    )

    return len(cells), sum(len(shard.data.polygons) for shard in cells)


def main():
    # Enable online access in case Blender preferences restrict it, and update sync
    bpy.context.preferences.system.use_online_access = True
    try:
        bpy.ops.extensions.repo_sync_all()
    except Exception as e:
        print(f"Skipping repository sync: {e}")

    with open(MODELS_JSON, "r", encoding="utf-8") as file:
        data = json.load(file)

    for index, entry in enumerate(data.get("models", [])):
        source_file = entry["file"]
        fragment_file = source_file.replace(".glb", "_fragments.glb")
        source_path = os.path.join(ASTEROID_DIR, source_file)
        output_path = os.path.join(ASTEROID_DIR, fragment_file)
        
        print(f"Processing {source_file}...")
        shard_count, face_count = export_fragments(source_path, output_path, index)
        entry["fragments_file"] = fragment_file
        entry["fragment_count"] = shard_count
        print(f"{source_file}: exported {shard_count} solid UV-unwrapped shards from {face_count} faces")

    with open(MODELS_JSON, "w", encoding="utf-8") as file:
        json.dump(data, file, indent=2)
        file.write("\n")


if __name__ == "__main__":
    main()
