import sys
import os
import bpy
import argparse

# Parse arguments after '--'
argv = sys.argv
if "--" not in argv:
    argv = []
else:
    argv = argv[argv.index("--") + 1:]

parser = argparse.ArgumentParser()
parser.add_argument("--seed", type=str, default="random_ship", help="Seed for the spaceship generation")
parser.add_argument("--class", dest="ship_class", type=str, default="hauler", help="Ship chassis class (hauler/fighter)")
parser.add_argument("--texture", type=str, default="metal.png", help="Base metal texture filename")
parser.add_argument("--emblem", type=str, default="none", help="Faction emblem filename")
parser.add_argument("--normal", type=str, default="hull_normal.png", help="Hull normal map filename")
parser.add_argument("--metallic", type=float, default=0.85, help="Metallic level for the hull material")
parser.add_argument("--output", type=str, default="", help="Output .glb file path (overrides default)")
args = parser.parse_args(argv)

# Add current dir to path to import spaceship_generator
current_dir = os.path.dirname(os.path.abspath(__file__))
sys.path.append(current_dir)
import spaceship_generator

seed_str = args.seed
ship_class_str = args.ship_class
texture_str = args.texture
emblem_str = args.emblem
normal_str = args.normal
metallic_val = args.metallic
print(f"Generating single {ship_class_str} spaceship with seed: {seed_str}, texture: {texture_str}, emblem: {emblem_str}, normal: {normal_str}, metallic: {metallic_val}...")

spaceship_generator.reset_scene()
obj = spaceship_generator.generate_spaceship(random_seed=seed_str, ship_class=ship_class_str, texture_file=texture_str, emblem_file=emblem_str, normal_file=normal_str, metallic=metallic_val)

# Validate that the ship has both engine and weapon hardpoints
engines = [c for c in obj.children if c.name.startswith("Engine_")]
weapons = [c for c in obj.children if c.name.startswith("Weapon_")]
if not engines or not weapons:
    missing = []
    if not engines:
        missing.append("thrusters")
    if not weapons:
        missing.append("hardpoints")
    print(f"REJECTED: ship '{seed_str}' missing {' and '.join(missing)} (engines={len(engines)}, weapons={len(weapons)})")
    sys.exit(1)

print(f"Validated: {len(engines)} thruster(s), {len(weapons)} hardpoint(s)")

# Select the spaceship and all its child nodes (engines/weapons)
bpy.ops.object.select_all(action='DESELECT')
obj.select_set(True)
for child in obj.children:
    child.select_set(True)
bpy.context.view_layer.objects.active = obj

# Generate UV map for non-decal faces
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='DESELECT')
bpy.ops.object.mode_set(mode='OBJECT')

for poly in obj.data.polygons:
    if poly.material_index != 5: # 5 is Material.decal
        poly.select = True

bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.uv.cube_project(cube_size=1.0)
bpy.ops.object.mode_set(mode='OBJECT')

# Determine output path
if args.output:
    gltf_path = args.output
else:
    models_dir = os.path.join(current_dir, "models")
    os.makedirs(models_dir, exist_ok=True)
    gltf_path = os.path.join(models_dir, f"{seed_str}.glb")

os.makedirs(os.path.dirname(os.path.abspath(gltf_path)), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=gltf_path, use_selection=True)

print(f"Exported to {gltf_path}")
