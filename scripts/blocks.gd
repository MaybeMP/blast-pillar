extends RefCounted
## Block registry + texture atlas.
##
## Every block gets 16x16 pixel-art tiles: a TOP version (top/bottom faces) and a SIDE version,
## each in 4 crack stages (0 = intact .. 3 = nearly broken).
## Textures are drawn from a per-layer "style" (see data.gd), using a small 4-shade palette so
## they read as clean pixel art instead of noise.
##
## Your own textures: drop 16x16 PNGs in res://textures/blocks/
##   <block_id>.png        used for every face
##   <block_id>_side.png   (optional) side faces only
## Crack overlays are added on top automatically.

const Data = preload("res://scripts/data.gd")

const TILE := 16
const STAGES := 4

var defs: Array = []
var by_id := {}
var atlas: ImageTexture
var atlas_rows := 0


func _init() -> void:
	_build_plants()
	defs.append({"id": "air", "name": "Air", "hp": 0.0, "ore": "", "world": -1, "c1": Color.BLACK, "c2": Color.BLACK, "style": "stone"})
	# Block numbers are saved, so the order here must never change: worlds 1-6, then bedrock and
	# the vaults of worlds 1-6, then everything for worlds 7+ (one world after another).
	for w in Data.ORIGINAL_WORLDS:
		_add_world_blocks(w)
	_add({"id": "bedrock", "name": "Bedrock", "hp": 1.0e30, "ore": "", "world": -1, "style": "bedrock",
		"c1": Color("2c2c2e"), "c2": Color("4a4a4e"), "bedrock": true})
	for w in Data.ORIGINAL_WORLDS:
		_add_vault_blocks(w)
	for w in range(Data.ORIGINAL_WORLDS, Data.WORLDS.size()):
		_add_world_blocks(w)
		_add_vault_blocks(w)
	# the portal's frame (never part of a pillar)
	_add({"id": "portal_frame", "name": "Obsidian", "hp": 1.0e30, "ore": "", "world": -1, "style": "portal",
		"c1": Color("0c0814"), "c2": Color("1a1128")})
	# pure gold, shown for a moment by the Golden Bomb (added last so saved worlds keep their numbers)
	_add({"id": "gold_block", "name": "Gold", "hp": 1.0, "ore": "", "world": 0, "coins": 0.0, "style": "gold",
		"c1": Color("ffd23a"), "c2": Color("e0a81e")})
	# Cosmic Eggs buried in each world, set in that world's own rock and about as tough as its
	# rare ores (also added last, so older saves keep their block numbers)
	for w in Data.WORLDS.size():
		var world: Dictionary = Data.WORLDS[w]
		var host: Dictionary = world["layers"][2]
		_add({"id": "egg_" + world["id"], "name": "Cosmic Egg", "hp": float(world["hard"]) * 13.0,
			"ore": Data.BEDROCK_BOMB_ORE, "world": w, "style": _ore_host_style(host),
			"c1": Data.color(host["c1"]), "c2": Data.color(host["c2"]), "oc": Color("ffffff"), "rank": 5})
	_build_atlas()


func _add_world_blocks(w: int) -> void:
	var world: Dictionary = Data.WORLDS[w]
	var hard := float(world["hard"])
	var layers: Array = world["layers"]
	var host: Dictionary = layers[2]
	for li in layers.size():
		var l: Dictionary = layers[li]
		var under: Dictionary = layers[mini(li + 1, layers.size() - 1)]
		_add({"id": "%s_%s" % [world["id"], l["id"]], "name": l["name"], "hp": float(l["hp"]) * hard,
			"ore": "", "world": w, "style": l.get("style", "stone"),
			"c1": Data.color(l["c1"]), "c2": Data.color(l["c2"]),
			"u1": Data.color(under["c1"]), "u2": Data.color(under["c2"]), "ustyle": under.get("style", "stone"),
			"coins": 0.05 * (li + 1) * float(world["value"])})
	var rank := 0
	for o in world["ores"]:
		_add({"id": "ore_" + o["id"], "name": o["name"], "hp": hard * (4.0 + rank * 3.0), "ore": o["id"],
			"world": w, "style": _ore_host_style(host), "c1": Data.color(host["c1"]), "c2": Data.color(host["c2"]),
			"oc": Data.color(o["col"]), "rank": rank})
		rank += 1
	var tr: Dictionary = world["treasure"]
	_add({"id": "ore_" + tr["id"], "name": tr["name"], "hp": hard * 24.0, "ore": tr["id"], "world": w,
		"style": _ore_host_style(host), "c1": Data.color(host["c1"]), "c2": Data.color(host["c2"]),
		"oc": Data.color(tr["col"]), "rank": 5})


func _add_vault_blocks(w: int) -> void:
	var world: Dictionary = Data.WORLDS[w]
	var deep: Dictionary = world["layers"][world["layers"].size() - 1]
	var vhp := float(deep["hp"]) * float(world["hard"]) * 2.5
	_add({"id": "vault_" + world["id"], "name": "Vault Rock", "hp": vhp, "ore": "", "world": w, "style": "deep",
		"c1": Data.color(deep["c1"]).darkened(0.3), "c2": Data.color(deep["c2"]).darkened(0.2),
		"coins": 0.25 * float(world["value"])})
	_add({"id": "cache_" + world["id"], "name": "Bomb Cache", "hp": vhp * 2.0, "ore": "", "world": w, "style": "cache",
		"c1": Color("6b4a2e"), "c2": Color("ffcf5a"), "cache_world": w})



## Plant sprites for the grass top of World 1 (drawn as crossed quads like Minecraft).
const PLANT_SPRITES := {
	"grass1": [
		"................",
		"................",
		"................",
		"......l.........",
		"..l...g.....l...",
		"..g...gl...g....",
		"...g..gG..gl....",
		"...gl.gG..g..l..",
		"....g.gG.gG.g...",
		".l..gGgG.gGgg...",
		"..g.gGGGgGGg....",
		"..ggGGGGGGg.....",
		"...gGGGGGGg.....",
		"....GGGGGG......",
		"....GGGGGGG.....",
		"...GGGGGGGG.....",
	],
	"grass2": [
		"................",
		"................",
		"................",
		"................",
		"................",
		"...........l....",
		"..l........g....",
		"..g...l...gG....",
		"..gl..g...gG.l..",
		"...g..gG.gG..g..",
		"...gG.gG.gG.gG..",
		"....gGgGgGGgG...",
		"....gGGGGGGGG...",
		"....GGGGGGGG....",
		"...GGGGGGGGGG...",
		"..GGGGGGGGGGG...",
	],
	"poppy": [
		"................",
		"................",
		"................",
		"................",
		"......rr........",
		".....rRrr.......",
		"....rrkkrr......",
		".....rkkRr......",
		"......rr........",
		".......G........",
		".......G..gg....",
		"...gg..G.gG.....",
		"....gG.GgG......",
		"......GGG.......",
		".......G........",
		".......G........",
	],
	"dandelion": [
		"................",
		"................",
		"................",
		"................",
		"................",
		"......yy........",
		".....yYYy.......",
		".....yYYy.......",
		"......yy........",
		".......G........",
		".......G........",
		"..gg...G..gg....",
		"...gG..G.Gg.....",
		".....GGGGG......",
		".......G........",
		".......G........",
	],
	"cornflower": [
		"................",
		"................",
		"................",
		"................",
		".....b.b.b......",
		"......bbb.......",
		".....bbCbb......",
		"......bbb.......",
		".....b...b......",
		".......G........",
		".......G.g......",
		"....g..GgG......",
		"....Gg.GG.......",
		"......GG........",
		".......G........",
		".......G........",
	],
	"daisy": [
		"................",
		"................",
		"................",
		"................",
		"......w.w.......",
		".....wwwww......",
		"....wwyyyww.....",
		".....wyyyw......",
		"....wwyyyww.....",
		".....wwwww......",
		"......wGw.......",
		"...gg..G........",
		"....gG.G.gg.....",
		"......GGGg......",
		".......G........",
		".......G........",
	],
	"allium": [
		"................",
		"......pPp.......",
		".....pPpPp......",
		".....PpPpP......",
		".....pPpPp......",
		"......pPp.......",
		".......G........",
		".......G........",
		".......G........",
		".......G........",
		".......G..g.....",
		".......G.gG.....",
		"...gg..GgG......",
		"....gG.GG.......",
		"......GG........",
		".......G........",
	],
}
const PLANT_PALETTE := {
	"g": "6cbf3f", "G": "3f8f2a", "l": "9be36b", "r": "e8283c", "R": "ff6b6b", "k": "2a1a10",
	"y": "ffd23a", "Y": "e89a1a", "b": "4f7cff", "C": "1f3fb0", "w": "f4f1ea", "p": "b46bff", "P": "8a3fd6",
}
const PLANT_NAMES := ["grass1", "grass2", "poppy", "dandelion", "cornflower", "daisy", "allium"]

var plant_atlas: ImageTexture


func _build_plants() -> void:
	var img := Image.create(TILE * PLANT_NAMES.size(), TILE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i in PLANT_NAMES.size():
		var path := "res://textures/plants/%s.png" % PLANT_NAMES[i]
		var custom := _load_png(path)
		if custom:
			img.blit_rect(custom, Rect2i(0, 0, TILE, TILE), Vector2i(i * TILE, 0))
			continue
		var rows: Array = PLANT_SPRITES[PLANT_NAMES[i]]
		for y in TILE:
			var row: String = rows[y]
			for x in TILE:
				var ch := row[x]
				if PLANT_PALETTE.has(ch):
					img.set_pixel(i * TILE + x, y, Color.html(PLANT_PALETTE[ch]))
	plant_atlas = ImageTexture.create_from_image(img)


func _load_png(path: String) -> Image:
	if not ResourceLoader.exists(path):
		return null
	var tex = load(path)
	if not (tex is Texture2D):
		return null
	var im: Image = tex.get_image().duplicate()
	if im.is_compressed():
		im.decompress()
	im.convert(Image.FORMAT_RGBA8)
	if im.get_width() != TILE or im.get_height() != TILE:
		im.resize(TILE, TILE, Image.INTERPOLATE_NEAREST)
	return im


## Ores sit in plain rock so the gems stand out (no glowing magma behind them).
func _ore_host_style(host: Dictionary) -> String:
	var st: String = host.get("style", "stone")
	return "stone" if st == "magma" else st


func _add(d: Dictionary) -> void:
	by_id[d["id"]] = defs.size()
	defs.append(d)


func is_bedrock(b: int) -> bool:
	return defs[b].get("bedrock", false)


func index_of(id: String) -> int:
	return int(by_id.get(id, 0))


## UV rect for a block. side = true for the four side faces.
func uv(block: int, side: bool, stage: int) -> Rect2:
	var w := float(TILE * STAGES * 2)
	var h := float(TILE * atlas_rows)
	var inset := 0.02
	var col := (STAGES if side else 0) + stage
	return Rect2((col * TILE + inset) / w, (block * TILE + inset) / h, (TILE - inset * 2.0) / w, (TILE - inset * 2.0) / h)


# =============================================================================================
# Atlas
# =============================================================================================

func _build_atlas() -> void:
	atlas_rows = defs.size()
	var img := Image.create(TILE * STAGES * 2, TILE * atlas_rows, false, Image.FORMAT_RGBA8)
	var cracks := _crack_masks()
	for b in range(1, defs.size()):
		var d: Dictionary = defs[b]
		var top := _load_override(d["id"])
		var side := _load_override(d["id"] + "_side")
		if top == null:
			top = _gen(d, b, false)
		if side == null:
			side = top if not (d["style"] in ["grass", "snow"]) or d["ore"] != "" or _has_override(d["id"]) else _gen(d, b, true)
		for v in 2:
			var tile: Image = top if v == 0 else side
			for s in STAGES:
				var mask: PackedByteArray = cracks[s]
				var ox := (v * STAGES + s) * TILE
				for y in TILE:
					for x in TILE:
						var c := tile.get_pixel(x, y)
						var m := mask[y * TILE + x]
						if m == 1:
							c = c.darkened(0.5)
						elif m == 2:
							c = c.lightened(0.12)
						img.set_pixel(ox + x, b * TILE + y, c)
	atlas = ImageTexture.create_from_image(img)


func _has_override(id: String) -> bool:
	return ResourceLoader.exists("res://textures/blocks/%s.png" % id)


func _load_override(id: String) -> Image:
	var path := "res://textures/blocks/%s.png" % id
	if not ResourceLoader.exists(path):
		return null
	var tex = load(path)
	if not (tex is Texture2D):
		return null
	var im: Image = tex.get_image()
	if im == null:
		return null
	im = im.duplicate()
	if im.is_compressed():
		im.decompress()
	im.convert(Image.FORMAT_RGBA8)
	if im.get_width() != TILE or im.get_height() != TILE:
		im.resize(TILE, TILE, Image.INTERPOLATE_NEAREST)
	return im


## Crack masks per stage: 0 = none, 1 = crack pixel, 2 = light edge beside a crack.
func _crack_masks() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var masks: Array = []
	var cur := PackedByteArray()
	cur.resize(TILE * TILE)
	masks.append(cur.duplicate())
	# a crack grows from the centre outwards; each stage adds more branches
	var tips: Array = [Vector2i(7, 7), Vector2i(8, 8)]
	var steps := [6, 9, 12]
	for s in 3:
		var new_tips: Array = []
		for t in tips:
			var p: Vector2i = t
			var dir := Vector2i(1 if rng.randf() < 0.5 else -1, 1 if rng.randf() < 0.5 else -1)
			for k in steps[s]:
				if p.x < 1 or p.y < 1 or p.x > TILE - 2 or p.y > TILE - 2:
					break
				cur[p.y * TILE + p.x] = 1
				if rng.randf() < 0.55:
					p.x += dir.x
				else:
					p.y += dir.y
			new_tips.append(p)
			if s < 2:
				new_tips.append(t)
		tips = new_tips
		# light pixel to the lower-right of each crack pixel (looks carved in)
		var out := cur.duplicate()
		for y in TILE - 1:
			for x in TILE - 1:
				if cur[y * TILE + x] == 1 and cur[(y + 1) * TILE + x + 1] == 0:
					out[(y + 1) * TILE + x + 1] = 2
		masks.append(out)
	return masks


# =============================================================================================
# Tile generators
# =============================================================================================

func _gen(d: Dictionary, b: int, side: bool) -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = b * 7919 + (31 if side else 0)
	var img := Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
	var style: String = d["style"]
	var c1: Color = d["c1"]
	var c2: Color = d["c2"]
	match style:
		"grass":
			if side:
				_soil(img, rng, d["u1"], d["u2"])
				_fringe(img, rng, c1, 3, 5)
			else:
				_grass_top(img, rng, c1, c2)
		"snow":
			if side:
				_draw_style(img, rng, d["ustyle"], d["u1"], d["u2"])
				_fringe(img, rng, c1, 2, 5)
			else:
				_snow(img, rng, c1, c2)
		_:
			_draw_style(img, rng, style, c1, c2)
	if d["ore"] != "":
		_ore(img, rng, d["oc"], int(d.get("rank", 0)), c1)
	_bevel(img)
	return img


func _draw_style(img: Image, rng: RandomNumberGenerator, style: String, c1: Color, c2: Color) -> void:
	match style:
		"soil": _soil(img, rng, c1, c2)
		"sand": _sand(img, rng, c1, c2)
		"stone": _stone(img, rng, c1, c2, 7, 1.0, false)
		"deep": _stone(img, rng, c1, c2, 9, 0.55, false)
		"magma": _stone(img, rng, c1, c2, 6, 0.8, true)
		"strata": _strata(img, rng, c1, c2)
		"ice": _ice(img, rng, c1, c2)
		"crystal": _crystal(img, rng, c1, c2)
		"obsidian": _obsidian(img, rng, c1, c2)
		"glow": _glow(img, rng, c1, c2)
		"void": _void(img, rng, c1, c2)
		"snow": _snow(img, rng, c1, c2)
		"grass": _grass_top(img, rng, c1, c2)
		"bedrock": _bedrock(img, rng, c1, c2)
		"cache": _cache(img, rng, c1, c2)
		"portal": _portal_obsidian(img, rng)
		"gold": _gold_block(img, rng)
		_: _stone(img, rng, c1, c2, 7, 1.0, false)


## A block of solid gold: bright and smooth, light edges top-left, darker bottom-right, a few glints.
func _gold_block(img: Image, rng: RandomNumberGenerator) -> void:
	var base := Color("fcd73c")
	var light := Color("fff3a0")
	var mid := Color("f2c22a")
	var dark := Color("c8901a")
	for y in TILE:
		for x in TILE:
			var c := base
			if (x + y) % 7 == 0 and rng.randf() < 0.5:
				c = mid
			img.set_pixel(x, y, c)
	for i in TILE:
		img.set_pixel(i, 0, light)
		img.set_pixel(0, i, light)
		img.set_pixel(i, TILE - 1, dark)
		img.set_pixel(TILE - 1, i, dark)
	for i in range(2, TILE - 4):
		img.set_pixel(i, 2, light.lerp(base, 0.4))
		img.set_pixel(2, i, light.lerp(base, 0.4))
	for i in 4:
		var px := rng.randi_range(3, TILE - 4)
		var py := rng.randi_range(3, TILE - 4)
		img.set_pixel(px, py, Color.WHITE)
		img.set_pixel(px + 1, py, light)
		img.set_pixel(px, py + 1, light)


func _shades(c: Color) -> Array:
	return [c.darkened(0.3), c.darkened(0.15), c, c.lightened(0.12)]


func _noise(rng: RandomNumberGenerator, freq: float) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = rng.randi()
	n.frequency = freq
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	return n


## Map a -1..1 value to one of 4 palette shades.
func _pick(sh: Array, v: float) -> Color:
	return sh[clampi(int((v + 1.0) * 2.0), 0, 3)]


func _soil(img: Image, rng: RandomNumberGenerator, c1: Color, c2: Color) -> void:
	var sh := _shades(c1)
	var n := _noise(rng, 0.22)
	for y in TILE:
		for x in TILE:
			img.set_pixel(x, y, _pick(sh, n.get_noise_2d(x, y) * 1.1 + rng.randf_range(-0.25, 0.25)))
	# clumps in the second colour
	for i in 4:
		var cx := rng.randi_range(1, TILE - 3)
		var cy := rng.randi_range(1, TILE - 3)
		img.set_pixel(cx, cy, c2.lightened(0.05))
		img.set_pixel(cx + 1, cy, c2)
		img.set_pixel(cx, cy + 1, c2)
		img.set_pixel(cx + 1, cy + 1, c2.darkened(0.2))
	# pebbles
	for i in 3:
		var px := rng.randi_range(1, TILE - 2)
		var py := rng.randi_range(1, TILE - 2)
		img.set_pixel(px, py, c1.lightened(0.3))
		img.set_pixel(px + 1, py + 1, c1.darkened(0.4))


func _sand(img: Image, rng: RandomNumberGenerator, c1: Color, c2: Color) -> void:
	var sh := [c1.darkened(0.12), c1.darkened(0.05), c1, c1.lightened(0.08)]
	var n := _noise(rng, 0.3)
	for y in TILE:
		for x in TILE:
			var ripple := sin((y + n.get_noise_2d(x, y) * 3.0) * 1.1) * 0.6
			img.set_pixel(x, y, _pick(sh, ripple + rng.randf_range(-0.3, 0.3)))
	for i in 10:
		var px := rng.randi_range(0, TILE - 1)
		var py := rng.randi_range(0, TILE - 1)
		img.set_pixel(px, py, c2.darkened(0.15) if rng.randf() < 0.6 else c1.lightened(0.25))


## Voronoi rock plates with dark seams. squash < 1 stretches plates sideways.
## glow = true makes the seams glow (magma).
func _stone(img: Image, rng: RandomNumberGenerator, c1: Color, c2: Color, cells: int, squash: float, glow: bool) -> void:
	var pts: Array[Vector2] = []
	var shade: Array[Color] = []
	var sh := _shades(c1)
	for i in cells:
		pts.append(Vector2(rng.randf_range(-1, TILE + 1), rng.randf_range(-1, TILE + 1)))
		var r := rng.randf()
		shade.append(c2 if r < 0.25 else sh[rng.randi_range(1, 3)])
	var seam := c1.darkened(0.45)
	var edge := PackedByteArray()
	edge.resize(TILE * TILE)
	for y in TILE:
		for x in TILE:
			var p := Vector2(x + 0.5, y + 0.5)
			var d1 := INF
			var d2 := INF
			var best := 0
			for i in cells:
				var dv := pts[i] - p
				dv.x *= squash
				var dd := dv.length()
				if dd < d1:
					d2 = d1
					d1 = dd
					best = i
				elif dd < d2:
					d2 = dd
			if d2 - d1 < 1.1:
				edge[y * TILE + x] = 1
				img.set_pixel(x, y, seam)
			else:
				var c: Color = shade[best]
				if rng.randf() < 0.08:
					c = c.darkened(0.12)
				img.set_pixel(x, y, c)
	# light catches the top edge of each plate, shadow under it
	for y in range(1, TILE):
		for x in TILE:
			if edge[y * TILE + x] == 0 and edge[(y - 1) * TILE + x] == 1:
				img.set_pixel(x, y, img.get_pixel(x, y).lightened(0.15))
	if glow:
		var hot := Color("ff8a1f")
		var core := Color("ffd84a")
		for y in TILE:
			for x in TILE:
				if edge[y * TILE + x] == 1:
					var r := rng.randf()
					if r < 0.15:
						img.set_pixel(x, y, core)
					elif r < 0.7:
						img.set_pixel(x, y, hot.darkened(0.15))


func _strata(img: Image, rng: RandomNumberGenerator, c1: Color, c2: Color) -> void:
	var n := _noise(rng, 0.25)
	var bands := [c1.lightened(0.08), c1, c2, c1.darkened(0.1), c2.darkened(0.1)]
	for y in TILE:
		for x in TILE:
			var band := int(floor((y + n.get_noise_2d(x, 0) * 1.5) / 3.0))
			var c: Color = bands[posmod(band, bands.size())]
			var by := posmod(int(floor(y + n.get_noise_2d(x, 0) * 1.5)), 3)
			if by == 0:
				c = c.lightened(0.1)
			elif by == 2:
				c = c.darkened(0.08)
			if rng.randf() < 0.06:
				c = c.darkened(0.2)
			img.set_pixel(x, y, c)


func _ice(img: Image, rng: RandomNumberGenerator, c1: Color, c2: Color) -> void:
	var n := _noise(rng, 0.12)
	var sh := [c2.darkened(0.1), c2, c1, c1.lightened(0.15)]
	for y in TILE:
		for x in TILE:
			img.set_pixel(x, y, _pick(sh, n.get_noise_2d(x, y) * 1.2))
	# diagonal shine streaks
	for k in 2:
		var off := rng.randi_range(3, 20)
		for x in TILE:
			var y := off - x
			if y >= 0 and y < TILE:
				img.set_pixel(x, y, c1.lightened(0.35))
				if y + 1 < TILE:
					img.set_pixel(x, y + 1, c1.lightened(0.18))
	for i in 3:
		img.set_pixel(rng.randi_range(0, TILE - 1), rng.randi_range(0, TILE - 1), Color.WHITE)


func _crystal(img: Image, rng: RandomNumberGenerator, c1: Color, c2: Color) -> void:
	var sh := [c2.darkened(0.1), c2, c1, c1.lightened(0.15)]
	var a := rng.randi_range(4, 9)
	var b := rng.randi_range(4, 9)
	for y in TILE:
		for x in TILE:
			var facet := int(floor((x + y + a) / 5.0)) + int(floor((x - y + 16 + b) / 7.0))
			img.set_pixel(x, y, sh[posmod(facet, 4)])
	for i in 4:
		var px := rng.randi_range(1, TILE - 2)
		var py := rng.randi_range(1, TILE - 2)
		img.set_pixel(px, py, Color.WHITE)
		img.set_pixel(px + 1, py, c1.lightened(0.4))


func _obsidian(img: Image, rng: RandomNumberGenerator, c1: Color, c2: Color) -> void:
	var n := _noise(rng, 0.18)
	var sh := [c2.darkened(0.2), c2, c1, c1.lightened(0.1)]
	for y in TILE:
		for x in TILE:
			img.set_pixel(x, y, _pick(sh, n.get_noise_2d(x, y) * 1.3))
	var glint := c1.lightened(0.5).lerp(Color("b46bff"), 0.5)
	for i in 6:
		var px := rng.randi_range(0, TILE - 2)
		var py := rng.randi_range(0, TILE - 1)
		img.set_pixel(px, py, glint)
		img.set_pixel(px + 1, py, glint.darkened(0.3))


## The portal frame: near-black obsidian with dark-purple blotches and a few bright violet glints.
func _portal_obsidian(img: Image, rng: RandomNumberGenerator) -> void:
	var base := Color("0e0a16")
	var dark := Color("08060d")
	var mid := Color("1c1430")
	var blot := Color("2b1c48")
	var hi := Color("5b3696")
	var glint := Color("a77cf0")
	var n := _noise(rng, 0.22)
	for y in TILE:
		for x in TILE:
			var v := n.get_noise_2d(x, y)
			var c := base
			if v > 0.32:
				c = blot
			elif v > 0.08:
				c = mid
			elif v < -0.38:
				c = dark
			img.set_pixel(x, y, c)
	# lighter purple streaks along the blotch edges
	for y in TILE:
		for x in range(1, TILE):
			if n.get_noise_2d(x, y) > 0.32 and n.get_noise_2d(x - 1, y) <= 0.32 and rng.randf() < 0.55:
				img.set_pixel(x, y, hi)
	for i in 5:
		var px := rng.randi_range(1, TILE - 2)
		var py := rng.randi_range(1, TILE - 2)
		img.set_pixel(px, py, glint)
		img.set_pixel(px + 1, py, hi)
		img.set_pixel(px, py + 1, hi.darkened(0.25))
	# a darker rim so neighbouring blocks read as separate blocks
	for k in TILE:
		img.set_pixel(k, TILE - 1, img.get_pixel(k, TILE - 1).darkened(0.35))
		img.set_pixel(TILE - 1, k, img.get_pixel(TILE - 1, k).darkened(0.35))


func _glow(img: Image, rng: RandomNumberGenerator, c1: Color, c2: Color) -> void:
	_soil(img, rng, c1, c1.darkened(0.15))
	var bright := c2.lightened(0.6)
	for i in 5:
		var px := rng.randi_range(1, TILE - 2)
		var py := rng.randi_range(1, TILE - 2)
		img.set_pixel(px, py, Color.WHITE)
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			img.set_pixel(px + o.x, py + o.y, bright)


func _void(img: Image, rng: RandomNumberGenerator, c1: Color, c2: Color) -> void:
	var n := _noise(rng, 0.15)
	var sh := [c1.darkened(0.3), c1, c2, c2.lightened(0.1)]
	for y in TILE:
		for x in TILE:
			img.set_pixel(x, y, _pick(sh, n.get_noise_2d(x, y)))
	for i in 7:
		var c := Color.WHITE if rng.randf() < 0.5 else Color("b48cff")
		img.set_pixel(rng.randi_range(0, TILE - 1), rng.randi_range(0, TILE - 1), c)
	var sx := rng.randi_range(3, TILE - 4)
	var sy := rng.randi_range(3, TILE - 4)
	img.set_pixel(sx, sy, Color.WHITE)
	for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		img.set_pixel(sx + o.x, sy + o.y, Color("8f7cff"))


func _grass_top(img: Image, rng: RandomNumberGenerator, c1: Color, c2: Color) -> void:
	var n := _noise(rng, 0.2)
	var sh := [c1.darkened(0.18), c1.darkened(0.06), c1, c2]
	for y in TILE:
		for x in TILE:
			img.set_pixel(x, y, _pick(sh, n.get_noise_2d(x, y) + rng.randf_range(-0.35, 0.35)))
	# little blades: bright tip with a dark root
	for i in 14:
		var px := rng.randi_range(0, TILE - 1)
		var py := rng.randi_range(0, TILE - 2)
		img.set_pixel(px, py, c2.lightened(0.2))
		img.set_pixel(px, py + 1, c1.darkened(0.25))


func _snow(img: Image, rng: RandomNumberGenerator, c1: Color, c2: Color) -> void:
	var n := _noise(rng, 0.15)
	for y in TILE:
		for x in TILE:
			var v := n.get_noise_2d(x, y)
			img.set_pixel(x, y, c2 if v < -0.3 else (c1 if v < 0.4 else c1.lightened(0.5)))
	for i in 4:
		img.set_pixel(rng.randi_range(0, TILE - 1), rng.randi_range(0, TILE - 1), Color.WHITE)


## Grass/snow hanging over the top edge of a side face.
func _fringe(img: Image, rng: RandomNumberGenerator, c: Color, min_d: int, max_d: int) -> void:
	var depth := rng.randi_range(min_d, max_d)
	for x in TILE:
		if rng.randf() < 0.35:
			depth = clampi(depth + (1 if rng.randf() < 0.5 else -1), min_d, max_d)
		for y in depth:
			var col := c
			if y == 0:
				col = c.lightened(0.15)
			elif y == depth - 1:
				col = c.darkened(0.2)
			img.set_pixel(x, y, col)


## Ore veins grown into the rock. Each vein is an irregular blob that keeps the rock's own
## light/dark variation and seams, so the ore looks like part of the block, not a sticker.
func _ore(img: Image, rng: RandomNumberGenerator, oc: Color, rank: int, host: Color) -> void:
	var treasure := rank == 5
	var count := 1 if treasure else (4 if rank == 0 else 3)
	var base_lum := maxf(host.get_luminance(), 0.05)
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var centers: Array[Vector2i] = []
	var mask := {}
	for i in count:
		var c := Vector2i(7, 7) if treasure else Vector2i(rng.randi_range(2, TILE - 3), rng.randi_range(2, TILE - 3))
		for tries in 12:
			var ok := true
			for o in centers:
				if (o - c).length() < 6.0:
					ok = false
			if ok:
				break
			c = Vector2i(rng.randi_range(2, TILE - 3), rng.randi_range(2, TILE - 3))
		centers.append(c)
		var blob: Array[Vector2i] = [c]
		mask[c] = true
		var size := rng.randi_range(26, 32) if treasure else rng.randi_range(8, 12)
		var reach := 3.6 if treasure else 2.3
		var guard := 0
		while blob.size() < size and guard < 200:
			guard += 1
			var from: Vector2i = blob[rng.randi_range(0, blob.size() - 1)]
			var q: Vector2i = from + dirs[rng.randi_range(0, 3)]
			if q.x < 1 or q.y < 1 or q.x > TILE - 2 or q.y > TILE - 2 or mask.has(q):
				continue
			if Vector2(q - c).length() > reach + rng.randf() * 0.8:
				continue  # keep veins chunky, not stringy
			mask[q] = true
			blob.append(q)
	var orig := img.duplicate()
	for p in mask:
		var h: Color = orig.get_pixel(p.x, p.y)
		var k := clampf(h.get_luminance() / base_lum, 0.65, 1.3)
		var c := Color(oc.r * k, oc.g * k, oc.b * k)
		if h.get_luminance() < base_lum * 0.7:
			c = oc.darkened(0.4).lerp(h, 0.45)       # rock seam running through the ore
		var top_open: bool = not mask.has(p + Vector2i(0, -1)) or not mask.has(p + Vector2i(-1, 0))
		var bottom_open: bool = not mask.has(p + Vector2i(0, 1)) or not mask.has(p + Vector2i(1, 0))
		if top_open:
			c = c.lightened(0.15)
		elif bottom_open:
			c = c.darkened(0.2)
		if top_open or bottom_open:
			c = c.lerp(h, 0.2)                        # edges blend into the stone
		img.set_pixel(p.x, p.y, c)
	# soft shadow under/right of the veins
	for p in mask:
		for o in [Vector2i(1, 0), Vector2i(0, 1)]:
			var q: Vector2i = p + o
			if not mask.has(q) and q.x < TILE and q.y < TILE:
				img.set_pixel(q.x, q.y, orig.get_pixel(q.x, q.y).darkened(0.15))
	# a few glints
	var glints := 4 if treasure else count
	var keys := mask.keys()
	for i in glints:
		var g: Vector2i = keys[rng.randi_range(0, keys.size() - 1)]
		img.set_pixel(g.x, g.y, oc.lightened(0.55))


## Bedrock: chaotic dark greys with light flecks, unmistakably "you can't break this".
func _bedrock(img: Image, rng: RandomNumberGenerator, c1: Color, c2: Color) -> void:
	var sh := [c1.darkened(0.4), c1, c2, c2.lightened(0.25)]
	for y in TILE:
		for x in TILE:
			var r := rng.randf()
			img.set_pixel(x, y, sh[0] if r < 0.3 else (sh[1] if r < 0.6 else (sh[2] if r < 0.88 else sh[3])))
	for i in 6:
		var px := rng.randi_range(0, TILE - 2)
		var py := rng.randi_range(0, TILE - 2)
		img.set_pixel(px, py, Color("8a8a90"))
		img.set_pixel(px + 1, py + 1, Color("101012"))


## Bomb cache: a reinforced crate with gold corners and a bomb symbol.
func _cache(img: Image, rng: RandomNumberGenerator, wood: Color, gold: Color) -> void:
	for y in TILE:
		for x in TILE:
			var plank := wood if (y / 4) % 2 == 0 else wood.darkened(0.12)
			if y % 4 == 3:
				plank = wood.darkened(0.35)
			img.set_pixel(x, y, plank)
	for i in TILE:
		for t in 2:
			img.set_pixel(i, t, Color("3a3a40"))
			img.set_pixel(i, TILE - 1 - t, Color("3a3a40"))
			img.set_pixel(t, i, Color("3a3a40"))
			img.set_pixel(TILE - 1 - t, i, Color("3a3a40"))
	for c in [Vector2i(0, 0), Vector2i(TILE - 3, 0), Vector2i(0, TILE - 3), Vector2i(TILE - 3, TILE - 3)]:
		for y in 3:
			for x in 3:
				img.set_pixel(c.x + x, c.y + y, gold if (x + y) % 2 == 0 else gold.darkened(0.3))
	# bomb symbol
	var bomb := [
		"....yo..",
		"...b....",
		"..kkkk..",
		".kddddk.",
		".kdwddk.",
		".kddddk.",
		"..kkkk..",
	]
	var pal := {"k": Color("120e0b"), "d": Color("2b2b30"), "w": Color("8a8a90"), "b": Color("6b4a2e"), "y": gold, "o": Color("ff8a1f")}
	for y in bomb.size():
		for x in bomb[y].length():
			var ch: String = bomb[y][x]
			if pal.has(ch):
				img.set_pixel(4 + x, 4 + y, pal[ch])


## Every block: light top-left edge, darker bottom-right edge, so blocks read as separate cubes.
func _bevel(img: Image) -> void:
	for i in TILE:
		img.set_pixel(i, 0, img.get_pixel(i, 0).lightened(0.08))
		img.set_pixel(0, i, img.get_pixel(0, i).lightened(0.05))
		img.set_pixel(i, TILE - 1, img.get_pixel(i, TILE - 1).darkened(0.22))
		img.set_pixel(TILE - 1, i, img.get_pixel(TILE - 1, i).darkened(0.16))
