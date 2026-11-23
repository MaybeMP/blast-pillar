extends Node3D
## The voxel pillar for one world.
##
## Blocks are stored in flat byte arrays (type + remaining health). Only the part of the pillar
## near the dig is turned into meshes, in chunks CHUNK layers tall.
##
## "cut" is the layer currently drawn as the top of the pillar. As the hole gets deeper the cut
## follows it down (CUT_GAP layers above the hole floor), so the view always looks like a pillar
## with a crater in the top — like the concept drawing.

const Data = preload("res://scripts/data.gd")

const CHUNK := 8
const VIEW_BELOW := 48          # layers drawn below the cut
const CUT_GAP := 6              # layers of crater wall kept above the hole floor

# face order: top, bottom, +x, -x, +z, -z  (dd = depth direction, +1 is down)
const FDX := [0, 0, 1, -1, 0, 0]
const FDD := [-1, 1, 0, 0, 0, 0]
const FDZ := [0, 0, 0, 0, 1, -1]
const FACE_SHADE := [1.0, 0.45, 0.82, 0.68, 0.92, 0.6]
const FACE_CORNERS := [
	[Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(0, 1, 1)],
	[Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 0, 0), Vector3(0, 0, 0)],
	[Vector3(1, 1, 1), Vector3(1, 1, 0), Vector3(1, 0, 0), Vector3(1, 0, 1)],
	[Vector3(0, 1, 0), Vector3(0, 1, 1), Vector3(0, 0, 1), Vector3(0, 0, 0)],
	[Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 0, 1), Vector3(0, 0, 1)],
	[Vector3(1, 1, 0), Vector3(0, 1, 0), Vector3(0, 0, 0), Vector3(1, 0, 0)],
]

var blocks                      # blocks.gd registry
var W := Data.WIDTH
var VS := Data.VOXEL
var H := 120                     # total layers: pillar + bedrock + vault + bedrock floor
var depth := 120                 # layers in the main pillar (bedrock sits at layer `depth`)
var bedrock_idx := 0
var world_index := 0
var types := PackedByteArray()
var hp := PackedByteArray()     # remaining health, 255 = full
var col_top := PackedInt32Array()
var cut := 0
var chunks := {}
var dirty := {}
var coll_dirty := {}              # chunk -> true: collision needs rebuilding (done at most ~8x/sec)
var coll_timer := 0.0
const COLLISION_INTERVAL := 0.12
var walls: StaticBody3D          # invisible walls that keep bombs over the pillar
var material: StandardMaterial3D
var plant_material: StandardMaterial3D
var grass_blocks := {}           # block types that can have plants on top
var hp_table := PackedFloat32Array()
var hp_mult := 1.0               # realms: every block is this much tougher (set per world)
var uv_table: Array[Rect2] = []


func setup(blocks_ref) -> void:
	blocks = blocks_ref
	bedrock_idx = blocks.index_of("bedrock")
	material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = blocks.atlas
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.vertex_color_use_as_albedo = true
	plant_material = StandardMaterial3D.new()
	plant_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	plant_material.albedo_texture = blocks.plant_atlas
	plant_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	plant_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	plant_material.alpha_scissor_threshold = 0.5
	plant_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	plant_material.vertex_color_use_as_albedo = true
	for b in blocks.defs.size():
		if blocks.defs[b]["style"] == "grass" and blocks.defs[b]["ore"] == "" and int(blocks.defs[b]["world"]) == 0:
			grass_blocks[b] = true
	hp_table.resize(blocks.defs.size())
	uv_table.clear()
	for b in blocks.defs.size():
		hp_table[b] = maxf(float(blocks.defs[b]["hp"]), 0.01)
		for side in [false, true]:
			for s in 4:
				uv_table.append(blocks.uv(b, side, s))


# =============================================================================================
# Generation, saving, loading
# =============================================================================================

func generate(widx: int, seed_val: int) -> void:
	world_index = widx
	var world: Dictionary = Data.WORLDS[widx]
	depth = int(world["depth"])
	H = depth + 1 + Data.VAULT_LAYERS + 1
	types.resize(W * W * H)
	types.fill(0)
	hp.resize(W * W * H)
	hp.fill(255)
	cut = 0

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var noise := FastNoiseLite.new()
	noise.seed = seed_val
	noise.frequency = 0.12

	var layers: Array = world["layers"]
	var layer_blocks: Array[int] = []
	for l in layers:
		layer_blocks.append(blocks.index_of("%s_%s" % [world["id"], l["id"]]))

	for d in depth:
		for z in W:
			for x in W:
				var li := 0
				if d > 0:
					var frac := (d + noise.get_noise_3d(x * 1.0, d * 0.6, z * 1.0) * 4.0) / depth
					li = layers.size() - 1
					for k in layers.size():
						if frac < float(layers[k]["to"]):
							li = k
							break
					# a very thin top layer (grass) only ever sits on the very top row
					if li == 0 and float(layers[0]["to"]) < 0.02:
						li = 1
				types[_idx(x, d, z)] = layer_blocks[li]

	_veins(rng, world["ores"], 1, depth - 4, int(W * W * depth * 0.008), 0.0)

	# treasure: exactly 5, just above the bedrock (World 6's treasure is the Cosmic Egg, which is
	# buried all the way down instead - see _bury_eggs)
	var tb: int = blocks.index_of("ore_" + world["treasure"]["id"])
	var placed := 0 if world["treasure"]["id"] != Data.BEDROCK_BOMB_ORE else 5
	while placed < 5:
		var i := _idx(rng.randi_range(3, W - 4), depth - 1 - rng.randi_range(0, 2), rng.randi_range(3, W - 4))
		if types[i] != tb:
			types[i] = tb
			placed += 1

	_bury_eggs(seed_val)

	_gen_below(seed_val)
	_recompute_all_columns()
	_clear_chunks()
	_make_walls()


## Cosmic Eggs: single blocks spread evenly from near the top to a few layers above the bedrock,
## away from the edges, so a normal dig turns them all up. (Own random stream, so the rest of
## the pillar comes out the same as before.)
func _bury_eggs(seed_val: int) -> void:
	var n: int = int(Data.EGGS_PER_WORLD[world_index])
	var eb: int = blocks.index_of("egg_" + Data.WORLDS[world_index]["id"])
	if n <= 0 or eb < 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val * 53 + 11
	var top := 3
	var bottom := depth - 12
	for k in n:
		var d0 := top + (bottom - top) * k / n
		var d1 := maxi(d0, top + (bottom - top) * (k + 1) / n - 1)
		for attempt in 20:
			var i := _idx(rng.randi_range(2, W - 3), rng.randi_range(d0, d1), rng.randi_range(2, W - 3))
			if types[i] != eb:
				types[i] = eb
				break


## Ore veins between layers d_from..d_to. rare_boost > 0 makes rare ores more common (vaults).
func _veins(rng: RandomNumberGenerator, ores: Array, d_from: int, d_to: int, count: int, rare_boost: float) -> void:
	var span := maxf(1.0, float(depth))
	for v in count:
		var d := rng.randi_range(d_from, d_to)
		var frac := clampf(float(d) / span, 0.0, 1.0)
		var total := 0.0
		var weights: Array[float] = []
		for k in ores.size():
			var o: Dictionary = ores[k]
			var w := float(o["w"]) * (1.0 + rare_boost * k) if frac >= float(o["min"]) else 0.0
			weights.append(w)
			total += w
		var pick := rng.randf() * total
		var chosen: Dictionary = ores[0]
		for k in ores.size():
			pick -= weights[k]
			if weights[k] > 0.0 and pick <= 0.0:
				chosen = ores[k]
				break
		var ob: int = blocks.index_of("ore_" + chosen["id"])
		var x := rng.randi_range(0, W - 1)
		var z := rng.randi_range(0, W - 1)
		for st in rng.randi_range(2, 6):
			if x >= 0 and x < W and z >= 0 and z < W and d >= d_from and d <= d_to:
				types[_idx(x, d, z)] = ob
			match rng.randi_range(0, 5):
				0: x += 1
				1: x -= 1
				2: z += 1
				3: z -= 1
				4: d += 1
				5: d -= 1


## Everything under the pillar: a bedrock layer, the vault (tough rock rich in rare ores) with the
## bomb cache at the bottom, and a bedrock floor.
func _gen_below(seed_val: int) -> void:
	var world: Dictionary = Data.WORLDS[world_index]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val * 31 + 7
	var vault: int = blocks.index_of("vault_" + world["id"])
	for z in W:
		for x in W:
			types[_idx(x, depth, z)] = bedrock_idx
			types[_idx(x, H - 1, z)] = bedrock_idx
			for d in range(depth + 1, H - 1):
				types[_idx(x, d, z)] = vault
	for i in range(W * W * depth, W * W * H):
		hp[i] = 255
	_veins(rng, world["ores"], depth + 1, H - 3, int(W * W * Data.VAULT_LAYERS * 0.02), 0.8)
	_place_cache()


## The crate at the bottom of the vault: a bomb (Worlds 1-6), a relic (7-11) or the Star Core (12).
func _place_cache() -> void:
	var cache: int = blocks.index_of("cache_" + Data.WORLDS[world_index]["id"])
	for z in range(W / 2 - 1, W / 2 + 1):
		for x in range(W / 2 - 1, W / 2 + 1):
			types[_idx(x, H - 2, z)] = cache
			hp[_idx(x, H - 2, z)] = 255


## Four invisible walls hugging the pillar, from its bottom to high above the top,
## so bombs bounce back instead of falling off the sides.
func _make_walls() -> void:
	if walls:
		walls.queue_free()
	walls = StaticBody3D.new()
	walls.collision_layer = 1
	walls.collision_mask = 0
	var mat := PhysicsMaterial.new()
	mat.bounce = 0.2
	mat.friction = 0.2
	walls.physics_material_override = mat
	add_child(walls)
	var half := W * 0.5 * VS
	var thick := 1.0
	var top := 40.0
	var bottom := -H * VS
	var height := top - bottom
	var mid_y := (top + bottom) * 0.5
	var span := W * VS + thick * 2.0
	for side in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		if side.x != 0.0:
			box.size = Vector3(thick, height, span)
		else:
			box.size = Vector3(span, height, thick)
		cs.shape = box
		cs.position = side * (half + thick * 0.5) + Vector3(0, mid_y, 0)
		walls.add_child(cs)


func get_state() -> Dictionary:
	return {
		"types": Marshalls.raw_to_base64(types.compress(FileAccess.COMPRESSION_DEFLATE)),
		"hp": Marshalls.raw_to_base64(hp.compress(FileAccess.COMPRESSION_DEFLATE)),
		"cut": cut,
	}


func load_state(widx: int, state: Dictionary, seed_val := 0) -> bool:
	world_index = widx
	depth = int(Data.WORLDS[widx]["depth"])
	H = depth + 1 + Data.VAULT_LAYERS + 1
	var n := W * W * H
	var old_n := W * W * depth
	var t := Marshalls.base64_to_raw(str(state.get("types", ""))).decompress_dynamic(n * 2, FileAccess.COMPRESSION_DEFLATE)
	var h := Marshalls.base64_to_raw(str(state.get("hp", ""))).decompress_dynamic(n * 2, FileAccess.COMPRESSION_DEFLATE)
	if t.size() == n and h.size() == n:
		types = t
		hp = h
	elif t.size() == old_n and h.size() == old_n:
		# a save from before bedrock + vaults: keep everything, add the new part underneath
		types = t
		hp = h
		types.resize(n)
		hp.resize(n)
		_gen_below(seed_val)
	else:
		return false
	cut = int(state.get("cut", 0))
	_recompute_all_columns()
	_clear_chunks()
	_make_walls()
	return true


# =============================================================================================
# Queries
# =============================================================================================

func _idx(x: int, d: int, z: int) -> int:
	return (d * W + z) * W + x


func is_solid(x: int, d: int, z: int) -> bool:
	if x < 0 or z < 0 or x >= W or z >= W or d < cut or d >= H:
		return false
	return types[(d * W + z) * W + x] != 0


func voxel_center(x: int, d: int, z: int) -> Vector3:
	return Vector3((x - W * 0.5 + 0.5) * VS, -(d + 0.5) * VS, (z - W * 0.5 + 0.5) * VS)


func top_y() -> float:
	return -cut * VS


func bottom_y() -> float:
	return -H * VS


func half_width() -> float:
	return W * 0.5 * VS


func _recompute_column(k: int) -> void:
	var x := k % W
	var z := k / W
	var d := cut
	while d < H and types[_idx(x, d, z)] == 0:
		d += 1
	col_top[k] = d


func _recompute_all_columns() -> void:
	col_top.resize(W * W)
	for k in W * W:
		_recompute_column(k)


## Average depth (in layers) of the deepest half of the columns: "how deep the dig is".
## Using half (not just the deepest point) means you have to clear a wide hole to progress.
func floor_depth() -> float:
	var arr := Array(col_top)
	arr.sort()
	var n := maxi(1, arr.size() / 2)
	var s := 0.0
	for i in n:
		s += arr[arr.size() - 1 - i]
	return s / n


## World position of the bottom of the hole (x/z = centre of the deepest columns).
func hole_point() -> Vector3:
	var best: Array = []
	for k in W * W:
		best.append([col_top[k], k])
	best.sort_custom(func(a, b): return a[0] > b[0])
	var n := maxi(1, best.size() / 6)
	var p := Vector3.ZERO
	for i in n:
		var k: int = best[i][1]
		p += voxel_center(k % W, mini(best[i][0], H - 1), k / W)
	return p / n


## A random column that is still high up (least dug), as a world position at its surface.
func high_point(tries := 3) -> Vector3:
	var best_k := randi() % (W * W)
	for i in tries - 1:
		var k := randi() % (W * W)
		if col_top[k] < col_top[best_k]:
			best_k = k
	return voxel_center(best_k % W, mini(col_top[best_k], H - 1), best_k / W)


## True once the pillar is nearly gone: the bedrock shows somewhere AND nothing left stands
## more than PORTAL_LAYERS_LEFT - 1 layers above it. This opens the portal to the next world.
const PORTAL_LAYERS_LEFT := 5

func reached_bedrock() -> bool:
	var exposed := false
	var highest := H
	for v in col_top:
		if v >= depth:
			exposed = true
		highest = mini(highest, v)
	return exposed and depth - highest < PORTAL_LAYERS_LEFT


## Layer under a world position (0 = top of the pillar).
func layer_at(p: Vector3) -> int:
	return int(floor(-p.y / VS))


## The highest layer anything still stands on (the top of the tallest column).
func highest_layer() -> int:
	var highest := H
	for v in col_top:
		highest = mini(highest, v)
	return highest


## Every breakable block (not bedrock, and nothing under intact bedrock) in layers d0..d1-1,
## as [index, type, position].
func cells_in_layers(d0: int, d1: int) -> Array:
	var out: Array = []
	for d in range(maxi(cut, d0), mini(_hurt_limit(), d1)):
		for z in W:
			for x in W:
				var i := _idx(x, d, z)
				var t := types[i]
				if t != 0 and t != bedrock_idx:
					out.append([i, t, voxel_center(x, d, z)])
	return out


## Show blocks as another type for a moment (the Golden Bomb's gold) without changing what they are.
func paint_cells(cells: Array, t: int) -> void:
	var layers := {}
	for c in cells:
		types[c[0]] = t
		layers[int(c[0]) / (W * W)] = true
	for d in layers:
		_mark_dirty(d)


## Break the given cells (as returned by cells_in_layers). They count as their original type.
func break_cells(cells: Array) -> Dictionary:
	var broken: Array = []
	var touched := {}
	for c in cells:
		var i: int = c[0]
		if types[i] == 0:
			continue
		types[i] = 0
		hp[i] = 255
		broken.append([c[1], c[2]])
		touched[i % (W * W)] = true
		_mark_dirty(i / (W * W))
	for k in touched:
		_recompute_column(k)
	if not touched.is_empty():
		_mark_dirty(0)   # plants on top go too
	return {"broken": broken, "damaged": 0, "plants": []}


## Break every block for which `gone(x, d, z)` returns true.
## Only looks at layers d0..d1-1. Used by the Sword Bomb's slices and the Moon Bomb.
func break_where(d0: int, d1: int, gone: Callable) -> Dictionary:
	var cells: Array = []
	for d in range(maxi(cut, d0), mini(_hurt_limit(), d1)):
		for z in W:
			for x in W:
				var i := _idx(x, d, z)
				var t := types[i]
				if t != 0 and t != bedrock_idx and gone.call(x, d, z):
					cells.append([i, t, voxel_center(x, d, z)])
	return break_cells(cells)


func bedrock_broken() -> bool:
	for z in W:
		for x in W:
			if types[_idx(x, depth, z)] == bedrock_idx:
				return false
	return true


## Bedrock Bomb: remove the whole bedrock layer. Returns where the bedrock blocks were (for effects).
func break_bedrock() -> Array:
	var spots: Array = []
	for z in W:
		for x in W:
			var i := _idx(x, depth, z)
			if types[i] == bedrock_idx:
				types[i] = 0
				spots.append(voxel_center(x, depth, z))
	if not cache_left():
		_place_cache()   # vaults made before the realms had crates get one now
	for k in W * W:
		_recompute_column(k)
	_mark_dirty(depth)
	return spots


func cache_left() -> bool:
	var cache: int = blocks.index_of("cache_" + Data.WORLDS[world_index]["id"])
	for z in range(W / 2 - 1, W / 2 + 1):
		for x in range(W / 2 - 1, W / 2 + 1):
			if types[_idx(x, H - 2, z)] == cache:
				return true
	return false


## 0..1 progress for the depth bar: the main pillar, or the vault once the bedrock is gone.
func progress() -> float:
	if bedrock_broken():
		return clampf((floor_depth() - depth - 1) / Data.VAULT_LAYERS, 0.0, 1.0)
	return clampf(floor_depth() / depth, 0.0, 1.0)


func blocks_left_ratio() -> float:
	return 1.0 - progress()


# =============================================================================================
# Destruction
# =============================================================================================

## Damage every block in the radius. Blocks near the centre take full damage, the edge takes
## less. Blocks that survive keep their damage (and show cracks).
## Returns {"broken": [[block_type, position], ...], "damaged": int, "plants": [positions]}
func explode(center: Vector3, radius: float, power: float) -> Dictionary:
	var broken: Array = []
	var damaged := 0
	var plants_hit: Array = []
	var r_vox := int(ceil(radius / VS)) + 1
	var cx := int(floor(center.x / VS + W * 0.5))
	var cd := int(floor(-center.y / VS))
	var cz := int(floor(center.z / VS + W * 0.5))
	var touched := {}
	for d in range(maxi(cut, cd - r_vox), mini(_hurt_limit(), cd + r_vox + 1)):
		for z in range(maxi(0, cz - r_vox), mini(W, cz + r_vox + 1)):
			for x in range(maxi(0, cx - r_vox), mini(W, cx + r_vox + 1)):
				var i := _idx(x, d, z)
				var t := types[i]
				if t == 0 or t == bedrock_idx:
					continue
				var p := voxel_center(x, d, z)
				var dist := p.distance_to(center)
				if dist > radius + VS * 0.5:
					continue
				var fall := clampf(1.15 - dist / maxf(radius, 0.01), 0.0, 1.0)
				if fall <= 0.0:
					continue
				var had_plant := d == 0 and hp[i] == 255 and has_plant(x, z)
				var maxhp := hp_table[t] * hp_mult
				var remaining := hp[i] / 255.0 * maxhp - power * fall
				var steps := _round_hp(remaining / maxhp * 255.0)
				if steps <= 0:
					types[i] = 0
					hp[i] = 255
					broken.append([t, p])
					touched[z * W + x] = true
					_mark_dirty(d)
				else:
					var nb := mini(steps, 254)
					if nb < hp[i]:
						if _stage(nb) != _stage(hp[i]):
							_mark_dirty(d)
						hp[i] = nb
						damaged += 1
				if had_plant and hp[i] != 255 or had_plant and types[i] == 0:
					plants_hit.append(p + Vector3(0, VS * 0.8, 0))
					_mark_dirty(0)
	for k in touched:
		_recompute_column(k)
	return {"broken": broken, "damaged": damaged, "plants": plants_hit}


## Explosions can't reach through bedrock: while the bedrock layer is whole, nothing under it
## (the vault) can be damaged, however close to the bedrock a bomb goes off.
func _hurt_limit() -> int:
	return H if bedrock_broken() else depth


## Is there anything left that bombs can still break? (False once you're down to bedrock
## everywhere and the vault, if open, is cleared out.)
func blocks_left() -> bool:
	for k in W * W:
		var d := col_top[k]
		if d < H and types[_idx(k % W, d, k / W)] != bedrock_idx:
			return true
	return false


## The lowest point a bomb can bore down to right now (top of the first whole bedrock layer).
func solid_floor_y() -> float:
	return -(H - 1) * VS if bedrock_broken() else -depth * VS


## Health is stored in 255 steps. A hit smaller than one step still has its fair chance of
## knocking a step off, so very tough blocks (the realms) wear down instead of shrugging hits off.
func _round_hp(exact: float) -> int:
	var whole := floori(exact)
	if randf() < exact - whole:
		whole += 1
	return whole


## Acid: breaks every block within `radius` (ignores toughness) and cracks the blocks in a band
## `edge` wide just outside it, so it looks like it's eating its way outwards.
func dissolve(center: Vector3, radius: float, edge: float) -> Dictionary:
	var broken: Array = []
	var plants_hit: Array = []
	var reach := radius + edge
	var r_vox := int(ceil(reach / VS)) + 1
	var cx := int(floor(center.x / VS + W * 0.5))
	var cd := int(floor(-center.y / VS))
	var cz := int(floor(center.z / VS + W * 0.5))
	var touched := {}
	for d in range(maxi(cut, cd - r_vox), mini(_hurt_limit(), cd + r_vox + 1)):
		for z in range(maxi(0, cz - r_vox), mini(W, cz + r_vox + 1)):
			for x in range(maxi(0, cx - r_vox), mini(W, cx + r_vox + 1)):
				var i := _idx(x, d, z)
				var t := types[i]
				if t == 0 or t == bedrock_idx:
					continue
				var p := voxel_center(x, d, z)
				var dist := p.distance_to(center)
				if dist > reach:
					continue
				var had_plant := d == 0 and hp[i] == 255 and has_plant(x, z)
				if dist <= radius:
					types[i] = 0
					hp[i] = 255
					broken.append([t, p])
					touched[z * W + x] = true
					_mark_dirty(d)
				else:
					var nb := clampi(int((dist - radius) / edge * 255.0), 1, 254)
					if nb < hp[i]:
						if _stage(nb) != _stage(hp[i]):
							_mark_dirty(d)
						hp[i] = nb
				if had_plant:
					plants_hit.append(p + Vector3(0, VS * 0.8, 0))
					_mark_dirty(0)
	for k in touched:
		_recompute_column(k)
	return {"broken": broken, "damaged": 0, "plants": plants_hit}


## Freeze Bomb: every block within `radius` drops to `left` (0..1) of its health - nearly broken,
## so the next bombs shatter it. Returns how many blocks were frozen.
func make_brittle(center: Vector3, radius: float, left: float) -> int:
	var n := 0
	var target := clampi(int(left * 255.0), 1, 254)
	for v in _blocks_in(center, radius):
		var i: int = v[0]
		if hp[i] > target:
			hp[i] = target
			n += 1
			_mark_dirty(v[1])
	return n


## Quake Bomb: damage every block in a slab `layers` thick across the whole pillar.
func damage_slab(top_d: int, layers: int, power: float) -> Dictionary:
	var broken: Array = []
	var touched := {}
	for d in range(maxi(cut, top_d), mini(_hurt_limit(), top_d + layers)):
		for z in W:
			for x in W:
				var i := _idx(x, d, z)
				var t := types[i]
				if t == 0 or t == bedrock_idx:
					continue
				var maxhp := hp_table[t] * hp_mult
				var remaining := hp[i] / 255.0 * maxhp - power
				var steps := _round_hp(remaining / maxhp * 255.0)
				if steps <= 0:
					broken.append([t, voxel_center(x, d, z)])
					types[i] = 0
					hp[i] = 255
					touched[z * W + x] = true
				else:
					hp[i] = mini(steps, 254)
				_mark_dirty(d)
	for k in touched:
		_recompute_column(k)
	return {"broken": broken, "damaged": 0, "plants": []}


## Magnet Bomb: rip out every ore block within `radius` (any toughness), leave the rock.
func pull_ores(center: Vector3, radius: float) -> Dictionary:
	var broken: Array = []
	var touched := {}
	for v in _blocks_in(center, radius):
		var i: int = v[0]
		var t := types[i]
		if blocks.defs[t]["ore"] == "":
			continue
		broken.append([t, v[2]])
		types[i] = 0
		hp[i] = 255
		touched[v[3]] = true
		_mark_dirty(v[1])
	for k in touched:
		_recompute_column(k)
	return {"broken": broken, "damaged": 0, "plants": []}


## [index, layer, position, column] for every solid, breakable block within radius.
func _blocks_in(center: Vector3, radius: float) -> Array:
	var out: Array = []
	var r_vox := int(ceil(radius / VS)) + 1
	var cx := int(floor(center.x / VS + W * 0.5))
	var cd := int(floor(-center.y / VS))
	var cz := int(floor(center.z / VS + W * 0.5))
	for d in range(maxi(cut, cd - r_vox), mini(_hurt_limit(), cd + r_vox + 1)):
		for z in range(maxi(0, cz - r_vox), mini(W, cz + r_vox + 1)):
			for x in range(maxi(0, cx - r_vox), mini(W, cx + r_vox + 1)):
				var i := _idx(x, d, z)
				var t := types[i]
				if t == 0 or t == bedrock_idx:
					continue
				var p := voxel_center(x, d, z)
				if p.distance_to(center) <= radius:
					out.append([i, d, p, z * W + x])
	return out


## Move the visible top down as the hole deepens. Returns true if it moved.
func update_cut() -> bool:
	var target := mini(maxi(0, int(floor_depth()) - CUT_GAP), H - 2)
	if target < cut + 2:
		return false
	cut = target
	for k in W * W:
		if col_top[k] < cut:
			_recompute_column(k)
	_mark_dirty(cut)
	refresh_window()
	return true


func _stage(h: int) -> int:
	if h > 191:
		return 0
	if h > 127:
		return 1
	if h > 63:
		return 2
	return 3


func _mark_dirty(d: int) -> void:
	var c := d / CHUNK
	dirty[c] = true
	if d % CHUNK == 0 and c > 0:
		dirty[c - 1] = true
	elif d % CHUNK == CHUNK - 1:
		dirty[c + 1] = true


# =============================================================================================
# Meshing
# =============================================================================================

func _clear_chunks() -> void:
	for c in chunks:
		chunks[c]["mesh"].queue_free()
		chunks[c]["body"].queue_free()
		chunks[c]["plants"].queue_free()
	chunks.clear()
	dirty.clear()
	coll_dirty.clear()


func refresh_window() -> void:
	var first := cut / CHUNK
	var last := mini((cut + VIEW_BELOW) / CHUNK, (H - 1) / CHUNK)
	for c in chunks.keys():
		if c < first or c > last:
			chunks[c]["mesh"].queue_free()
			chunks[c]["body"].queue_free()
			chunks[c]["plants"].queue_free()
			chunks.erase(c)
	for c in range(first, last + 1):
		if not chunks.has(c):
			_create_chunk(c)
			dirty[c] = true
			coll_dirty[c] = true


func process_dirty(delta := 0.016) -> void:
	if not dirty.is_empty():
		for c in dirty:
			if chunks.has(c):
				_build_chunk(c, false)      # what you see updates right away
				coll_dirty[c] = true
		dirty.clear()
	# collision shapes are rebuilt in batches - rebuilding them is the expensive part for physics
	coll_timer -= delta
	if coll_timer <= 0.0 and not coll_dirty.is_empty():
		coll_timer = COLLISION_INTERVAL
		var t := Time.get_ticks_usec()
		for c in coll_dirty:
			if chunks.has(c):
				_build_collision(c)
		coll_dirty.clear()
		var g = get_parent()
		if g and g.has_method("prof"):
			g.prof("collision", t)


func rebuild_all() -> void:
	refresh_window()
	for c in chunks:
		_build_chunk(c)
	dirty.clear()
	coll_dirty.clear()


func _create_chunk(c: int) -> void:
	var mi := MeshInstance3D.new()
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
	var plants := MeshInstance3D.new()
	plants.material_override = plant_material
	plants.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(plants)
	chunks[c] = {"mesh": mi, "body": body, "shape": shape, "cs": cs, "plants": plants}


func _build_collision(c: int) -> void:
	var ch: Dictionary = chunks[c]
	var tris := _collision_faces(maxi(c * CHUNK, cut), mini(c * CHUNK + CHUNK, H))
	if tris.is_empty():
		ch["shape"].set_faces(PackedVector3Array())
		ch["cs"].disabled = true
	else:
		ch["shape"].set_faces(tris)
		ch["cs"].disabled = false


func _build_chunk(c: int, with_collision := true) -> void:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var inds := PackedInt32Array()
	var d0 := maxi(c * CHUNK, cut)
	var d1 := mini(c * CHUNK + CHUNK, H)
	var half := W * 0.5
	for d in range(d0, d1):
		var fade := clampf(1.0 - (d - cut) / 70.0, 0.3, 1.0)
		for z in W:
			for x in W:
				var i := (d * W + z) * W + x
				var t := types[i]
				if t == 0:
					continue
				var stage := _stage(hp[i])
				var base := Vector3((x - half) * VS, -(d + 1) * VS, (z - half) * VS)
				for f in 6:
					if is_solid(x + FDX[f], d + FDD[f], z + FDZ[f]):
						continue
					var r: Rect2 = uv_table[t * 8 + (0 if f < 2 else 4) + stage]
					var shade: float = FACE_SHADE[f] * fade
					var col := Color(shade, shade, shade)
					var corners: Array = FACE_CORNERS[f]
					var start := verts.size()
					var v0: Vector3 = base + corners[0] * VS
					var v1: Vector3 = base + corners[1] * VS
					var v2: Vector3 = base + corners[2] * VS
					var v3: Vector3 = base + corners[3] * VS
					verts.append(v0)
					verts.append(v1)
					verts.append(v2)
					verts.append(v3)
					uvs.append(r.position)
					uvs.append(Vector2(r.end.x, r.position.y))
					uvs.append(r.end)
					uvs.append(Vector2(r.position.x, r.end.y))
					cols.append(col)
					cols.append(col)
					cols.append(col)
					cols.append(col)
					inds.append(start)
					inds.append(start + 1)
					inds.append(start + 2)
					inds.append(start)
					inds.append(start + 2)
					inds.append(start + 3)
	var ch: Dictionary = chunks[c]
	if c == 0:
		_build_plants(ch["plants"])
	var mi: MeshInstance3D = ch["mesh"]
	if with_collision:
		_build_collision(c)
	if verts.is_empty():
		mi.mesh = null
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = inds
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mi.mesh = mesh


# =============================================================================================
# Plants (tall grass and flowers on top of grass blocks, Minecraft-style crossed quads)
# =============================================================================================

## Which plant grows on top of column x,z (-1 = none). Fixed per world so it never changes.
func plant_at(x: int, z: int) -> int:
	var h := absi((x * 73856093) ^ (z * 19349663) ^ ((world_index + 1) * 83492791))
	var r := h % 100
	if r < 32:
		return (h / 100) % 2              # tall grass
	if r < 44:
		return 2 + (h / 1000) % 5         # a flower
	return -1


func has_plant(x: int, z: int) -> bool:
	var i := _idx(x, 0, z)
	return cut == 0 and types[i] != 0 and hp[i] == 255 and grass_blocks.has(int(types[i])) and plant_at(x, z) >= 0


func _build_plants(mi: MeshInstance3D) -> void:
	if cut > 0:
		mi.mesh = null
		return
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var inds := PackedInt32Array()
	var n := float(blocks.PLANT_NAMES.size())
	var r := VS * 0.45
	for z in W:
		for x in W:
			if not has_plant(x, z):
				continue
			var kind := plant_at(x, z)
			var c := voxel_center(x, 0, z)
			var base := Vector3(c.x, 0.0, c.z)
			var h := VS * (0.85 + ((x * 7 + z * 13) % 5) * 0.04)
			var u0 := kind / n
			var u1 := (kind + 1) / n
			for diag in 2:
				var a := Vector3(-r, 0, -r) if diag == 0 else Vector3(-r, 0, r)
				var start := verts.size()
				verts.append(base + a + Vector3(0, h, 0))
				verts.append(base - a + Vector3(0, h, 0))
				verts.append(base - a)
				verts.append(base + a)
				uvs.append(Vector2(u0, 0.0))
				uvs.append(Vector2(u1, 0.0))
				uvs.append(Vector2(u1, 1.0))
				uvs.append(Vector2(u0, 1.0))
				var top := Color(1, 1, 1) if diag == 0 else Color(0.9, 0.9, 0.9)
				var bottom := top.darkened(0.3)
				cols.append(top)
				cols.append(top)
				cols.append(bottom)
				cols.append(bottom)
				for k in [0, 1, 2, 0, 2, 3]:
					inds.append(start + k)
	if verts.is_empty():
		mi.mesh = null
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = inds
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mi.mesh = mesh


# =============================================================================================
# Collision: merged rectangles (much less work for the physics engine than one square per face)
# =============================================================================================

## Collision triangles for layers d0..d1. Neighbouring faces that lie in the same plane are merged
## into big rectangles (greedy meshing), and the pillar's outer sides are skipped because the
## invisible walls already stop bombs there.
func _collision_faces(d0: int, d1: int) -> PackedVector3Array:
	var tris := PackedVector3Array()
	if d1 <= d0:
		return tris
	var half := W * 0.5
	var rows := d1 - d0
	# look every block up once (with a 1-block border) instead of calling is_solid() thousands of times
	var P := W + 2
	var sol := PackedByteArray()
	sol.resize(P * P * (rows + 2))
	for dd in range(rows + 2):
		var d := d0 - 1 + dd
		if d < cut or d >= H:
			continue
		for z in W:
			var row := (d * W + z) * W
			var o := (dd * P + z + 1) * P + 1
			for x in W:
				if types[row + x] != 0:
					sol[o + x] = 1
	var PP := P * P
	# top (f=0) and bottom (f=1) faces
	for r_i in rows:
		var base := (r_i + 1) * PP
		for f in [0, 1]:
			var nb: int = base + (-PP if f == 0 else PP)
			var mask := PackedByteArray()
			mask.resize(W * W)
			var any := false
			for z in W:
				for x in W:
					var o := (z + 1) * P + x + 1
					if sol[base + o] == 1 and sol[nb + o] == 0:
						mask[z * W + x] = 1
						any = true
			if not any:
				continue
			var d := d0 + r_i
			var y := -d * VS if f == 0 else -(d + 1) * VS
			for r in _greedy(mask, W, W):
				var x0: float = (r.x - half) * VS
				var z0: float = (r.y - half) * VS
				var x1: float = (r.x + r.z - half) * VS
				var z1: float = (r.y + r.w - half) * VS
				_quad(tris, Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1))
	# +x / -x faces (outer sides skipped: the invisible walls are there)
	for f in [2, 3]:
		var step: int = 1 if f == 2 else -1
		for x in W:
			if (f == 2 and x == W - 1) or (f == 3 and x == 0):
				continue
			var mask := PackedByteArray()
			mask.resize(W * rows)
			var any := false
			for r_i in rows:
				var base := (r_i + 1) * PP
				for z in W:
					var o := base + (z + 1) * P + x + 1
					if sol[o] == 1 and sol[o + step] == 0:
						mask[r_i * W + z] = 1
						any = true
			if not any:
				continue
			var px: float = (x + (1 if f == 2 else 0) - half) * VS
			for r in _greedy(mask, W, rows):
				var z0: float = (r.x - half) * VS
				var z1: float = (r.x + r.z - half) * VS
				var ytop: float = -(d0 + r.y) * VS
				var ybot: float = -(d0 + r.y + r.w) * VS
				_quad(tris, Vector3(px, ytop, z0), Vector3(px, ytop, z1), Vector3(px, ybot, z1), Vector3(px, ybot, z0))
	# +z / -z faces
	for f in [4, 5]:
		var step: int = P if f == 4 else -P
		for z in W:
			if (f == 4 and z == W - 1) or (f == 5 and z == 0):
				continue
			var mask := PackedByteArray()
			mask.resize(W * rows)
			var any := false
			for r_i in rows:
				var base := (r_i + 1) * PP + (z + 1) * P + 1
				for x in W:
					var o := base + x
					if sol[o] == 1 and sol[o + step] == 0:
						mask[r_i * W + x] = 1
						any = true
			if not any:
				continue
			var pz: float = (z + (1 if f == 4 else 0) - half) * VS
			for r in _greedy(mask, W, rows):
				var x0: float = (r.x - half) * VS
				var x1: float = (r.x + r.z - half) * VS
				var ytop: float = -(d0 + r.y) * VS
				var ybot: float = -(d0 + r.y + r.w) * VS
				_quad(tris, Vector3(x0, ytop, pz), Vector3(x1, ytop, pz), Vector3(x1, ybot, pz), Vector3(x0, ybot, pz))
	return tris


## Greedy rectangles over a w x h mask. Returns Vector4i(a, b, width, height) per rectangle.
func _greedy(mask: PackedByteArray, w: int, h: int) -> Array[Vector4i]:
	var out: Array[Vector4i] = []
	var used := PackedByteArray()
	used.resize(w * h)
	for b in h:
		for a in w:
			var i := b * w + a
			if mask[i] == 0 or used[i] == 1:
				continue
			var rw := 1
			while a + rw < w and mask[i + rw] == 1 and used[i + rw] == 0:
				rw += 1
			var rh := 1
			var grow := true
			while grow and b + rh < h:
				for k in rw:
					var j := (b + rh) * w + a + k
					if mask[j] == 0 or used[j] == 1:
						grow = false
						break
				if grow:
					rh += 1
			for yy in rh:
				for xx in rw:
					used[(b + yy) * w + a + xx] = 1
			out.append(Vector4i(a, b, rw, rh))
	return out


func _quad(tris: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	tris.append(a)
	tris.append(b)
	tris.append(c)
	tris.append(a)
	tris.append(c)
	tris.append(d)
