extends RefCounted

## Builds the rock surface of an asteroid's cracks as one smooth mesh, from the
## same shape the drone collides with (DroneMazeModel.crack_probe), so what
## the captain sees is where the drone scrapes.
##
## The cave is a signed distance field: negative inside the cracks, positive
## in the rock. Noise only ever pushes the rock outward, never into the space
## the drone may use, so the camera cannot end up inside a lump. The surface
## is extracted with naive surface nets (one vertex per cell the surface
## crosses, one quad per crossed grid edge), which gives smooth, organic walls
## with shared vertices and smooth normals.
##
## PURE and thread-safe: no scene access. Call from a worker thread.

const Maze := preload("res://scripts/story/activities/DroneMazeModel.gd")

## Grid spacing in tiles. Finer is smoother and slower.
const CELL := 0.14
## Cracks are taller than they are wide.
const TALL := 1.6
## How far the noise may push the rock outward.
const LUMPS := 0.1
const ROCK := 1.0


## {"vertices": PackedVector3Array, "normals": PackedVector3Array,
##  "indices": PackedInt32Array}. Normals face into the cave.
static func build(cracks: Dictionary, seed_value: int) -> Dictionary:
	var nodes: Dictionary = cracks["nodes"]
	var segs := _segments(cracks)
	var buckets := _buckets(segs)
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 1.4
	noise.fractal_octaves = 3
	# Bounds: every chamber, padded by the widest crack.
	var lo := Vector3(INF, 0.0, INF)
	var hi := Vector3(-INF, 0.0, -INF)
	var widest := 0.0
	for key in nodes:
		var n: Array = nodes[key]
		lo.x = minf(lo.x, float(n[0]))
		lo.z = minf(lo.z, float(n[1]))
		hi.x = maxf(hi.x, float(n[0]))
		hi.z = maxf(hi.z, float(n[1]))
		widest = maxf(widest, float(n[2]))
	var pad := widest + LUMPS + CELL * 2.0
	lo -= Vector3(pad, 0.0, pad)
	hi += Vector3(pad, 0.0, pad)
	lo.y = -(widest + LUMPS) * TALL - CELL * 2.0
	hi.y = -lo.y
	var nx := int(ceil((hi.x - lo.x) / CELL))
	var ny := int(ceil((hi.y - lo.y) / CELL))
	var nz := int(ceil((hi.z - lo.z) / CELL))

	# Field samples.
	var sx := nx + 1
	var sy := ny + 1
	var field := PackedFloat32Array()
	field.resize(sx * sy * (nz + 1))
	for k in nz + 1:
		for j in sy:
			for i in sx:
				var p := lo + Vector3(i, j, k) * CELL
				field[(k * sy + j) * sx + i] = _sdf(p, segs, buckets, noise)

	# One vertex per cell the surface crosses.
	var cell_vertex := PackedInt32Array()
	cell_vertex.resize(nx * ny * nz)
	cell_vertex.fill(-1)
	var verts := PackedVector3Array()
	var corner := [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(1, 1, 0),
		Vector3i(0, 0, 1), Vector3i(1, 0, 1), Vector3i(0, 1, 1), Vector3i(1, 1, 1)]
	var cube_edges := [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]]
	for k in nz:
		for j in ny:
			for i in nx:
				var vals := PackedFloat32Array()
				vals.resize(8)
				var inside := 0
				for c in 8:
					var o: Vector3i = corner[c]
					vals[c] = field[((k + o.z) * sy + (j + o.y)) * sx + (i + o.x)]
					if vals[c] < 0.0:
						inside += 1
				if inside == 0 or inside == 8:
					continue
				var sum := Vector3.ZERO
				var count := 0
				for e in cube_edges:
					var a: float = vals[e[0]]
					var b: float = vals[e[1]]
					if (a < 0.0) == (b < 0.0):
						continue
					var t := a / (a - b)
					var pa := Vector3(corner[e[0]])
					var pb := Vector3(corner[e[1]])
					sum += pa.lerp(pb, t)
					count += 1
				cell_vertex[(k * ny + j) * nx + i] = verts.size()
				verts.append(lo + (Vector3(i, j, k) + sum / count) * CELL)

	# One quad per grid edge the surface crosses, joining the four cells
	# around that edge. Winding faces the quad into the cave.
	var indices := PackedInt32Array()
	for k in range(1, nz):
		for j in range(1, ny):
			for i in nx:
				_quad(field, cell_vertex, verts, indices, sx, sy, nx, ny,
					Vector3i(i, j, k), Vector3i(1, 0, 0),
					[Vector3i(i, j - 1, k - 1), Vector3i(i, j, k - 1), Vector3i(i, j, k), Vector3i(i, j - 1, k)])
	for k in range(1, nz):
		for j in ny:
			for i in range(1, nx):
				_quad(field, cell_vertex, verts, indices, sx, sy, nx, ny,
					Vector3i(i, j, k), Vector3i(0, 1, 0),
					[Vector3i(i - 1, j, k - 1), Vector3i(i - 1, j, k), Vector3i(i, j, k), Vector3i(i, j, k - 1)])
	for k in nz:
		for j in range(1, ny):
			for i in range(1, nx):
				_quad(field, cell_vertex, verts, indices, sx, sy, nx, ny,
					Vector3i(i, j, k), Vector3i(0, 0, 1),
					[Vector3i(i - 1, j - 1, k), Vector3i(i - 1, j, k), Vector3i(i, j, k), Vector3i(i, j - 1, k)])

	# Smooth normals: area-weighted face normals, accumulated per vertex.
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	for f in range(0, indices.size(), 3):
		var a := verts[indices[f]]
		var b := verts[indices[f + 1]]
		var c := verts[indices[f + 2]]
		var n := (b - a).cross(c - a)
		normals[indices[f]] += n
		normals[indices[f + 1]] += n
		normals[indices[f + 2]] += n
	for v in normals.size():
		normals[v] = normals[v].normalized()
	# Godot draws clockwise triangles as front faces: flip the winding so the
	# side facing into the cave is the one drawn (normals already face in).
	for f in range(0, indices.size(), 3):
		var keep := indices[f + 1]
		indices[f + 1] = indices[f + 2]
		indices[f + 2] = keep
	return {"vertices": verts, "normals": normals, "indices": indices}


static func to_mesh(built: Dictionary) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = built["vertices"]
	arrays[Mesh.ARRAY_NORMAL] = built["normals"]
	arrays[Mesh.ARRAY_INDEX] = built["indices"]
	var mesh := ArrayMesh.new()
	if (built["indices"] as PackedInt32Array).size() > 0:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _quad(field: PackedFloat32Array, cell_vertex: PackedInt32Array, verts: PackedVector3Array, indices: PackedInt32Array,
		sx: int, sy: int, nx: int, ny: int, p: Vector3i, axis: Vector3i, cells: Array) -> void:
	var a := field[(p.z * sy + p.y) * sx + p.x]
	var q := p + axis
	var b := field[(q.z * sy + q.y) * sx + q.x]
	if (a < 0.0) == (b < 0.0):
		return
	var ids := PackedInt32Array()
	for c: Vector3i in cells:
		var id := cell_vertex[(c.z * ny + c.y) * nx + c.x]
		if id < 0:
			return
		ids.append(id)
	# Face the quad toward the cave end of the crossed edge.
	var toward_cave := -Vector3(axis) if a < 0.0 else Vector3(axis)
	# The diagonals' cross product is robust on bent (non-planar) quads.
	var n := (verts[ids[2]] - verts[ids[0]]).cross(verts[ids[3]] - verts[ids[1]])
	if n.dot(toward_cave) >= 0.0:
		indices.append_array(PackedInt32Array([ids[0], ids[1], ids[2], ids[0], ids[2], ids[3]]))
	else:
		indices.append_array(PackedInt32Array([ids[0], ids[2], ids[1], ids[0], ids[3], ids[2]]))


## Signed distance: negative in the cracks. Vertical distance counts less
## (the cracks are TALL), and noise only widens the cave.
static func _sdf(p: Vector3, segs: Array, buckets: Dictionary, noise: FastNoiseLite) -> float:
	var key := Vector2i(int(floor(p.x)), int(floor(p.z)))
	if not buckets.has(key):
		return ROCK
	var flat := Vector3(p.x, p.y / TALL, p.z)
	var best := ROCK
	for s_index: int in buckets[key]:
		var s: Array = segs[s_index]
		var a: Vector3 = s[0]
		var ab: Vector3 = s[1]
		var t := clampf((flat - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var r := Maze._edge_radius(float(s[2]), float(s[3]), float(s[4]), t)
		best = minf(best, flat.distance_to(a + ab * t) - r)
	if best < LUMPS + CELL and best > -CELL * 2.0:
		best -= (noise.get_noise_3dv(p) * 0.5 + 0.5) * LUMPS
	return best


## [start, start->end, r_start, r_end, pinch] per crack.
static func _segments(cracks: Dictionary) -> Array:
	var out: Array = []
	var nodes: Dictionary = cracks["nodes"]
	for e in cracks["edges"]:
		var a: Array = nodes[e[0]]
		var b: Array = nodes[e[1]]
		var pa := Vector3(float(a[0]), 0.0, float(a[1]))
		var pb := Vector3(float(b[0]), 0.0, float(b[1]))
		out.append([pa, pb - pa, float(a[2]), float(b[2]), float(e[2])])
	return out


## Unit-tile buckets of the segments that can reach them.
static func _buckets(segs: Array) -> Dictionary:
	var out := {}
	for i in segs.size():
		var s: Array = segs[i]
		var a: Vector3 = s[0]
		var b: Vector3 = a + (s[1] as Vector3)
		var reach := maxf(float(s[2]), float(s[3])) + LUMPS + CELL * 2.0
		for z in range(int(floor(minf(a.z, b.z) - reach)), int(floor(maxf(a.z, b.z) + reach)) + 1):
			for x in range(int(floor(minf(a.x, b.x) - reach)), int(floor(maxf(a.x, b.x) + reach)) + 1):
				var key := Vector2i(x, z)
				if not out.has(key):
					out[key] = []
				(out[key] as Array).append(i)
	return out
