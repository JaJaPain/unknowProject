"""
Blender headless script to generate 20 asteroid rock models.
Run with: blender --background --python generate_asteroids.py

Uses icospheres with multiple displacement modifiers and noise textures
to create varied organic rock shapes. Exports as .glb for Godot import.
"""

import bpy
import bmesh
import json
import os
import random
import math

OUTPUT_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "assets", "asteroids")
NUM_ROCKS = 20
TARGET_RADIUS = 5.0
SEED = 42

random.seed(SEED)
os.makedirs(OUTPUT_DIR, exist_ok=True)


def clear_scene():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for block in list(bpy.data.meshes):
        bpy.data.meshes.remove(block)
    for block in list(bpy.data.textures):
        bpy.data.textures.remove(block)
    for block in list(bpy.data.cameras):
        bpy.data.cameras.remove(block)
    for block in list(bpy.data.lights):
        bpy.data.lights.remove(block)
    for block in list(bpy.data.materials):
        bpy.data.materials.remove(block)


def create_rock(index, seed_val):
    subdivisions = random.choice([3, 4, 4, 5])
    bpy.ops.mesh.primitive_ico_sphere_add(
        subdivisions=subdivisions,
        radius=1.0,
        location=(0, 0, 0),
    )
    rock = bpy.context.active_object
    rock.name = f"asteroid_{index:02d}"

    sx = random.uniform(0.7, 1.6)
    sy = random.uniform(0.7, 1.6)
    sz = random.uniform(0.5, 1.4)
    rock.scale = (sx, sy, sz)
    bpy.ops.object.transform_apply(scale=True)

    rng = random.Random(seed_val)

    # Large-scale deformation
    tex_large = bpy.data.textures.new(f"disp_large_{index}", type='CLOUDS')
    tex_large.noise_scale = rng.uniform(0.8, 1.8)
    tex_large.noise_depth = rng.randint(2, 5)
    tex_large.noise_type = 'SOFT_NOISE'

    mod_large = rock.modifiers.new(name="Disp_Large", type='DISPLACE')
    mod_large.texture = tex_large
    mod_large.strength = rng.uniform(0.25, 0.55)
    mod_large.mid_level = 0.5
    mod_large.texture_coords = 'GLOBAL'

    # Medium detail
    tex_med = bpy.data.textures.new(f"disp_med_{index}", type='VORONOI')
    tex_med.noise_scale = rng.uniform(0.4, 0.9)
    tex_med.noise_intensity = rng.uniform(0.8, 1.2)

    mod_med = rock.modifiers.new(name="Disp_Med", type='DISPLACE')
    mod_med.texture = tex_med
    mod_med.strength = rng.uniform(0.1, 0.3)
    mod_med.mid_level = 0.5
    mod_med.texture_coords = 'GLOBAL'

    # Fine surface roughness
    tex_fine = bpy.data.textures.new(f"disp_fine_{index}", type='MUSGRAVE')
    tex_fine.noise_scale = rng.uniform(0.15, 0.4)

    mod_fine = rock.modifiers.new(name="Disp_Fine", type='DISPLACE')
    mod_fine.texture = tex_fine
    mod_fine.strength = rng.uniform(0.05, 0.15)
    mod_fine.mid_level = 0.5
    mod_fine.texture_coords = 'GLOBAL'

    # Apply all modifiers
    bpy.context.view_layer.objects.active = rock
    for mod in list(rock.modifiers):
        bpy.ops.object.modifier_apply(modifier=mod.name)

    # Normalize to target radius
    bpy.ops.object.origin_set(type='ORIGIN_CENTER_OF_VOLUME')
    rock.location = (0, 0, 0)

    mesh = rock.data
    max_dist = 0.0
    for vert in mesh.vertices:
        dist = vert.co.length
        if dist > max_dist:
            max_dist = dist

    if max_dist > 0:
        scale_factor = TARGET_RADIUS / max_dist
        rock.scale = (scale_factor, scale_factor, scale_factor)
        bpy.ops.object.transform_apply(scale=True)

    # Smooth shading
    bpy.ops.object.shade_smooth()

    # UV unwrap
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=1.15192, island_margin=0.02)
    bpy.ops.object.mode_set(mode='OBJECT')

    return rock


def export_rock(rock, filepath):
    bpy.ops.object.select_all(action='DESELECT')
    rock.select_set(True)
    bpy.context.view_layer.objects.active = rock

    bpy.ops.export_scene.gltf(
        filepath=filepath,
        export_format='GLB',
        use_selection=True,
        export_apply=True,
        export_yup=True,
    )


models = []

for i in range(NUM_ROCKS):
    clear_scene()
    seed_val = SEED + i * 137
    rock = create_rock(i, seed_val)

    filepath = os.path.join(OUTPUT_DIR, f"asteroid_{i:02d}.glb")
    export_rock(rock, filepath)

    tex_row = random.randint(0, 2)
    tex_col = random.randint(0, 2)

    models.append({
        "file": f"asteroid_{i:02d}.glb",
        "texture_cell": [tex_col, tex_row],
    })

    print(f"Generated asteroid_{i:02d}.glb (cell [{tex_col},{tex_row}])")

json_path = os.path.join(OUTPUT_DIR, "asteroid_models.json")
with open(json_path, 'w') as f:
    json.dump({"models": models}, f, indent=2)

print(f"\nDone! Generated {NUM_ROCKS} asteroid models in {OUTPUT_DIR}")
