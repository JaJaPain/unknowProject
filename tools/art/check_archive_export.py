"""Inspect the actual binary glTF deliverable, independently of Blender."""
import json, struct
from pathlib import Path
root=Path(__file__).resolve().parents[2]
path=root/'assets/landmarks/archive.glb'
blob=path.read_bytes()
magic,version,length=struct.unpack_from('<4sII',blob)
assert magic==b'glTF' and version==2 and length==len(blob)
size,kind=struct.unpack_from('<II',blob,12)
assert kind==0x4E4F534A
doc=json.loads(blob[20:20+size])
accessors=doc['accessors']
meshes=doc['meshes']
primitives=[p for m in meshes for p in m['primitives']]
triangles=sum(accessors[p['indices']]['count']//3 for p in primitives)
emission=[m['name'] for m in doc['materials'] if any(m.get('emissiveFactor',[0,0,0]))]
names=[n.get('name','') for n in doc['nodes']]
assert len(meshes)<50 and len(doc['materials'])<=8
assert len(primitives)==len(meshes)
assert all(p.get('mode',4)==4 for p in primitives)
assert len(emission)==3
assert not doc.get('cameras') and 'KHR_lights_punctual' not in doc.get('extensions',{})
assert all(label in names for label in ['Archive','Envelope01_Pivot','Envelope02_Pivot','Envelope03_Pivot'])
assert len(doc['scenes'])==1
assert not doc.get('images')
counts=json.loads((root/'art/archive/counts.json').read_text())
assert triangles==counts['triangles']
report={'valid':True,'bytes':len(blob),'meshes':len(meshes),'surfaces':len(primitives),
        'triangles':triangles,'materials':len(doc['materials']),'emissive_materials':emission,
        'scenes':len(doc['scenes']),'cameras':0,'lights':0,'external_textures':0}
(root/'art/archive/validation_glb.json').write_text(json.dumps(report,indent=2))
print(json.dumps(report))
