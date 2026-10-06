"""Run in Blender after building the derelict; preserve Brief 7's ray checks."""
import bpy
import json
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree

out = Path('D:/CodingProjects/spacegame/art/lone_derelict')
scene = bpy.data.scenes['A Lone Derelict Ship']
asset = next(c for c in scene.collection.children if c.name.startswith('Lone Derelict | Export'))
vertices, faces = [], []
for obj in asset.objects:
    if obj.type != 'MESH':
        continue
    offset = len(vertices)
    vertices.extend(obj.matrix_world @ v.co for v in obj.data.vertices)
    faces.extend(tuple(offset + i for i in face.vertices) for face in obj.data.polygons)
tree = BVHTree.FromPolygons(vertices, faces)
hit = tree.ray_cast(Vector((0, -90, 0)), Vector((0, 1, 0)), 150)
assert hit[3] is not None and hit[3] > 105, hit
samples = 0
for y in [-15, -12, -9]:
    for z in [-9, -6, -3]:
        ray = tree.ray_cast(Vector((-45, y, z)), Vector((1, 0, 0)), 95)
        assert ray[0] is None, (y, z, ray)
        samples += 1
original = json.loads((out / 'original_pivots.json').read_text())
for name, position in original.items():
    obj = asset.objects.get(name)
    assert obj is not None, name
    assert (obj.location - Vector(position)).length < .0001, name
report = {
    'entrance_ray_first_surface_distance_m': hit[3],
    'longitudinal_clearance_samples': samples,
    'sampled_corridor_length_m': 95,
    'sampled_corridor_width_and_height_m': 6,
    'preserved_original_pivots': len(original),
    'note': 'Geometry ray samples, not a full collision or drone simulation',
}
(out / 'breach_clearance.json').write_text(json.dumps(report, indent=2))
print(json.dumps(report))
