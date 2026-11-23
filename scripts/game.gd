extends Node3D
## Blast Pillar — main game script.
## Owns the game state (coins, ores, upgrades, worlds), the camera, bombs, saving and offline income.

const Data = preload("res://scripts/data.gd")
const Blocks = preload("res://scripts/blocks.gd")
const PillarScript = preload("res://scripts/pillar.gd")
const BombScript = preload("res://scripts/bomb.gd")
const FxScript = preload("res://scripts/fx.gd")
const GemScript = preload("res://scripts/gem.gd")
const SfxScript = preload("res://scripts/sfx.gd")
const LoadingScript = preload("res://scripts/loading.gd")
const UIScript = preload("res://scripts/ui.gd")

const SAVE_PATH := "user://blast_pillar_save.json"
const MAX_BOMBS := 30
const MAX_GEMS := 30
const AUTO_MAX := 20
const OFFLINE_CAP := 8.0 * 3600.0
const IDLE_EFFICIENCY := 0.5
const TAP_REPEAT := 0.28

# ---- saved state ----
var coins := 0.0
var total_coins := 0.0
var levels := {}
var ores := {}
var ores_seen := {}
var current_world := 0
var unlocked_worlds := 1
var worlds: Array = []
var specials := {}
var relics := {}                 # relic id -> true (found in the vaults of Worlds 7-11)
var rebirths := 0                # how many times you've reborn (kept through rebirths)
var rebirth_ready := false       # the Star Core was broken this run, so you can rebirth
var just_reborn := false         # show the "you reborn" popup once the game has loaded
var storm_count := 0             # Storm Battery: counts normal bombs dropped
var cooldowns := {}
var sound_on := true
var vibrate_on := true
var show_stats := false
var loading_screen: Node = null
var loading_open := false        # the loading / START screen is up (notifications wait for it)
var reduce_flash := false        # settings: no full-screen flashes, softer tints, no camera shake
## Lifetime numbers for the STATS page. Kept through rebirths.
var stats := {}
var hints_seen := {}             # first-time guide notes already shown
var hide_early_worlds := false   # WORLDS tab: Worlds 1-5 folded away
var _prof := {}                # this frame: section -> microseconds
var last_hitch := ""           # breakdown of the last frame that took over 100 ms

# ---- runtime ----
var blocks
var ore_table := {}
var pillar
var fx
var sfx
var ui
var camera: Camera3D
var env: Environment
var bg_rect: TextureRect
var bombs_node: Node3D
var gems_node: Node3D
var vp_size := Vector2(720, 1280)
var top_inset := 0.0
var bottom_inset := 0.0
var cam_focus := Vector3.ZERO
var shake := 0.0
var holding := false
var hold_timer := 0.0
var auto_accum := 0.0
var bg_timer := 0.0
var bg_acc := {}
var save_timer := 0.0
var ui_timer := 0.0
var pause_unix := 0.0
var portal_open := false
var world_token := 0
var model_cache := {}
var shape_scale := {}          # ore shape -> size multiplier so every shape LOOKS the same size
var model_icons := {}
var icon_index := {}           # saved icon cache: key -> signature (so we know if a model changed)
var model_icon_frames := {}    # "bombs/acid" -> Array[Image] (spin loop)          # "bombs/cluster", "ores/ruby", "world/0" -> Image (ICON_RES px)
const ICON_RES := 28           # world icons
const MODEL_ICON_RES := 56     # bomb and ore icons (double detail)
const ICON_FRAMES := 24        # frames in a spinning icon loop (one full turn + one bob)
const ICON_FPS := 8.0          # how fast icons spin: 24 frames / 8 fps = one turn every 3s
const ICON_BOB := 0.06         # how far icons float up and down
const ICON_CACHE_DIR := "user://icon_cache"
const ICON_CACHE_VERSION := 2  # bump to force all icons to be rebuilt
var mat_cache := {}


# =============================================================================================
# Setup
# =============================================================================================

func _ready() -> void:
	randomize()
	_compute_layout()
	blocks = Blocks.new()
	ore_table = Data.build_ore_table()
	_build_scene()
	for w in Data.WORLDS.size():
		worlds.append(_new_world_entry())
	var offline_seconds := load_game()
	var loading = null
	loading_open = DisplayServer.get_name() != "headless" and not quick_restart
	quick_restart = false
	if loading_open:
		loading = LoadingScript.new()     # bombs spinning in a checkerboard while it loads
		loading_screen = loading
		add_child(loading)
		loading.setup(self)
	_load_world(current_world)
	await _render_icons()
	if loading:
		loading.fill_icons()
	var layer := CanvasLayer.new()
	add_child(layer)
	ui = UIScript.new()
	ui.game = self
	layer.add_child(ui)
	ui.build()
	_render_spin_icons()   # runs in the background; icons start spinning as they're ready
	ui.hint_label.visible = total_coins == 0.0
	ui.refresh()
	if offline_seconds > 0.0:
		grant_offline(offline_seconds)
	if just_reborn:
		just_reborn = false
		_reborn_popup()
	if loading:
		loading.finish()


func _compute_layout() -> void:
	vp_size = get_viewport().get_visible_rect().size
	if OS.has_feature("mobile"):
		var screen := DisplayServer.screen_get_size()
		var safe := DisplayServer.get_display_safe_area()
		if screen.y > 0:
			top_inset = float(safe.position.y) / float(screen.y) * vp_size.y
			bottom_inset = float(screen.y - safe.end.y) / float(screen.y) * vp_size.y


func _build_scene() -> void:
	env = Environment.new()
	# background = a gradient drawn on a canvas layer behind the 3D view (works on every renderer)
	env.background_mode = Environment.BG_CANVAS
	env.background_canvas_max_layer = -1
	var bg_layer := CanvasLayer.new()
	bg_layer.layer = -1
	add_child(bg_layer)
	bg_rect = TextureRect.new()
	bg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_rect.stretch_mode = TextureRect.STRETCH_SCALE
	bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_layer.add_child(bg_rect)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.8, 0.8)
	env.ambient_light_energy = 0.7
	env.fog_enabled = true
	env.fog_density = 0.012
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# light only matters for your Blockbench models; the pillar is unshaded
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 35, 0)
	sun.light_energy = 0.9
	add_child(sun)

	camera = Camera3D.new()
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.fov = 52.0
	camera.far = 300.0
	add_child(camera)

	pillar = PillarScript.new()
	pillar.setup(blocks)
	add_child(pillar)
	bombs_node = Node3D.new()
	add_child(bombs_node)
	gems_node = Node3D.new()
	add_child(gems_node)
	fx = FxScript.new()
	add_child(fx)
	sfx = SfxScript.new()
	add_child(sfx)
	sfx.enabled = sound_on


func _new_world_entry() -> Dictionary:
	return {"seed": randi(), "state": {}, "auto": 0, "done": false, "depth": 0.0,
		"ema_coins": 0.0, "ema_ores": {}}


# =============================================================================================
# Worlds
# =============================================================================================

func _load_world(w: int) -> void:
	world_token += 1
	current_world = w
	cam_hold_y = INF
	for b in bombs_node.get_children():
		b.queue_free()
	for g in gems_node.get_children():
		g.queue_free()
	fx.clear_all()
	_scale_realm(w)
	pillar.hp_mult = hp_scale(w)
	var entry: Dictionary = worlds[w]
	var st: Dictionary = entry.get("state", {})
	if st.is_empty() or not pillar.load_state(w, st, int(entry["seed"])):
		pillar.generate(w, int(entry["seed"]))
	pillar.rebuild_all()
	portal_open = pillar.reached_bedrock()
	_update_portal()
	auto_accum = 0.0
	var world: Dictionary = Data.WORLDS[w]
	var grad := Gradient.new()
	grad.set_color(0, Color.html(world["sky_top"]))
	grad.set_color(1, Color.html(world["fog"]))
	grad.add_point(0.38, Color.html(world["sky_horizon"]))
	grad.add_point(0.62, Color.html(world["fog"]).lightened(0.12))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 256
	bg_rect.texture = gt
	env.fog_light_color = Color.html(world["fog"])
	cam_focus = _focus_target()
	_update_camera(0.0, true)


func travel(w: int) -> void:
	if w == current_world or w >= unlocked_worlds:
		return
	worlds[current_world]["state"] = pillar.get_state()
	worlds[current_world]["depth"] = pillar.floor_depth()
	_refund_falling_bedrock_bombs()
	sfx.play("portal")
	_load_world(w)
	save_game()
	ui.rebuild_tab()
	ui.refresh()


## Leaving a world while a Bedrock Bomb is still falling gives you its Cosmic Eggs back.
func _refund_falling_bedrock_bombs() -> void:
	for b in bombs_node.get_children():
		if b.get("kind") == "bedrock" and not b.get("exploded"):
			ores[Data.BEDROCK_BOMB_ORE] = int(ores.get(Data.BEDROCK_BOMB_ORE, 0)) + Data.bedrock_cost(current_world)


## Regrow a fresh pillar in a world you've already broken through.
func reset_world(w: int) -> void:
	if not worlds[w].get("done", false):
		return
	worlds[w]["seed"] = randi()
	worlds[w]["state"] = {}
	worlds[w]["depth"] = 0.0
	worlds[w].erase("bedrock_broken")
	worlds[w]["empty"] = false
	if w == current_world:
		_refund_falling_bedrock_bombs()
		_load_world(w)
	sfx.play("portal", 0.8)
	save_game()
	ui.rebuild_tab()
	ui.refresh()


## The portal: an upright swirling doorway standing on the bedrock against the back wall.
const PORTAL_W := 1.0
const PORTAL_H := 1.5
var portal_node: Node3D

func _update_portal() -> void:
	if portal_node:
		portal_node.queue_free()
		portal_node = null
	if not portal_open:
		return
	portal_node = Node3D.new()
	add_child(portal_node)
	var back: float = -pillar.half_width()
	portal_node.position = Vector3(0, -pillar.depth * Data.VOXEL, back)
	# obsidian frame: 4 blocks wide, 5 tall, 2x3 opening (same block size and style as the pillar)
	var cells: Array[Vector3i] = []
	for y in 5:
		for x in 4:
			if (x == 0 or x == 3 or y == 0 or y == 4):
				cells.append(Vector3i(x - 2, y, 0))
	var frame := MeshInstance3D.new()
	frame.mesh = _voxel_mesh(cells, blocks.index_of("portal_frame"), Data.VOXEL)
	frame.material_override = pillar.material
	frame.position = Vector3(0, 0, 0)
	portal_node.add_child(frame)
	var quad := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(PORTAL_W, PORTAL_H)
	quad.mesh = qm
	quad.position = Vector3(0, Data.VOXEL + PORTAL_H * 0.5, Data.VOXEL * 0.5)
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform bool locked = false;
void fragment() {
	vec2 uv = floor(UV * vec2(16.0, 24.0)) / vec2(16.0, 24.0) - 0.5;
	uv.y *= 1.5;
	float a = atan(uv.y, uv.x);
	float r = length(uv);
	float swirl = sin(a * 3.0 + r * 18.0 - TIME * (locked ? 0.8 : 4.0)) * 0.5 + 0.5;
	vec3 c = mix(vec3(0.3, 0.08, 0.6), vec3(0.65, 0.3, 1.0), step(0.5, swirl));
	c = mix(c, vec3(0.9, 0.75, 1.0), step(r, 0.12) * 0.6);
	if (locked) {
		c = mix(vec3(dot(c, vec3(0.33))), c, 0.3) * 0.55;   // sealed: dull, slow and grey
	}
	ALBEDO = c;
}
"""
	var qmat := ShaderMaterial.new()
	qmat.shader = sh
	qmat.set_shader_parameter("locked", portal_locked())
	quad.material_override = qmat
	portal_node.add_child(quad)
	if portal_locked():
		portal_node.add_child(_portal_lock())


## The next world is sealed until you find the hidden bomb it needs.
func portal_locked() -> bool:
	var nxt := current_world + 1
	return nxt < Data.WORLDS.size() and nxt >= unlocked_worlds


## Two iron chains crossed over the opening with a gold padlock in the middle.
func _portal_lock() -> Node3D:
	var lock := Node3D.new()
	var z := Data.VOXEL * 0.5 + 0.06
	var cy := Data.VOXEL + PORTAL_H * 0.5
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color("6a6f78")
	iron.metallic = 0.6
	iron.roughness = 0.45
	var iron_dark := StandardMaterial3D.new()
	iron_dark.albedo_color = Color("3c4048")
	iron_dark.metallic = 0.6
	iron_dark.roughness = 0.5
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color("e8b83a")
	gold.metallic = 0.7
	gold.roughness = 0.3
	var hole := StandardMaterial3D.new()
	hole.albedo_color = Color("1a1208")
	var half := Vector2(PORTAL_W * 0.5 + Data.VOXEL * 0.6, PORTAL_H * 0.5 + Data.VOXEL * 0.6)
	for side in [-1.0, 1.0]:
		var a := Vector3(-half.x * side, cy - half.y, z)
		var b := Vector3(half.x * side, cy + half.y, z)
		var links := 13
		for i in links:
			var t := (i + 0.5) / links
			var link := MeshInstance3D.new()
			var bm := BoxMesh.new()
			var flat := i % 2 == 0
			bm.size = Vector3(0.2, 0.09, 0.03) if flat else Vector3(0.2, 0.03, 0.09)
			link.mesh = bm
			link.material_override = iron if flat else iron_dark
			link.position = a.lerp(b, t) + Vector3(0, 0, 0.02 * side)
			link.rotation.z = atan2(b.y - a.y, b.x - a.x)
			lock.add_child(link)
	var body := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(0.34, 0.28, 0.1)
	body.mesh = bb
	body.material_override = gold
	body.position = Vector3(0, cy - 0.06, z + 0.07)
	lock.add_child(body)
	for p in [[Vector3(-0.1, cy + 0.15, z + 0.07), Vector3(0.05, 0.16, 0.05)],
			[Vector3(0.1, cy + 0.15, z + 0.07), Vector3(0.05, 0.16, 0.05)],
			[Vector3(0, cy + 0.235, z + 0.07), Vector3(0.25, 0.05, 0.05)]]:
		var s := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = p[1]
		s.mesh = sm
		s.material_override = iron
		s.position = p[0]
		lock.add_child(s)
	var key := MeshInstance3D.new()
	var km := BoxMesh.new()
	km.size = Vector3(0.05, 0.1, 0.02)
	key.mesh = km
	key.material_override = hole
	key.position = Vector3(0, cy - 0.08, z + 0.125)
	lock.add_child(key)
	return lock


## A mesh of whole blocks (pillar-style faces and shading) at integer cells; cell (0,0,0) spans
## 0..size on every axis. Faces between two cells are skipped.
func _voxel_mesh(cells: Array[Vector3i], block: int, size: float) -> ArrayMesh:
	var filled := {}
	for c in cells:
		filled[c] = true
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var inds := PackedInt32Array()
	for c in cells:
		var base := Vector3(c) * size
		for f in 6:
			# FDD is "down" in pillar layers, so flip it for world-space y
			var n := Vector3i(c.x + PillarScript.FDX[f], c.y - PillarScript.FDD[f], c.z + PillarScript.FDZ[f])
			if filled.has(n):
				continue
			var r: Rect2 = blocks.uv(block, f >= 2, 0)
			var sh: float = PillarScript.FACE_SHADE[f]
			var start := verts.size()
			var corners: Array = PillarScript.FACE_CORNERS[f]
			for k in 4:
				verts.append(base + corners[k] * size)
				cols.append(Color(sh, sh, sh))
			uvs.append(r.position)
			uvs.append(Vector2(r.end.x, r.position.y))
			uvs.append(r.end)
			uvs.append(Vector2(r.position.x, r.end.y))
			for k in [0, 1, 2, 0, 2, 3]:
				inds.append(start + k)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = inds
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func world_depth(w: int) -> float:
	if w == current_world:
		return pillar.floor_depth()
	return float(worlds[w].get("depth", 0.0))


func _check_progress() -> void:
	if pillar.update_cut():
		pass
	if not portal_open and pillar.reached_bedrock():
		portal_open = true
		_update_portal()
		var first_time: bool = not worlds[current_world]["done"]
		worlds[current_world]["done"] = true
		stat("bottoms")
		sfx.play("portal", 1.0, 0.0, 0.5)
		if not first_time:
			return
		var w := current_world
		_try_unlock()
		if w + 1 < Data.WORLDS.size() and unlocked_worlds <= w + 1:
			# the next world is a realm whose door needs a hidden bomb you don't have yet
			var need := world_needs(w + 1)
			var home := special_home(need)
			ui.notify("YOU HIT BEDROCK!",
				"The portal to [color=#ffcf5a]%s[/color] is sealed. Find the [color=#b46bff]%s[/color] under the bedrock of %s to open it." % [Data.WORLDS[w + 1]["name"], special_name(need), Data.WORLDS[home]["name"]],
				ui.world_icon(w, 3), ["world", str(w)], Callable(), 7.0)
		elif w + 1 < Data.WORLDS.size():
			var next_name: String = Data.WORLDS[w + 1]["name"]
			ui.notify("YOU HIT BEDROCK!",
				"A portal to [color=#ffcf5a]%s[/color] opened! [color=#9be36b]Tap here to go through.[/color]" % next_name,
				ui.world_icon(w + 1, 3), ["world", str(w + 1)], func(): travel(w + 1), 8.0)
		else:
			ui.notify("YOU CONQUERED IT ALL!", "Every pillar in every world is blasted down to bedrock. Legendary!",
				ui.micon("bombs", "mega", "mega", 3), ["bombs", "mega"], Callable(), 7.0)
		ui.rebuild_tab()
		save_game()


# =============================================================================================
# Upgrades & economy
# =============================================================================================

func lvl(id: String) -> int:
	return int(levels.get(id, 0))

func blast_radius() -> float:
	return (1.0 + 0.1 * lvl("radius")) * range_mult()

## Gale Lens relic: every bomb reaches farther (normal blasts and the fixed-size specials alike).
func range_mult() -> float:
	return Data.RANGE_RELIC_MULT if has_relic("gale_lens") else 1.0

## Bomb damage. The rebirth multiplier only counts in Worlds 1-6; the Deep Realms ignore it.
func bomb_power() -> float:
	var p := base_bomb_power()
	if not is_realm(current_world):
		p *= rebirth_mult()
	return p

## Bomb damage without the rebirth multiplier (upgrades and relics only).
func base_bomb_power() -> float:
	var p := 2.5 * pow(1.28, lvl("power"))
	if has_relic("golden_bomb"):
		p *= Data.GOLDEN_RELIC_MULT
	return p

## Rebirth damage: x10 after 1 rebirth, x20 after 2, x30 after 3...
func rebirth_mult() -> float:
	return maxf(1.0, Data.REBIRTH_MULT * rebirths)

func has_relic(id: String) -> bool:
	return relics.has(id)

func bombs_per_tap() -> int:
	return 1 + lvl("multi")

func fuse_time() -> float:
	return 1.4 * pow(0.82, lvl("fuse"))

func value_mult() -> float:
	return pow(1.2, lvl("value"))

func auto_rate(w: int) -> float:
	return 0.25 * int(worlds[w]["auto"])

## Rebirth coin boost: x2 after 1 rebirth, x3 after 2, x4 after 3... in every world.
func rebirth_coin_mult() -> float:
	return 1.0 + rebirths

func ore_value(oid: String) -> float:
	if oid == Data.BEDROCK_BOMB_ORE:
		return 0.0   # Cosmic Eggs pay out in Bedrock Bombs, not coins
	var v := float(ore_table[oid]["value"]) * value_mult() * coin_scale(int(ore_table[oid]["world"])) * rebirth_coin_mult()
	return v * (Data.ORE_RELIC_MULT if has_relic("pearl_of_plenty") else 1.0)


# ---- The Deep Realms (worlds 7+) -------------------------------------------------------------
## How much tougher a realm is than its base numbers, relative to your bombs when you first enter.
## Tuned so that walking into a realm feels like starting Grasslands on day one.
const REALM_TOUGHNESS := 0.3
## Coins per block in a realm are scaled so your cheapest upgrade costs about as many blocks as
## it did on day one in Grasslands.
const REALM_COINS := 1.0
## Specials that ignore toughness (acid, freeze, magnet, black hole...) reach this much less far
## in the realms, so they don't trivialise them.
const REALM_REACH := 0.6

func is_realm(w: int) -> bool:
	return bool(Data.WORLDS[w].get("realm", false))

func hp_scale(w: int) -> float:
	if w < 0 or w >= worlds.size():
		return 1.0
	return float(worlds[w].get("hp_scale", 1.0))

func coin_scale(w: int) -> float:
	if w < 0 or w >= worlds.size():
		return 1.0
	return float(worlds[w].get("coin_scale", 1.0))

func reach() -> float:
	return (REALM_REACH if is_realm(current_world) else 1.0) * range_mult()

## Fix a realm's toughness and coin values the first time you step into it.
func _scale_realm(w: int) -> void:
	if not is_realm(w) or worlds[w].has("hp_scale"):
		return
	var r := minf(blast_radius(), 3.0)
	# rebirth damage doesn't count in the realms, so it isn't counted here either
	worlds[w]["hp_scale"] = maxf(1.0, base_bomb_power() / 2.5 * float(bombs_per_tap()) * r * r * REALM_TOUGHNESS)
	worlds[w]["realm_t"] = REALM_TOUGHNESS
	# your cheapest upgrade should cost about as many blocks as it did on day one in Grasslands
	var ref := INF
	for u in Data.UPGRADES:
		if not upgrade_maxed(u):
			ref = minf(ref, upgrade_cost(u) / float(u["base"]))
	if ref == INF:
		ref = 1.0
	worlds[w]["coin_scale"] = maxf(1.0, ref / value_mult() * REALM_COINS)

## The hidden bomb a world needs before it opens ("" = none).
func world_needs(w: int) -> String:
	return str(Data.WORLDS[w].get("needs", ""))

func special_name(id: String) -> String:
	for sp in Data.SPECIALS:
		if sp["id"] == id:
			return sp["name"]
	return id

## Where a hidden bomb is found (world index), or -1.
func special_home(id: String) -> int:
	for sp in Data.SPECIALS:
		if sp["id"] == id:
			return int(sp.get("find", -1))
	return -1

## Open every world whose door is ready: the world before it is done and its bomb is found.
## Returns the worlds that just opened.
func _try_unlock() -> Array:
	var opened: Array = []
	while unlocked_worlds < Data.WORLDS.size():
		var nxt := unlocked_worlds
		if not bool(worlds[nxt - 1].get("done", false)):
			break
		var need := world_needs(nxt)
		if need != "" and not specials.has(need):
			break
		unlocked_worlds += 1
		opened.append(nxt)
	if not opened.is_empty() and portal_node:
		_update_portal()   # this world's portal may have just been unlocked
	return opened

func upgrade_effect(id: String) -> String:
	match id:
		"radius": return "%.1fm blast" % blast_radius()
		"power":
			var extra := ""
			if rebirths > 0:
				extra += ("  rebirth x%s" % fmt(rebirth_mult())) if not is_realm(current_world) else "  (no rebirth bonus here)"
			if has_relic("golden_bomb"):
				extra += "  golden x%.1f" % Data.GOLDEN_RELIC_MULT
			return "%s power%s" % [fmt(bomb_power()), extra]
		"multi": return ("%d bombs per tap" if bombs_per_tap() > 1 else "%d bomb per tap") % bombs_per_tap()
		"fuse": return "%.2fs fuse" % fuse_time()
		"value": return ("x%s ore coins" % fmt(value_mult())) + ("  rebirth x%d" % int(rebirth_coin_mult()) if rebirths > 0 else "")
	return ""

func upgrade_cost(u: Dictionary) -> float:
	return float(u["base"]) * pow(float(u["growth"]), lvl(u["id"]))

func upgrade_maxed(u: Dictionary) -> bool:
	return int(u["max"]) >= 0 and lvl(u["id"]) >= int(u["max"])

func auto_cost(w: int) -> Dictionary:
	var base: Dictionary = Data.WORLDS[w]["auto_cost"]
	var l := int(worlds[w]["auto"])
	if l == 0:
		if coin_scale(w) == 1.0:
			return base
		var scaled := base.duplicate()
		scaled["coins"] = float(base["coins"]) * coin_scale(w)
		return scaled
	return {"coins": float(base["coins"]) * coin_scale(w) * pow(1.75, l)}

func can_afford(cost: Dictionary) -> bool:
	for k in cost:
		if k == "coins":
			if coins < float(cost[k]):
				return false
		elif int(ores.get(k, 0)) < int(cost[k]):
			return false
	return true

func _pay(cost: Dictionary) -> void:
	for k in cost:
		if k == "coins":
			coins -= float(cost[k])
		else:
			ores[k] = int(ores.get(k, 0)) - int(cost[k])

func add_coins(amount: float) -> void:
	coins += amount
	total_coins += amount
	stat("coins", amount)

func buy_upgrade(id: String) -> void:
	var u: Dictionary = {}
	for x in Data.UPGRADES:
		if x["id"] == id:
			u = x
	if u.is_empty() or upgrade_maxed(u) or coins < upgrade_cost(u):
		sfx.play("error")
		return
	coins -= upgrade_cost(u)
	levels[id] = lvl(id) + 1
	sfx.play("buy")
	_vibrate(15)
	ui.refresh()

func buy_auto() -> void:
	var w := current_world
	if int(worlds[w]["auto"]) >= AUTO_MAX:
		return
	var cost := auto_cost(w)
	if not can_afford(cost):
		sfx.play("error")
		return
	_pay(cost)
	worlds[w]["auto"] = int(worlds[w]["auto"]) + 1
	sfx.play("unlock" if int(worlds[w]["auto"]) == 1 else "buy")
	_vibrate(15)
	ui.refresh()

func special_level(id: String) -> int:
	return mini(int(specials.get(id, 0)), Data.SPECIAL_MAX_LEVEL)


func special_cooldown(id: String) -> float:
	return special_cooldown_at(id, special_level(id))


func special_cooldown_at(id: String, level: int) -> float:
	var sp: Dictionary = Data.get_special(id)
	var base := float(sp["cooldown"])
	var lowest := float(sp.get("min_cooldown", base * Data.SPECIAL_MIN_FRACTION))
	var t := clampf(level / float(Data.SPECIAL_MAX_LEVEL), 0.0, 1.0)
	return lerpf(base, lowest, t) * (Data.RELOAD_RELIC_MULT if has_relic("clockwork_gear") else 1.0)


func special_upgrade_cost(id: String) -> float:
	var base := float(Data.get_special(id)["cost"].get("coins", 100.0))
	return base * 0.6 * pow(1.8, special_level(id))


func upgrade_special(id: String) -> void:
	if not specials.has(id) or special_level(id) >= Data.SPECIAL_MAX_LEVEL:
		return
	var cost := special_upgrade_cost(id)
	if coins < cost:
		sfx.play("error")
		return
	coins -= cost
	specials[id] = special_level(id) + 1
	cooldowns[id] = minf(float(cooldowns.get(id, 0.0)), special_cooldown(id))
	sfx.play("buy")
	_vibrate(15)
	ui.refresh()


## Tell the player (once) when they can afford a bomb they haven't bought yet.
var afford_timer := 1.0
var afford_told := {}

func _check_new_bombs() -> void:
	for sp in Data.SPECIALS:
		var id: String = sp["id"]
		if sp.has("find") or sp.has("rebirth") or specials.has(id) or afford_told.has(id):
			continue
		var cost: Dictionary = sp.get("cost", {})
		if cost.is_empty() or not can_afford(cost):
			continue
		afford_told[id] = true
		sfx.play("gem_rare", 1.2, -4.0)
		ui.notify("NEW BOMB AVAILABLE!", "You can unlock the [color=#b46bff]%s[/color]. [color=#9be36b]Tap to open BOMBS.[/color]" % sp["name"],
			ui.micon("bombs", id, id, 3), ["bombs", id], func(): ui.switch_tab("bombs"), 6.0)


func unlock_special(id: String) -> void:
	var s := Data.get_special(id)
	if s.is_empty() or specials.has(id) or s.has("find") or s.has("rebirth"):
		return
	if not can_afford(s["cost"]):
		sfx.play("error")
		return
	_pay(s["cost"])
	specials[id] = 0
	cooldowns[id] = 0.0
	sfx.play("unlock")
	_vibrate(25)
	ui.rebuild_tab()

func fire_special(id: String) -> void:
	if not specials.has(id) or float(cooldowns.get(id, 0.0)) > 0.0 or ui.popup_open():
		sfx.play("error")
		return
	if id == "mirror":
		if mirror_copy == "":
			sfx.play("error")
			return
		mirror_payload = mirror_copy
		mirror_copy = ""
	stat("specials")
	hint("special_used")
	# the Mirror Bomb reloads as long as the bomb it just copied does
	cooldowns[id] = special_cooldown(mirror_payload if id == "mirror" else id)
	if id in MIRRORABLE:
		mirror_copy = id
	if id == "sticky":
		_sticky_rain()
		sfx.play("drop", 1.3)
		ui.refresh()
		return
	if id == "moon":
		_moon_strike()
		ui.refresh()
		return
	_spawn_bomb(id, _spawn_point(0.6))
	sfx.play("drop", 0.8)
	ui.refresh()

## Buy/sell ores one at a time. Both use the same price: what the ore earns when you mine it.
## Cosmic Eggs are dug up, never bought or sold.
func ore_tradable(oid: String) -> bool:
	return oid != Data.BEDROCK_BOMB_ORE


## Dug up Cosmic Egg(s) (already added to your ores): a flash, fireworks where it was, chimes, a
## buzz, and a glowing notification saying how close you are to the next Bedrock Bomb.
func _eggs_found(n: int, where: Vector3) -> void:
	var eid: String = Data.BEDROCK_BOMB_ORE
	stat("eggs", n)
	var have := int(ores.get(eid, 0))
	var egg_col: Color = ore_table[eid]["color"]
	ui.flash(Color(egg_col.r, egg_col.g, egg_col.b, 0.4), 0.5)
	fx.explosion(where, 1.6, egg_col)
	fx.explosion(where, 1.0, Color(1.0, 0.85, 0.3))
	fx.shockwave(where, 2.5, [egg_col, Color(1.0, 0.9, 0.5), Color.WHITE])
	shake = maxf(shake, 0.35)
	_vibrate(90)
	sfx.play("unlock", 1.2, 0.0)
	sfx.play("gem_rare", 0.8, 0.0)
	var body := "You have [color=#ffcf5a]%d[/color]. " % have
	var nb := next_bedrock_world()
	if nb >= 0:
		var cost := Data.bedrock_cost(nb)
		if have >= cost:
			body += "That's enough to break the bedrock of [color=#ffcf5a]%s[/color]! [color=#9be36b]Tap to open BOMBS.[/color]" % Data.WORLDS[nb]["name"]
		else:
			body += "[color=#ffcf5a]%d[/color] more to break the bedrock of %s." % [cost - have, Data.WORLDS[nb]["name"]]
	ui.notify("COSMIC EGG!" if n == 1 else "%d COSMIC EGGS!" % n, body, ui.micon("ores", eid, "gem", 4, egg_col), ["ores", eid],
		func(): ui.switch_tab("bombs"), 6.0, true)
	save_game()


func buy_ore(oid: String) -> void:
	if not ore_tradable(oid):
		sfx.play("error")
		return
	var price := ore_value(oid)
	if coins < price:
		sfx.play("error")
		return
	coins -= price
	ores[oid] = int(ores.get(oid, 0)) + 1
	sfx.play("gem", 1.1, -4.0, 0.02)
	ui.refresh()


func sell_ore(oid: String) -> void:
	if int(ores.get(oid, 0)) <= 0 or not ore_tradable(oid):
		sfx.play("error")
		return
	ores[oid] = int(ores[oid]) - 1
	coins += ore_value(oid)
	sfx.play("click", 0.9)
	ui.refresh()


func set_sound(on: bool) -> void:
	sound_on = on
	sfx.enabled = on


# =============================================================================================
# Input & bombs
# =============================================================================================

func _unhandled_input(event: InputEvent) -> void:
	if ui == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if ui.popup_open():
				return
			holding = true
			hold_timer = TAP_REPEAT
			_tap_drop()
		else:
			holding = false


func _tap_drop() -> void:
	if grow_charging():
		_grow_tap()
		return
	if bombs_node.get_child_count() >= MAX_BOMBS:
		return
	for i in bombs_per_tap():
		_spawn_bomb("bomb", _spawn_point(1.0))
	stat("taps")
	stat("bombs", bombs_per_tap())
	sfx.play("drop", randf_range(0.95, 1.1), -4.0)
	_vibrate(8)
	if ui.hint_label.visible:
		ui.hint_label.visible = false


## Where a bomb appears: above the top of the pillar. Bombs lean towards the parts that
## are still standing, so the whole pillar gets blasted down, not just one deep shaft.
## spread < 1 keeps it nearer the middle (special bombs).
func _spawn_point(spread: float) -> Vector3:
	var lim: float = pillar.half_width() - 0.5
	var target: Vector3 = pillar.high_point(3)
	var x := target.x * spread + randf_range(-0.4, 0.4)
	var z := target.z * spread + randf_range(-0.4, 0.4)
	return Vector3(clampf(x, -lim, lim), pillar.top_y() + 7.0 + randf() * 1.5, clampf(z, -lim, lim))


func _spawn_bomb(kind: String, pos: Vector3, vel := Vector3(0, -3, 0), lit := -1.0) -> void:
	if bombs_node.get_child_count() >= MAX_BOMBS + 10:
		return
	if kind == "bomb" and has_relic("storm_battery"):
		# Storm Battery: every Nth normal bomb drops as a Mega Bomb (looks and blasts like one)
		storm_count += 1
		if storm_count % Data.STORM_EVERY == 0:
			kind = "mega"
	var __t := Time.get_ticks_usec()
	_spawn_bomb_now(kind, pos, vel, lit)
	prof("new bombs", __t)


func _spawn_bomb_now(kind: String, pos: Vector3, vel := Vector3(0, -3, 0), lit := -1.0) -> void:
	var b = BombScript.new()
	b.game = self
	b.kind = kind
	b.fuse = fuse_time() if kind != "mini" else 0.2
	if kind == "tnt":
		b.fuse = TNT_FUSE   # a TNT fuse always burns the same time, like in Minecraft
	b.position = pos
	b.linear_velocity = vel
	bombs_node.add_child(b)
	if lit >= 0.0:
		b.light(lit)


func on_bomb_explode(bomb) -> void:
	var kind: String = bomb.kind
	var k: Dictionary = Data.BOMB_KINDS.get(kind, Data.BOMB_KINDS["bomb"])
	var radius := blast_radius() * float(k["radius"])
	var power := bomb_power() * float(k["power"])
	var pos: Vector3 = bomb.global_position
	match kind:
		"drill":
			_blast(pos, maxf(radius * 1.6, 1.0), power, Color(0.85, 0.85, 0.9))
		"cluster":
			_blast(pos, radius, power, Color(1.0, 0.6, 0.2))
			# throw 6 bomblets in a ring onto the top of the pillar (they go off when they land)
			var lim: float = pillar.half_width() - 0.4
			var start := pos + Vector3(0, 0.5, 0)
			var flight := 0.6
			for i in 6:
				var a := TAU * i / 6.0 + randf_range(-0.3, 0.3)
				var dist := randf_range(1.2, 2.4)
				var target := Vector3(clampf(pos.x + cos(a) * dist, -lim, lim), pillar.top_y(), clampf(pos.z + sin(a) * dist, -lim, lim))
				var v := (target - start) / flight
				v.y = (target.y - start.y) / flight + 0.5 * 9.8 * flight
				_spawn_bomb("mini", start, v)
		"acid":
			_acid(pos)
		"mega", "sticky":
			_mega(pos)   # each Sticky Bomb slime ball blasts like a whole Mega Bomb
		"chain":
			_chain(pos, radius, power)
		"freeze":
			_freeze(pos, radius, power)
		"magnet":
			_magnet(pos)
		"mirror":
			_mirror(pos, radius, power)
		"blackhole":
			_black_hole(pos)
		"bedrock":
			_break_bedrock()
		"spore":
			_spore(pos, radius, power)
		"tnt":
			_tnt(pos)
		"gold":
			_golden(pos)
		"sushi":
			_sword()
		"grow":
			_grow_blast(pos)
		"moon":
			_moon_strike()
		_:
			_blast(pos, radius, power)


# ---------------------------------------------------------------------------------------------
# Hidden bombs (found in the vaults)
# ---------------------------------------------------------------------------------------------

## Chain Bomb: the blast, then some of the blocks it broke explode too, and some of theirs -
## always at least CHAIN_MIN follow-up explosions.
const CHAIN_MIN := 4
func _chain(pos: Vector3, radius: float, power: float) -> void:
	var token := world_token
	var res := _blast(pos, radius, power, Color(0.9, 0.9, 1.0))
	var wave: Array = []
	for e in res["broken"]:
		wave.append(e[1])
	wave.shuffle()
	wave = wave.slice(0, 8)
	var total := 0
	var last := pos
	for gen in 3:
		var next: Array = []
		for p in wave:
			if token != world_token or not is_inside_tree() or total >= 30:
				return
			var r2 := _blast(p, radius * 0.75, power, Color(0.8, 0.85, 1.0), false, gen > 0)
			total += 1
			last = p
			for e in r2["broken"]:
				if randf() < 0.15:
					next.append(e[1])
			await get_tree().create_timer(0.06).timeout
		next.shuffle()
		wave = next.slice(0, 6)
	# tough rock may not break enough to keep the chain going - it still always chains at least
	# CHAIN_MIN times, each one hopping on from the last
	var lim: float = pillar.half_width() - 0.3
	while total < CHAIN_MIN:
		if token != world_token or not is_inside_tree():
			return
		var p := last + Vector3(randf_range(-1, 1) * radius * 0.6, -randf_range(0.0, radius * 0.5), randf_range(-1, 1) * radius * 0.6)
		p.x = clampf(p.x, -lim, lim)
		p.z = clampf(p.z, -lim, lim)
		_blast(p, radius * 0.75, power, Color(0.8, 0.85, 1.0), false, total > 0)
		total += 1
		last = p
		await get_tree().create_timer(0.06).timeout


## Freeze Bomb: everything within 7 blocks is left with a sliver of health.
func _freeze(pos: Vector3, radius: float, power: float) -> void:
	var r := 7.0 * Data.VOXEL * reach()
	pillar.make_brittle(pos, r, 0.06)
	_blast(pos, radius * 0.6, power, Color(0.6, 0.9, 1.0), false, true)
	fx.freeze_burst(pos, r)
	sfx.play("freeze", randf_range(0.95, 1.05), 1.0, 0.1)
	shake = maxf(shake, 0.3)


## Quake Bomb: a 5-layer slab across the whole pillar takes a huge hit.
## Sticky Bomb: 20 slime balls drop at once from random spots in the sky. Each one sticks to
## whatever it lands on and goes off like a normal bomb - all of them within the same half second,
## a normal fuse after the last one lands.
const STICKY_BALLS := 20
const STICKY_SPREAD := 0.5     # seconds between the first and last ball going off
const STICKY_WAIT := 3.0       # never wait longer than this for stragglers to land

func _sticky_rain() -> void:
	var lim: float = pillar.half_width() - 0.3
	var group := {"balls": [], "armed": false}
	for i in STICKY_BALLS:
		var p := Vector3(randf_range(-lim, lim), pillar.top_y() + randf_range(6.0, 11.0), randf_range(-lim, lim))
		_spawn_bomb_now("sticky", p, Vector3(0, randf_range(-4.0, -2.0), 0))
		var b = bombs_node.get_child(bombs_node.get_child_count() - 1)
		b.sticky_group = group
		group["balls"].append(b)
	var token := world_token
	await get_tree().create_timer(STICKY_WAIT).timeout
	if token == world_token:
		_arm_sticky(group)


## Called each time a slime ball sticks; once they've all landed, light every fuse together.
func sticky_landed(group: Dictionary) -> void:
	for b in group["balls"]:
		if is_instance_valid(b) and not b.exploded and not b.stuck:
			return
	_arm_sticky(group)


func _arm_sticky(group: Dictionary) -> void:
	if group["armed"]:
		return
	group["armed"] = true
	var fuse := fuse_time()
	for b in group["balls"]:
		if is_instance_valid(b) and not b.exploded:
			b.fuse_left = fuse + randf() * STICKY_SPREAD


## Magnet Bomb: every ore within 12 blocks is ripped out and flies to the bomb.
func _magnet(pos: Vector3) -> void:
	var res: Dictionary = pillar.pull_ores(pos, 12.0 * Data.VOXEL * reach())
	for e in res["broken"]:
		var def: Dictionary = blocks.defs[e[0]]
		fx.streak(e[1], pos, ore_table[def["ore"]]["color"])
	_apply(res, pos)
	fx.explosion(pos, 0.8, Color(1.0, 0.3, 0.3))
	sfx.play("gem_rare", 0.8, 0.0, 0.1)
	shake = maxf(shake, 0.25)


const RENAMED_SPECIALS := {"prism": "mirror", "quake": "sticky",
	"lightning": "tnt", "anchor": "gold", "overclock": "sushi", "supernova": "moon", "sword": "sushi", "golden": "gold",
	"phantom": "grow"}

## Mirror Bomb: becomes a copy of the last special bomb you fired, right where it lands.
## (Drills land and bore as usual; everything else goes off on the spot.) It needs a special
## fired since it was last used - until then it stays locked, even when its reload is done.
const MIRRORABLE := ["drill", "cluster", "acid", "mega", "chain", "freeze", "sticky", "magnet", "blackhole",
	"spore", "tnt", "gold", "sushi", "moon"]
var mirror_copy := ""        # special fired since the Mirror Bomb was last used ("" = locked)
var mirror_payload := ""     # what the Mirror Bomb that's falling right now will become

func mirror_waiting() -> bool:
	return specials.has("mirror") and mirror_copy == ""

func _mirror(pos: Vector3, radius: float, power: float) -> void:
	fx.explosion(pos, 0.9, Color(0.9, 0.9, 1.0))
	sfx.play("portal", 1.8, -2.0, 0.1)
	var copy := mirror_payload
	mirror_payload = ""
	if copy == "":
		_blast(pos, radius, power, Color(0.85, 0.85, 0.95), true)   # shouldn't happen; just in case
	elif copy == "sticky":
		_sticky_rain()
	elif copy == "drill":
		_spawn_bomb_now("drill", pos + Vector3(0, 0.4, 0), Vector3(0, -2, 0))
	else:
		_spawn_bomb_now(copy, pos + Vector3(0, 0.3, 0), Vector3.ZERO, 0.05)


## Black Hole Bomb: swallows everything within 1.5x the Acid Bomb's reach over 2 seconds,
## pulling bombs in.
const BLACK_HOLE_RADIUS_BLOCKS := Data.ACID_RADIUS_BLOCKS * 1.5
const BLACK_HOLE_MAX_GROW := 3.0   # how many times bigger the black hole gets as it eats
func _black_hole(center: Vector3) -> void:
	var token := world_token
	var max_r := BLACK_HOLE_RADIUS_BLOCKS * Data.VOXEL * reach()
	sfx.play("portal", 0.5, 2.0, 0.1)
	cam_hold_y = center.y - 1.0   # keep the black hole (and its finale) on screen
	# the black hole itself stays visible, spinning and swelling as it eats
	var hole := make_model("bombs", "blackhole", float(BombScript.SIZES.get("blackhole", 1.0)), bomb_color("blackhole"))
	add_child(hole)
	hole.global_position = center
	var eaten := 0
	for i in 20:
		if token != world_token or not is_inside_tree():
			cam_hold_y = INF
			hole.queue_free()
			return
		var r := max_r * float(i + 1) / 20.0
		var res: Dictionary = pillar.dissolve(center, r, 0.5)
		eaten += res["broken"].size()
		var grow := 1.0 + minf(BLACK_HOLE_MAX_GROW - 1.0, sqrt(float(eaten)) / 35.0)
		var tw := hole.create_tween()
		tw.tween_property(hole, "scale", Vector3.ONE * grow, 0.1)
		hole.rotate_y(0.35)
		_suck_blocks(res["broken"], center)
		_apply(res, center, false)
		fx.implode(center, r)
		for b in bombs_node.get_children():
			if b is RigidBody3D and not b.exploded:
				var d: Vector3 = center - b.global_position
				if d.length() < max_r * 1.5 and d.length() > 0.2:
					b.apply_central_impulse(d.normalized() * 2.0)
		shake = maxf(shake, 0.2)
		await get_tree().create_timer(0.1).timeout
	# the finale: a big golden-white blast
	hole.queue_free()
	fx.explosion(center, 6.0, Color(1.0, 0.86, 0.45))
	for i in 4:
		var off := Vector3(randf_range(-1.5, 1.5), randf_range(-1.0, 1.5), randf_range(-1.5, 1.5))
		fx.explosion(center + off, 4.0, Color(1.0, 0.95, 0.8))
	fx.shockwave(center, 7.0, [Color(1.0, 0.98, 0.92), Color(1.0, 0.86, 0.45), Color(0.98, 0.7, 0.2)])
	sfx.play("explode_big", 0.6, 4.0, 0.1)
	sfx.play("explode_big", 0.9, 2.0, 0.1)
	shake = maxf(shake, 1.6)
	_vibrate(140)
	await get_tree().create_timer(0.6).timeout
	if token == world_token:
		cam_hold_y = INF


# ---------------------------------------------------------------------------------------------
# Hidden bombs of the Deep Realms
# ---------------------------------------------------------------------------------------------

## Spore Bomb: a small pop, then 14 spores land all over the pillar and burst one after another.

## The blocks a black hole swallows fly into it, shrinking away as they reach the middle.
const SUCK_PER_STEP := 45

func _suck_blocks(broken: Array, center: Vector3) -> void:
	var n := broken.size()
	if n == 0:
		return
	var step := maxf(1.0, float(n) / SUCK_PER_STEP)
	var k := 0.0
	while int(k) < n:
		var e: Array = broken[int(k)]
		var def: Dictionary = blocks.defs[e[0]]
		var c: Color = def.get("oc", def["c1"]) if def["ore"] != "" else def["c1"]
		fx.suck(e[1], c, center, Data.VOXEL * 0.85)
		k += step

func _spore(pos: Vector3, radius: float, power: float) -> void:
	var token := world_token
	_blast(pos, radius, power, Color(0.75, 0.5, 0.9), false, true)
	var spots: Array = []
	for i in 14:
		spots.append(pillar.high_point(2) + Vector3(randf_range(-0.2, 0.2), 0.1, randf_range(-0.2, 0.2)))
	for p in spots:
		fx.streak(pos, p, Color("c8e06a"))
	await get_tree().create_timer(0.6).timeout
	for p in spots:
		if token != world_token or not is_inside_tree():
			return
		_blast(p, radius * 1.2, power, Color(0.8, 0.9, 0.4), false, true)
		await get_tree().create_timer(0.12).timeout


## TNT Bomb (3 rebirths): lands, hops, hisses and flashes white like Minecraft TNT (bomb.gd),
## then blows a crater TNT_LAYERS deep, breaking everything in it however tough.
const TNT_FUSE := 3.0
const TNT_LAYERS := 10

func _tnt(pos: Vector3) -> void:
	var r := (TNT_LAYERS * 0.5 + 0.5) * Data.VOXEL
	var center := pos + Vector3(0, -(TNT_LAYERS * 0.5 - 1.0) * Data.VOXEL, 0)
	_apply(pillar.dissolve(center, r, 0.5), center)
	fx.explosion(pos, 3.5, Color(1.0, 0.62, 0.2))
	fx.explosion(center, 3.0, Color(0.95, 0.85, 0.75))
	fx.shockwave(pos, 3.5, [Color(1.0, 0.7, 0.3), Color(0.9, 0.9, 0.9), Color(0.5, 0.5, 0.5)])
	sfx.play("explode_big", 0.85, 4.0, 0.05)
	sfx.play("explode", 0.7, 2.0, 0.05)
	shake = maxf(shake, 1.1)
	_vibrate(90)


## Golden Bomb (5 rebirths): every block from GOLD_LAYERS above to GOLD_LAYERS below where it
## lands turns to pure gold for a moment, then it all breaks and pays out: the blocks' own ores
## and coins, plus GOLD_BONUS of the coins you had (so you end up with about 1.1x).
const GOLD_LAYERS := 5
const GOLD_BONUS := 0.1
const GOLD_SHOW := 1.0      # seconds the gold stays before it cashes in

func _golden(pos: Vector3) -> void:
	var token := world_token
	var mid: int = pillar.layer_at(pos)
	var cells: Array = pillar.cells_in_layers(mid - GOLD_LAYERS, mid + GOLD_LAYERS + 1)
	fx.explosion(pos, 1.2, Color(1.0, 0.85, 0.3))
	if cells.is_empty():
		return
	pillar.paint_cells(cells, blocks.index_of("gold_block"))
	fx.shockwave(pos, 5.0, [Color(1.0, 0.95, 0.6), Color(1.0, 0.82, 0.25), Color.WHITE])
	ui.flash(Color(1.0, 0.85, 0.3, 0.35), 0.6)
	sfx.play("unlock", 0.8, 3.0, 0.05)
	sfx.play("gem_rare", 1.2, 2.0, 0.05)
	_vibrate(60)
	await get_tree().create_timer(GOLD_SHOW).timeout
	if token != world_token or not is_inside_tree():
		return
	var bonus := coins * GOLD_BONUS
	var res: Dictionary = pillar.break_cells(cells)
	# glittering gold chunks fly off as it all breaks
	for i in mini(70, res["broken"].size()):
		var e: Array = res["broken"][randi() % res["broken"].size()]
		fx.debris(e[1], Color(1.0, 0.82, 0.25) if randf() < 0.7 else Color(1.0, 0.97, 0.75), pos)
	_apply(res, pos, false)
	if bonus > 0.0:
		add_coins(bonus)
	fx.explosion(pos, 3.0, Color(1.0, 0.85, 0.3))
	sfx.play("buy", 1.0, 3.0, 0.05)
	sfx.play("gem_rare", 0.9, 3.0, 0.05)
	sfx.play("explode_big", 1.3, -2.0, 0.05)
	shake = maxf(shake, 0.6)
	ui.notify("GOLD RUSH!", "+[color=#ffcf5a]%s coins[/color] from the gold." % fmt(bonus), ui.icon("coin", 3))


## Sushi Bomb (10 rebirths): a giant katana slices diagonally through the pillar, top right to
## bottom left over SWORD_LAYERS layers, then from there top left to bottom right over another
## SWORD_LAYERS. Everything above each cut breaks off at once.
const SWORD_LAYERS := 10
const SWORD_TIME := 0.28     # seconds for one swing

func _sword() -> void:
	var token := world_token
	var top: int = pillar.highest_layer()
	if top >= pillar.depth:
		return
	var right := camera.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	var span: float = pillar.half_width() * (absf(right.x) + absf(right.z))   # half the pillar, side to side on screen
	var side := func(x: int, z: int) -> float:
		var c: Vector3 = pillar.voxel_center(x, 0, z)
		return clampf((c.x * right.x + c.z * right.z) / span, -1.0, 1.0)
	var at := func(s: float, d: float) -> Vector3:
		return right * (s * span) + Vector3(0, -d * Data.VOXEL, 0)
	cam_hold_y = -(top + SWORD_LAYERS) * Data.VOXEL + 3.0
	var cuts := [
		[1.0, -1.0, top, top + SWORD_LAYERS],                       # top right -> bottom left
		[-1.0, 1.0, top + SWORD_LAYERS, top + SWORD_LAYERS * 2],     # top left -> bottom right
	]
	for c in cuts:
		var s0: float = c[0]
		var s1: float = c[1]
		var d0: float = c[2]
		var d1: float = c[3]
		var a: Vector3 = at.call(s0, d0)
		var b: Vector3 = at.call(s1, d1)
		sfx.play("slash", randf_range(0.95, 1.05), 4.0, 0.05)
		await _swing_sword(a, b)
		if token != world_token or not is_inside_tree():
			return
		# everything above the cut line goes
		var res: Dictionary = pillar.break_where(top, int(ceil(maxf(d0, d1))), func(x: int, d: int, z: int) -> bool:
			var s: float = side.call(x, z)
			var line := lerpf(d0, d1, (s - s0) / (s1 - s0))
			return d + 0.5 < line)
		for i in mini(60, res["broken"].size()):
			var e: Array = res["broken"][randi() % res["broken"].size()]
			fx.debris(e[1], blocks.defs[e[0]]["c1"], e[1] + Vector3(randf_range(-1, 1), 1.0, randf_range(-1, 1)))
		_apply(res, (a + b) * 0.5)
		sfx.play("crack", 0.7, 2.0, 0.05)
		sfx.play("explode", 1.4, -2.0, 0.05)
		shake = maxf(shake, 0.7)
		_vibrate(50)
		await get_tree().create_timer(0.18).timeout
		if token != world_token or not is_inside_tree():
			return
	await get_tree().create_timer(0.5).timeout
	if token == world_token:
		cam_hold_y = INF


## The giant katana flies along the cut from a to b, tip first, flat side to the camera,
## leaving a white streak behind it. models/bombs/katana.gltf (pointing up) if you made one.
func _swing_sword(a: Vector3, b: Vector3) -> void:
	var length: float = pillar.half_width() * 2.6
	var dir := (b - a).normalized()
	var pivot := Node3D.new()
	var blade: Node3D
	if has_model("bombs", "katana"):
		blade = make_model("bombs", "katana", length, Color.WHITE)
		_point_up(blade)
	else:
		blade = _plain_katana(length)
	pivot.add_child(blade)
	var to_cam := camera.global_position - (a + b) * 0.5
	var y := dir
	var z := (to_cam - y * to_cam.dot(y)).normalized()
	var x := y.cross(z).normalized()
	pivot.basis = Basis(x, y, z)
	add_child(pivot)
	# swing just in front of the pillar so the whole blade shows as it cuts
	var front: Vector3 = to_cam.normalized() * (pillar.half_width() * 1.2)
	var from: Vector3 = a + front - dir * length * 0.8
	var to: Vector3 = b + front + dir * length * 0.1
	pivot.position = from
	var tw := pivot.create_tween()
	tw.tween_property(pivot, "position", to, SWORD_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	var trail := pivot.create_tween()
	for k in 12:
		var p: Vector3 = a.lerp(b, (k + 1) / 12.0) + front
		trail.tween_callback(func(): fx.beam(p, Color(0.92, 0.96, 1.0)); fx.beam(p, Color.WHITE))
		trail.tween_interval(SWORD_TIME / 12.0)
	await tw.finished
	var out := pivot.create_tween()
	out.tween_property(pivot, "scale", Vector3.ONE * 0.01, 0.2)
	out.tween_callback(pivot.queue_free)


## Turn a model so its longest side points along +Y (how the giant sword flies, tip first).
func _point_up(holder: Node3D) -> void:
	var acc: Array = [null]
	_collect_aabb(holder, Transform3D.IDENTITY, acc)
	if acc[0] == null:
		return
	var sz: Vector3 = (acc[0] as AABB).size
	if sz.x >= sz.y and sz.x >= sz.z:
		holder.rotate_z(PI * 0.5)
	elif sz.z >= sz.y and sz.z >= sz.x:
		holder.rotate_x(-PI * 0.5)


## Stand-in giant katana until there's a model: a long, thin, gently curved blade with a
## bright edge, a gold collar, a round black guard and a long black handle with white wrapping.
func _plain_katana(length: float) -> Node3D:
	var n := Node3D.new()
	var steel := _flat_mat(Color("d9dfe6"), 0.9)
	var edge := _flat_mat(Color("ffffff"), 0.9)
	var gold := _flat_mat(Color("e8b83a"), 0.8)
	var black := _flat_mat(Color("1a1a1e"), 0.2)
	var wrap := _flat_mat(Color("f2efe6"), 0.0)
	var blade_len := length * 0.7
	var width := length * 0.042
	var thick := length * 0.01
	var curve := 0.07        # how far the tip bends back (share of the blade's length)
	var segs := 8
	for i in segs:
		var t0 := float(i) / segs
		var t1 := float(i + 1) / segs
		var p0 := Vector2(curve * t0 * t0 * blade_len, t0 * blade_len)
		var p1 := Vector2(curve * t1 * t1 * blade_len, t1 * blade_len)
		var mid := (p0 + p1) * 0.5
		var seg_len := p0.distance_to(p1) + thick
		var w := width * (1.0 if i < segs - 1 else 0.6)   # the tip narrows
		var ang := -atan2(p1.x - p0.x, p1.y - p0.y)
		for part in [[w, steel, 0.0], [w * 0.3, edge, -w * 0.5]]:   # body, then the sharp edge
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(part[0], seg_len, thick)
			mi.mesh = bm
			mi.material_override = part[1]
			mi.rotation.z = ang
			mi.position = Vector3(mid.x, mid.y, 0) + Vector3(cos(ang), sin(ang), 0) * float(part[2])
			n.add_child(mi)
	var bits := [
		[Vector3(width * 1.1, length * 0.03, thick * 2.0), Vector3(0, -length * 0.005, 0), gold],     # collar
		[Vector3(length * 0.11, length * 0.012, length * 0.11), Vector3(0, -length * 0.026, 0), black],   # guard
		[Vector3(width * 0.95, length * 0.24, width * 0.7), Vector3(0, -length * 0.152, 0), black],    # handle
		[Vector3(width * 1.05, length * 0.02, width * 0.8), Vector3(0, -length * 0.282, 0), gold],     # end cap
	]
	for b in bits:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = b[0]
		mi.mesh = bm
		mi.material_override = b[2]
		mi.position = b[1]
		n.add_child(mi)
	# the diamond pattern of the handle wrapping
	for k in 6:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(width * 0.45, width * 0.45, width * 0.75)
		mi.mesh = bm
		mi.material_override = wrap
		mi.rotation.z = PI * 0.25
		mi.position = Vector3(0, -length * (0.055 + 0.038 * k), 0)
		n.add_child(mi)
	n.position.y = length * 0.1    # centre it roughly on its length
	var holder := Node3D.new()
	holder.add_child(n)
	return holder


func _flat_mat(c: Color, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = 0.25
	return m


## Moon Bomb (20 rebirths): a long falling whistle for MOON_WAIT seconds, then a moon twice as
## wide as the pillar slams into the top and breaks the top half of what's left.
const MOON_WAIT := 2.0
const MOON_RED := 0.5       # how red the screen gets just before the moon hits

func _moon_strike() -> void:
	var token := world_token
	sfx.play("moon_fall", 1.0, 6.0, 0.1)
	# the sky burns redder and redder as the moon comes down
	var red: ColorRect = ui.screen_tint(Color(1.0, 0.18, 0.06))
	var glow := red.create_tween()
	glow.tween_property(red, "color:a", MOON_RED, MOON_WAIT + 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await get_tree().create_timer(MOON_WAIT).timeout
	if token != world_token or not is_inside_tree():
		red.queue_free()
		return
	var top: int = mini(pillar.highest_layer(), pillar.depth)
	var surface := -top * Data.VOXEL
	var size: float = pillar.half_width() * 4.0     # twice the pillar's width
	var moon: Node3D
	if has_model("bombs", "moon"):
		moon = make_model("bombs", "moon", size, bomb_color("moon"))
	else:
		moon = _plain_moon(size)
	var land := Vector3(0, surface + size * 0.35, 0)
	moon.position = land + Vector3(0, 40.0, 0)
	add_child(moon)
	cam_hold_y = surface - 1.0
	var tw := moon.create_tween()
	tw.set_parallel(true)
	tw.tween_property(moon, "position", land, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(moon, "rotation", Vector3(0.6, 1.2, 0.3), 0.4)
	await tw.finished
	glow.kill()
	var fade := red.create_tween()
	fade.tween_property(red, "color:a", 0.0, 1.6).set_ease(Tween.EASE_OUT)
	fade.tween_callback(red.queue_free)
	if token != world_token or not is_inside_tree():
		moon.queue_free()
		return
	# BOOM: the top half of the pillar that's left is gone
	var half_to := top + int(ceil((pillar.depth - top) * 0.5))
	var res: Dictionary = pillar.break_cells(pillar.cells_in_layers(top, half_to))
	var hit := Vector3(0, surface, 0)
	for i in mini(90, res["broken"].size()):
		var e: Array = res["broken"][randi() % res["broken"].size()]
		fx.debris(e[1], blocks.defs[e[0]]["c1"], hit)
	_apply(res, hit, false)
	ui.flash(Color(1.0, 0.97, 0.9, 0.85), 1.2)
	fx.explosion(hit, 8.0, Color(1.0, 0.8, 0.45))
	for i in 5:
		fx.explosion(hit + Vector3(randf_range(-3, 3), randf_range(-2, 2), randf_range(-3, 3)), 5.0, Color(0.9, 0.9, 0.95))
	fx.shockwave(hit, 9.0, [Color.WHITE, Color(0.85, 0.85, 0.9), Color(1.0, 0.75, 0.4)])
	sfx.play("explode_big", 0.45, 8.0, 0.05)
	sfx.play("explode_big", 0.7, 6.0, 0.05)
	sfx.play("crack", 0.5, 4.0, 0.05)
	shake = maxf(shake, 3.0)
	_vibrate(300)
	var gone := moon.create_tween()
	gone.tween_property(moon, "scale", Vector3.ONE * 0.01, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	gone.tween_callback(moon.queue_free)
	await get_tree().create_timer(1.4).timeout
	if token == world_token:
		cam_hold_y = INF


## Stand-in moon until there's a model: a grey ball.
func _plain_moon(size: float) -> Node3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = size * 0.5
	sm.height = size
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("b4b4bc")
	m.roughness = 0.95
	mi.material_override = m
	var n := Node3D.new()
	n.add_child(mi)
	return n


## Grow Bomb (15 rebirths): lands and sits there for GROW_TIME seconds. Every tap in that
## time (instead of dropping a bomb) makes its blast 1 block bigger - there's no limit. Then it
## goes off, breaking everything in reach however tough.
const GROW_TIME := 10.0
var grow_bomb = null
var grow_taps := 0
var grow_left := 0.0

func grow_landed(bomb) -> void:
	grow_bomb = bomb
	grow_taps = 0
	grow_left = GROW_TIME
	sfx.play("unlock", 0.7, 0.0, 0.05)
	ui.show_charge(true)


func grow_charging() -> bool:
	return grow_bomb != null and is_instance_valid(grow_bomb) and grow_left > 0.0


func _grow_tap() -> void:
	grow_taps += 1
	stat("taps")
	var b = grow_bomb
	# it swells a little with every tap (the blast keeps growing even when the bomb stops)
	var s: float = 1.0 + minf(2.5, grow_taps * 0.04)
	var tw: Tween = b.visual.create_tween()
	tw.tween_property(b.visual, "scale", Vector3.ONE * s * 1.15, 0.05)
	tw.tween_property(b.visual, "scale", Vector3.ONE * s, 0.08)
	sfx.play("land", minf(2.5, 0.8 + grow_taps * 0.02), -2.0, 0.02)
	fx.spark(b.global_position + Vector3(randf_range(-0.3, 0.3), 0.4, randf_range(-0.3, 0.3)))
	_vibrate(6)


func _update_grow(delta: float) -> void:
	if grow_bomb == null:
		return
	if not is_instance_valid(grow_bomb):
		grow_bomb = null
		ui.show_charge(false)
		return
	grow_left -= delta
	ui.set_charge("TAP TAP TAP!", "Blast: [color=#ffcf5a]%d block%s[/color]   %ds" % [1 + grow_taps, "" if grow_taps == 0 else "s", int(ceil(maxf(grow_left, 0.0)))])
	if grow_left <= 0.0:
		var b = grow_bomb
		grow_bomb = null
		ui.show_charge(false)
		b.explode()


func _grow_blast(pos: Vector3) -> void:
	var blocks_r := 1 + grow_taps
	var r := blocks_r * Data.VOXEL
	_apply(pillar.dissolve(pos, r, 0.5), pos)
	var big := minf(r, 9.0)
	fx.explosion(pos, maxf(1.0, big), Color(0.55, 1.0, 0.35))
	fx.explosion(pos, maxf(1.0, big * 0.7), Color(1.0, 0.9, 0.5))
	if blocks_r >= 8:
		fx.shockwave(pos, big, [Color(0.6, 1.0, 0.4), Color(1.0, 0.95, 0.6), Color.WHITE])
	sfx.play("explode_big", clampf(1.2 - blocks_r * 0.01, 0.45, 1.2), clampf(blocks_r * 0.2, 0.0, 8.0), 0.05)
	shake = maxf(shake, clampf(0.4 + blocks_r * 0.03, 0.4, 3.0))
	_vibrate(mini(300, 40 + blocks_r * 4))
	grow_taps = 0


# ---------------------------------------------------------------------------------------------
# Bedrock, vault and the bomb cache
# ---------------------------------------------------------------------------------------------

func treasure_id(w: int) -> String:
	return Data.WORLDS[w]["treasure"]["id"]


## Can the Bedrock Bomb be used in the world you're in right now?
func bedrock_bomb_state() -> String:
	if pillar.bedrock_broken():
		return "broken"
	for b in bombs_node.get_children():
		if b.get("kind") == "bedrock" and not b.get("exploded"):
			return "falling"   # one's already on its way - don't pay for a second
	if next_bedrock_world() != current_world and not bool(worlds[current_world].get("bedrock_done", false)):
		return "out_of_order"
	if not pillar.reached_bedrock():
		return "not_reached"
	if int(ores.get(Data.BEDROCK_BOMB_ORE, 0)) < Data.bedrock_cost(current_world):
		return "need_treasure"
	return "ready"


## Bedrock Bombs go in order: World 1's bedrock first, then World 2's, and so on.
## Returns the first world whose bedrock has never been broken (-1 when all are done).
func next_bedrock_world() -> int:
	for w in Data.WORLDS.size():
		if not bool(worlds[w].get("bedrock_done", false)):
			return w
	return -1


func use_bedrock_bomb() -> void:
	if bedrock_bomb_state() != "ready" or ui.popup_open():
		sfx.play("error")
		return
	ores[Data.BEDROCK_BOMB_ORE] = int(ores.get(Data.BEDROCK_BOMB_ORE, 0)) - Data.bedrock_cost(current_world)
	_spawn_bomb("bedrock", _spawn_point(0.3))
	sfx.play("drop", 0.6)
	ui.refresh()


func _break_bedrock() -> void:
	var spots: Array = pillar.break_bedrock()
	stat("bedrocks")
	for i in mini(spots.size(), 60):
		var p: Vector3 = spots[randi() % spots.size()]
		fx.debris(p, Color("4a4a4e"), p + Vector3(randf_range(-1, 1), -1, randf_range(-1, 1)))
	fx.explosion(Vector3(0, -pillar.depth * Data.VOXEL, 0), 3.0, Color(0.7, 0.7, 0.75))
	sfx.play("explode_big", 0.5, 4.0, 0.1)
	shake = maxf(shake, 1.5)
	_vibrate(120)
	worlds[current_world]["bedrock_broken"] = true
	worlds[current_world]["bedrock_done"] = true   # stays even if the world is reset
	worlds[current_world]["empty"] = false
	ui.notify("THE BEDROCK SHATTERED!",
		"A vault lies below. Dig to the bottom - something is waiting there!",
		ui.micon("bombs", "bedrock", "bedrock", 3), ["bombs", "bedrock"])
	save_game()


## Breaking the bomb cache at the bottom of a vault unlocks that world's hidden bomb (Worlds 1-6),
## a relic (Worlds 7-11), or - in the Starforge - lets you rebirth.
func _open_cache(w: int) -> void:
	if w == Data.STAR_CORE_WORLD:
		rebirth_ready = true
		save_game()
		sfx.play("unlock")
		_vibrate(100)
		ui.notify("THE STAR CORE!", "You can rebirth now. [color=#9be36b]Tap here[/color] or the rebirth button at the top.",
			ui.icon("rebirth", 3), [], show_rebirth_popup, 8.0)
		ui.rebuild_tab()
		return
	for rl in Data.RELICS:
		if int(rl["find"]) == w and not relics.has(rl["id"]):
			relics[rl["id"]] = true
			sfx.play("unlock")
			_vibrate(100)
			var col := Color(rl["col"])
			ui.notify("YOU FOUND THE %s!" % rl["name"].to_upper(),
				"A relic! %s. [color=#9be36b]Tap to see your relics.[/color]" % rl["desc"],
				ui.micon("relics", rl["id"], "gem", 3, col), ["relics", rl["id"]], func(): ui.switch_tab("relics"), 7.0)
			ui.update_tabs()
			ui.rebuild_tab()
			save_game()
			return
	for sp in Data.SPECIALS:
		if int(sp.get("find", -1)) == w and not specials.has(sp["id"]):
			specials[sp["id"]] = 0
			cooldowns[sp["id"]] = 0.0
			sfx.play("unlock")
			_vibrate(100)
			var body := "%s. It's in your hotbar now." % sp["desc"]
			for ow in _try_unlock():
				body += "\n[color=#ffcf5a]%s[/color] has opened!" % Data.WORLDS[ow]["name"]
			for rw in range(Data.ORIGINAL_WORLDS, Data.WORLDS.size()):
				if world_needs(rw) == sp["id"] and rw >= unlocked_worlds:
					body += "\nIt opens [color=#ffcf5a]%s[/color] once you reach the bottom of %s." % [Data.WORLDS[rw]["name"], Data.WORLDS[rw - 1]["name"]]
			ui.notify("YOU FOUND THE %s!" % sp["name"].to_upper(), body,
				ui.micon("bombs", sp["id"], sp["id"], 3), ["bombs", sp["id"]], Callable(), 7.0)
			ui.rebuild_hotbar()
			ui.rebuild_tab()
			save_game()


## Mega Bomb: hits like the Acid Bomb - everything in range breaks, however tough - but all at
## once, reaching 10 blocks.
const MEGA_RADIUS_BLOCKS := 10.0

func _mega(pos: Vector3) -> void:
	var r := MEGA_RADIUS_BLOCKS * Data.VOXEL * reach()
	_apply(pillar.dissolve(pos, r, 0.5), pos)
	fx.explosion(pos, r, Color(1.0, 0.4, 0.1))
	sfx.play("explode_big", 1.0, 2.0, 0.1)
	shake = maxf(shake, 0.9)
	_vibrate(60)


## Acid bomb: the acid spreads out over ACID_SECONDS, dissolving everything it reaches.
func _acid(center: Vector3) -> void:
	var token := world_token
	var steps := 30
	var max_r := Data.ACID_RADIUS_BLOCKS * Data.VOXEL * reach()
	sfx.play("acid", 1.0, 0.0, 0.1)
	for i in steps:
		if token != world_token or not is_inside_tree():
			return
		var r := max_r * float(i + 1) / steps
		var res: Dictionary = pillar.dissolve(center, r, 0.9)
		fx.acid(center, r, pillar.half_width(), pillar.top_y())
		for pp in res.get("plants", []):
			fx.debris(pp, Color("6cbf3f"), center)
		var gained := _collect(res["broken"], center)
		_record_stats(gained[0], gained[1])
		if i % 10 == 9:
			sfx.play("acid", randf_range(0.85, 1.1), -3.0, 0.1)
		shake = maxf(shake, 0.06)
		_check_progress()
		await get_tree().create_timer(Data.ACID_SECONDS / steps).timeout


## One step of a drill bomb boring down: a small, strong blast right under the drill.
func drill_step(pos: Vector3) -> void:
	var k: Dictionary = Data.BOMB_KINDS["drill"]
	_blast(pos + Vector3(0, -0.25, 0), maxf(blast_radius() * float(k["radius"]), 0.75), bomb_power() * float(k["power"]),
		Color(0.8, 0.8, 0.85), false, true)


func _drill(start: Vector3, radius: float, power: float) -> void:
	var token := world_token
	var pos := start
	var r := maxf(radius, 0.75)
	for i in 16:
		if token != world_token or not is_inside_tree():
			return
		_blast(pos, r, power, Color(0.8, 0.8, 0.85), false, true)
		pos.y -= 0.5
		await get_tree().create_timer(0.06).timeout


func _blast(pos: Vector3, radius: float, power: float, tint := Color(1.0, 0.55, 0.15), big := false, quiet := false) -> Dictionary:
	var __t := Time.get_ticks_usec()
	var res: Dictionary = pillar.explode(pos, radius, power)
	prof("explode blocks", __t)
	__t = Time.get_ticks_usec()
	fx.explosion(pos, radius, tint)
	if big:
		sfx.play("explode_big", 1.0, 2.0, 0.1)
		shake = maxf(shake, 0.9)
		_vibrate(60)
	elif quiet:
		sfx.play("crack", randf_range(0.8, 1.2), -4.0, 0.05)
		shake = maxf(shake, 0.08)
	else:
		sfx.play("explode", randf_range(0.9, 1.1) * clampf(1.25 - radius * 0.08, 0.7, 1.2), -2.0, 0.05)
		shake = maxf(shake, 0.12 + radius * 0.06)
	for pp in res.get("plants", []):
		for k in 3:
			fx.debris(pp, Color("6cbf3f") if k < 2 else Color("e8283c").lerp(Color("ffd23a"), randf()), pos)
	var broken: Array = res["broken"]
	if broken.is_empty() and int(res["damaged"]) > 0 and not quiet:
		sfx.play("crack", 1.0, -6.0)
	prof("explosion fx+sound", __t)
	__t = Time.get_ticks_usec()
	var gained := _collect(broken, pos)
	prof("ores+coins", __t)
	# push other bombs around
	for b in bombs_node.get_children():
		if b is RigidBody3D and not b.exploded:
			var d: Vector3 = b.global_position - pos
			var dist := d.length()
			if dist < radius * 2.0 and dist > 0.01:
				b.apply_central_impulse(d.normalized() * 6.0 * (1.0 - dist / (radius * 2.0)))
	_record_stats(gained[0], gained[1])
	_check_progress()
	return res


## Collect a result from one of the special bomb effects (freeze/quake/magnet/black hole...).
func _apply(res: Dictionary, center: Vector3, debris := true) -> void:
	for pp in res.get("plants", []):
		fx.debris(pp, Color("6cbf3f"), center)
	var gained := _collect(res["broken"], center, debris)
	_record_stats(gained[0], gained[1])
	_check_progress()


## Turn broken blocks into coins/ores, debris and flying ore pieces.
func _collect(broken: Array, center: Vector3, debris := true) -> Array:
	var gained := 0.0
	var counts := {}
	var debris_budget := 16
	stat("blocks", broken.size())
	var best_rank := -1
	var cache_world := -1
	var eggs := 0
	var egg_at := Vector3.ZERO
	for e in broken:
		var t: int = e[0]
		var p: Vector3 = e[1]
		var def: Dictionary = blocks.defs[t]
		if def.has("cache_world"):
			cache_world = int(def["cache_world"])
			fx.explosion(p, 0.6, Color(1.0, 0.85, 0.3))
		var oid: String = def["ore"]
		if oid != "":
			ores[oid] = int(ores.get(oid, 0)) + 1
			ores_seen[oid] = true
			stat("ores")
			var v := ore_value(oid)
			gained += v
			counts[oid] = int(counts.get(oid, 0)) + 1
			best_rank = maxi(best_rank, int(def.get("rank", 0)))
			_spawn_gem(oid, p)
			ui.toast_ore(oid, 1)
			if oid == Data.BEDROCK_BOMB_ORE:
				eggs += 1
				egg_at = p
				counts.erase(oid)   # eggs are never part of idle/offline income
		else:
			gained += float(def.get("coins", 0.0)) * value_mult() * coin_scale(int(def["world"])) * rebirth_coin_mult()
			if debris and debris_budget > 0 and randf() < 0.55:
				fx.debris(p, def["c1"], center)
				debris_budget -= 1
	if cache_world >= 0:
		_open_cache.call_deferred(cache_world)
	if eggs > 0:
		_eggs_found(eggs, egg_at)
	if gained > 0.0:
		add_coins(gained)
	if best_rank >= 0:
		sfx.play("gem_rare" if best_rank >= 3 else "gem", 1.0 + randf() * 0.1, -3.0, 0.06)
	return [gained, counts]


## Running averages of what one bomb earns here — used for idle and offline income.
func _record_stats(gained: float, counts: Dictionary) -> void:
	var e: Dictionary = worlds[current_world]
	e["ema_coins"] = lerpf(float(e["ema_coins"]), gained, 0.08)
	var eo: Dictionary = e["ema_ores"]
	for k in counts:
		if not eo.has(k):
			eo[k] = 0.0
	for k in eo.keys():
		eo[k] = lerpf(float(eo[k]), float(counts.get(k, 0)), 0.08)


func _spawn_gem(oid: String, p: Vector3) -> void:
	if gems_node.get_child_count() >= MAX_GEMS:
		return
	var __t := Time.get_ticks_usec()
	_spawn_gem_now(oid, p)
	prof("ore pieces", __t)


func _spawn_gem_now(oid: String, p: Vector3) -> void:
	var g = GemScript.new()
	g.add_child(make_model("ores", oid, 0.32, ore_table[oid]["color"]))
	g.position = p
	gems_node.add_child(g)


func bomb_color(kind: String) -> Color:
	return Color.html(Data.BOMB_KINDS.get(kind, Data.BOMB_KINDS["bomb"])["color"])


# =============================================================================================
# Models (your Blockbench .glb files, or placeholder cubes)
# =============================================================================================

var _scene_cache := {}

## Menu icons: like make_model, but some bombs show as a little pile of their pieces.
const ICON_PILES := {"sticky": [Vector3(-0.27, 0, 0.16), Vector3(0.27, 0, 0.16), Vector3(0, 0, -0.3), Vector3(0.02, 0.36, 0.02)]}

func make_icon_model(folder: String, id: String, size: float, color: Color) -> Node3D:
	if folder == "bombs" and _model_path(folder, id + "pile") != "":
		return make_model(folder, id + "pile", size, color)   # your own pile model, e.g. stickypile
	var path := _model_path(folder, id)
	if folder == "bombs" and ICON_PILES.has(id) and path != "":
		if not _scene_cache.has(path):
			_scene_cache[path] = load(path)
		var scene = _scene_cache[path]
		if scene is PackedScene:
			var pile := Node3D.new()
			var k := 0
			for off in ICON_PILES[id]:
				var ball: Node3D = scene.instantiate()
				ball.position = off
				ball.rotation = Vector3(0.25 * sin(k * 2.1), k * 1.7, 0.25 * cos(k * 1.3))
				pile.add_child(ball)
				k += 1
			return _fit(pile, size)
	return make_model(folder, id, size, color)


func make_model(folder: String, id: String, size: float, color: Color) -> Node3D:
	var path := _model_path(folder, id)
	if path != "":
		if not _scene_cache.has(path):
			_scene_cache[path] = load(path)
		var scene = _scene_cache[path]
		if scene is PackedScene:
			var inst: Node3D = scene.instantiate()
			if folder == "bombs" and not _soft_checked.has(path):
				_soft_checked[path] = true
				_soften_alpha(inst)
			if folder == "bombs" and id in CHROME_BOMBS:
				_make_shiny(inst, Color(CHROME_BOMBS[id]), false, true)
			if folder == "relics":
				var rl := Data.get_relic(id)
				_make_shiny(inst, Color(String(rl.get("col", "ffffff"))), bool(rl.get("keep_white", false)))
			if folder == "ores":
				# shared grey shape -> recolor for this ore; every ore model gets baked face shading
				var shared: bool = not path.get_file().get_basename() == id
				_shade_ore(inst, ore_table[id]["color"] if shared else Color.WHITE)
			if folder == "ores" and Data.ORE_SHAPES.has(id):
				size *= float(shape_scale.get(Data.ORE_SHAPES[id], 1.0))
			return _fit(inst, size)
	return _placeholder(folder, size, color)


## Relics: painted as polished metal in one color. A fake shiny "studio" reflection (bright
## above, dark below, a hot streak at the horizon) plus a sharp highlight and a rim, so they
## gleam as they spin in their icons without needing a real sky to reflect.
## With keep_white, pure-white texture pixels (like the Storm Battery's "!" marks) stay white.
const SHINY_VERSION := 2
## Bombs drawn as polished chrome: their own texture colours, with mirror-like shine on top.
## (The colour is used for any part that has no texture.)
const CHROME_BOMBS := {"gold": "ffc533"}
const SHINY_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec4 tint : source_color = vec4(1.0);
uniform sampler2D tex : source_color, filter_nearest;
uniform bool use_tex = false;
uniform bool tex_color = false;   // chrome: the texture gives the colour, the shine goes on top

void fragment() {
	vec3 n = normalize(NORMAL);
	if (!FRONT_FACING) { n = -n; }
	vec3 v = normalize(VIEW);
	vec3 l = normalize(vec3(-0.45, 0.8, 0.55));
	float diff = max(dot(n, l), 0.0);
	vec3 r = reflect(-v, n);
	float env = mix(0.22, 0.95, smoothstep(-0.7, 0.45, r.y));
	env += 0.8 * exp(-pow((r.y + 0.3) * 7.0, 2.0));           // bright streak along the horizon
	env += 0.35 * smoothstep(0.5, 1.0, r.x * 0.6 + r.y * 0.8);  // soft window glare, upper left
	float spec = pow(max(dot(n, normalize(l + v)), 0.0), 70.0);
	float rim = pow(1.0 - max(dot(n, v), 0.0), 3.0);
	vec3 base = tint.rgb;
	if (tex_color) {
		vec4 tc = texture(tex, UV);
		if (tc.a < 0.5) { discard; }
		base = tc.rgb;
	}
	vec3 metal = base * (0.16 + 0.22 * diff + 0.8 * env) + vec3(1.0) * (1.2 * spec + 0.3 * rim * env);
	if (tex_color) {
		metal += vec3(0.35) * smoothstep(0.55, 1.0, env);   // chrome: bright mirror streaks
	}
	vec3 c = metal;
	if (use_tex) {
		vec4 t = texture(tex, UV);
		if (t.a > 0.5 && min(t.r, min(t.g, t.b)) > 0.97) {
			c = vec3(0.86 + 0.14 * diff) + vec3(0.6 * spec);
		}
	}
	ALBEDO = clamp(c, vec3(0.0), vec3(1.0));
}
"""
var _shiny_shader: Shader
var _shiny_mats := {}

func _make_shiny(node: Node, tint: Color, keep_white: bool, chrome := false) -> void:
	if _shiny_shader == null:
		_shiny_shader = Shader.new()
		_shiny_shader.code = SHINY_SHADER
	for mi in ([node] + node.find_children("*", "MeshInstance3D", true, false)):
		if not (mi is MeshInstance3D) or (mi as MeshInstance3D).mesh == null:
			continue
		var m := mi as MeshInstance3D
		for si in m.mesh.get_surface_count():
			var tex: Texture2D = null
			var src := m.mesh.surface_get_material(si)
			if (keep_white or chrome) and src is BaseMaterial3D:
				tex = (src as BaseMaterial3D).albedo_texture
			var key := "%s|%d|%s" % [tint.to_html(), tex.get_instance_id() if tex else 0, chrome]
			if not _shiny_mats.has(key):
				var mat := ShaderMaterial.new()
				mat.shader = _shiny_shader
				mat.set_shader_parameter("tint", tint)
				mat.set_shader_parameter("use_tex", tex != null and not chrome)
				mat.set_shader_parameter("tex_color", tex != null and chrome)
				if tex:
					mat.set_shader_parameter("tex", tex)
				_shiny_mats[key] = mat
			m.set_surface_override_material(si, _shiny_mats[key])


## Blockbench exports see-through parts as on/off cut-outs, which throws away soft edges (like
## the fading rim of the Black Hole Bomb's ring). Textures with partly see-through pixels get
## real blending instead. Done once per model; the materials are shared, so it sticks.
var _soft_checked := {}

func _soften_alpha(node: Node) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		for si in mesh.get_surface_count():
			var mat := mesh.surface_get_material(si) as BaseMaterial3D
			if mat and mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR and _has_soft_alpha(mat.albedo_texture):
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for c in node.get_children():
		_soften_alpha(c)


func _has_soft_alpha(tex: Texture2D) -> bool:
	if tex == null:
		return false
	var img := tex.get_image()
	if img == null:
		return false
	if img.is_compressed():
		img = img.duplicate()
		img.decompress()
	for y in img.get_height():
		for x in img.get_width():
			var a := img.get_pixel(x, y).a
			if a > 0.04 and a < 0.96:
				return true
	return false


## Which file to load: models/<folder>/<id>.glb/.gltf, or for ores the shared shape model.
## Looked up on disk once per model, then remembered (file checks can be slow on Windows).
var _path_cache := {}

func _model_path(folder: String, id: String) -> String:
	var key := folder + "/" + id
	if _path_cache.has(key):
		return _path_cache[key]
	var p := _find_model_path(folder, id)
	_path_cache[key] = p
	return p


func _find_model_path(folder: String, id: String) -> String:
	var file := id
	if folder == "relics":
		file = String(Data.get_relic(id).get("model", id))
	for ext in [".glb", ".gltf"]:
		var p := "res://models/%s/%s%s" % [folder, file, ext]
		if ResourceLoader.exists(p):
			return p
	if folder == "ores" and Data.ORE_SHAPES.has(id):
		for ext in [".glb", ".gltf"]:
			var p := "res://models/ores/shapes/%s%s" % [Data.ORE_SHAPES[id], ext]
			if ResourceLoader.exists(p):
				return p
	return ""


## Ore models: bake blocky face shading into the mesh (like the pillar's blocks — lit top,
## darker sides and underside, in a few clean steps) and multiply by the ore's color.
## Parts with "notint" in the name keep their own colors but still get shaded.
var _shaded_meshes := {}
var _shaded_mats := {}
const ORE_LIGHT := Vector3(-0.55, 1.0, 0.75)   # from the upper-left, as seen from the camera

func _shade_ore(node: Node, tint: Color) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh:
			var keep := String(mi.name).to_lower().contains("notint")
			var mats: Array = []
			for i in mi.mesh.get_surface_count():
				mats.append(mi.get_active_material(i))
			var mid := mi.mesh.get_instance_id()
			if not _shaded_meshes.has(mid):
				_shaded_meshes[mid] = _bake_shading(mi.mesh)
			mi.mesh = _shaded_meshes[mid]
			for i in mi.mesh.get_surface_count():
				var src = mats[i] if i < mats.size() else null
				var c := Color.WHITE if keep else tint
				var key := "%d_%s" % [src.get_instance_id() if src else 0, c.to_html()]
				if not _shaded_mats.has(key):
					var m := StandardMaterial3D.new()
					m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
					m.vertex_color_use_as_albedo = true
					m.vertex_color_is_srgb = true
					m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
					var base := Color.WHITE
					if src is BaseMaterial3D:
						base = src.albedo_color
						m.albedo_texture = src.albedo_texture
						m.transparency = src.transparency
					m.albedo_color = base * c
					_shaded_mats[key] = m
				mi.set_surface_override_material(i, _shaded_mats[key])
	for ch in node.get_children():
		_shade_ore(ch, tint)


func _bake_shading(src: Mesh) -> ArrayMesh:
	var out := ArrayMesh.new()
	var light := ORE_LIGHT.normalized()
	for i in src.get_surface_count():
		var arrays := src.surface_get_arrays(i)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var cols := PackedColorArray()
		cols.resize(verts.size())
		for v in verts.size():
			var n := normals[v] if v < normals.size() else Vector3.UP
			var lit := clampf(n.dot(light) * 0.5 + 0.5, 0.0, 1.0)
			var shade := lerpf(0.42, 1.12, lit)
			shade = round(shade * 5.0) / 5.0          # a few clean steps, pixel-art style
			cols[v] = Color(shade, shade, shade)
		arrays[Mesh.ARRAY_COLOR] = cols
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out


## Multiply every material by the ore's color (a grey model becomes that ore's color).
func _tint(node: Node, c: Color) -> void:
	if node is MeshInstance3D and not String(node.name).to_lower().contains("notint"):
		var mi := node as MeshInstance3D
		if mi.mesh:
			for i in mi.mesh.get_surface_count():
				var m = mi.get_active_material(i)
				var nm: StandardMaterial3D
				if m is StandardMaterial3D:
					nm = m.duplicate()
				else:
					nm = StandardMaterial3D.new()
				nm.albedo_color = nm.albedo_color * c
				mi.set_surface_override_material(i, nm)
	for ch in node.get_children():
		_tint(ch, c)


## Scale a model so its longest side is `size`.
func _fit(inst: Node3D, size: float) -> Node3D:
	var acc: Array = [null]
	_collect_aabb(inst, Transform3D.IDENTITY, acc)
	var holder := Node3D.new()
	var inner := Node3D.new()
	holder.add_child(inner)
	inner.add_child(inst)
	if acc[0] != null:
		var box: AABB = acc[0]
		var dims := [box.size.x, box.size.y, box.size.z]
		dims.sort()
		var longest: float = dims[2]
		if longest > 0.0001:
			holder.scale = Vector3.ONE * (size / longest)
		inner.position = -box.get_center()
	return holder


## Longest side of a model in its own (Blockbench) units, or 0 if it doesn't exist.
func model_longest(folder: String, id: String) -> float:
	var key := "%s/%s" % [folder, id]
	if model_cache.has(key):
		return model_cache[key]
	var longest := 0.0
	var path := _model_path(folder, id)
	if path != "":
		var scene = load(path)
		if scene is PackedScene:
			var inst: Node = scene.instantiate()
			var acc: Array = [null]
			_collect_aabb(inst, Transform3D.IDENTITY, acc)
			if acc[0] != null:
				var box: AABB = acc[0]
				longest = maxf(box.size.x, maxf(box.size.y, box.size.z))
			inst.free()
	model_cache[key] = longest
	return longest


func has_model(folder: String, id: String) -> bool:
	return _model_path(folder, id) != ""


## Renders your Blockbench models (and a mini pillar for each world) into small pixel-art icons
## for the menus. Runs once at startup, one icon per frame.
func _render_icons() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_load_icon_index()
	var jobs: Array = []
	for kind in Data.BOMB_KINDS:
		if has_model("bombs", kind):
			jobs.append(["bombs", kind])
	for oid in ore_table:
		if has_model("ores", oid):
			jobs.append(["ores", oid])
	for r in Data.RELICS:
		if has_model("relics", r["id"]):
			jobs.append(["relics", r["id"]])
	for w in Data.WORLDS.size():
		jobs.append(["world", str(w)])
	var vp := SubViewport.new()
	vp.size = Vector2i(ICON_RES, ICON_RES)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var ienv := Environment.new()
	ienv.background_mode = Environment.BG_CLEAR_COLOR
	ienv.background_color = Color(0, 0, 0, 0)
	ienv.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	ienv.ambient_light_color = Color.WHITE
	ienv.ambient_light_energy = 1.0
	var we := WorldEnvironment.new()
	we.environment = ienv
	vp.add_child(we)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, 20, 0)
	light.light_energy = 1.7
	vp.add_child(light)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.6
	vp.add_child(cam)
	cam.position = Vector3(1.0, 1.0, 1.0).normalized() * 4.0
	cam.look_at(Vector3.ZERO)
	await _measure_shapes(vp, cam)

	# world icons: one still frame each
	vp.size = Vector2i(ICON_RES, ICON_RES)
	cam.size = 1.3
	for job in jobs:
		if job[0] != "world":
			continue
		if _load_cached_icon("%s/%s" % [job[0], job[1]], _icon_sig(job[0], job[1])):
			continue   # its saved spinning loop is ready
		var node := _world_icon_node(int(job[1]))
		vp.add_child(node)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		if img != null and not img.is_empty():
			model_icons["%s/%s" % [job[0], job[1]]] = _pixelize(img)
		node.queue_free()
	vp.queue_free()

	# bombs and ores: load saved spinning icons; anything new/changed gets a still frame for now
	# (its spinning loop is made in the background later)
	var still := _make_icon_viewport(MODEL_ICON_RES)
	for job in jobs:
		if job[0] == "world":
			continue
		if _load_cached_icon("%s/%s" % [job[0], job[1]], _icon_sig(job[0], job[1])):
			continue
		var node := make_icon_model(job[0], job[1], _icon_size(job[0], job[1]), Color.BLACK)
		node.rotation.y = _icon_turn(node) + float(ICON_TURN.get(job[1], 0.0))
		still.get_meta("cam").size = 1.3 if job[0] in ["bombs", "relics"] else 1.0
		still.add_child(node)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := still.get_texture().get_image()
		if img != null and not img.is_empty():
			model_icons["%s/%s" % [job[0], job[1]]] = _pixelize(img)
		node.queue_free()
	still.queue_free()
	_save_icon_index()


## A fingerprint of a model file: changes whenever you re-export / re-import the model.
func _model_sig(folder: String, id: String) -> String:
	var p := _model_path(folder, id)
	if p == "":
		return ""
	if FileAccess.file_exists(p + ".import"):
		return FileAccess.get_md5(p + ".import")
	return str(FileAccess.get_modified_time(p))


## Everything that changes how an icon looks. If this matches what was saved, the saved icon is used.
func _icon_sig(folder: String, id: String) -> String:
	var extra := "%d|%d|%d|%.3f|%.3f" % [ICON_CACHE_VERSION, MODEL_ICON_RES, ICON_FRAMES, ICON_BOB, float(ICON_TURN.get(id, 0.0))]
	if folder == "bombs" and ICON_SHRINK.has(id):
		extra += "|shrink%.3f" % float(ICON_SHRINK[id])
	if folder == "ores":
		extra += "|%s|%.3f" % [ore_table[id]["color"].to_html(), float(shape_scale.get(Data.ORE_SHAPES.get(id, ""), 1.0))]
	if folder == "world":
		var wd: Dictionary = Data.WORLDS[int(id)]
		extra += "|world%d" % hash([wd["layers"], wd["ores"][3]["id"]])
	if folder == "relics":
		var rl := Data.get_relic(id)
		extra += "|shiny%d|%s|%s|%s" % [SHINY_VERSION, rl.get("col", ""), rl.get("model", id), rl.get("keep_white", false)]
	if folder == "bombs" and CHROME_BOMBS.has(id):
		extra += "|chrome%d" % SHINY_VERSION
	if folder == "bombs" and ICON_PILES.has(id):
		extra += "|pile%d" % ICON_PILES[id].size()
	if folder == "bombs" and _model_path(folder, id + "pile") != "":
		extra += "|pilemodel" + _model_sig(folder, id + "pile")
	return _model_sig(folder, id) + "|" + extra


func _load_icon_index() -> void:
	DirAccess.make_dir_recursive_absolute(ICON_CACHE_DIR)
	var path := ICON_CACHE_DIR + "/index.json"
	if FileAccess.file_exists(path):
		var d = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(d) == TYPE_DICTIONARY:
			icon_index = d


func _save_icon_index() -> void:
	var f := FileAccess.open(ICON_CACHE_DIR + "/index.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(icon_index))


## Load a saved spin loop (one PNG strip of all frames) if it still matches the model.
func _load_cached_icon(key: String, sig: String) -> bool:
	if str(icon_index.get(key, "")) != sig:
		return false
	var path := "%s/%s.png" % [ICON_CACHE_DIR, key.replace("/", "_")]
	if not FileAccess.file_exists(path):
		return false
	var strip := Image.load_from_file(path)
	if strip == null or strip.get_width() != MODEL_ICON_RES * ICON_FRAMES:
		return false
	var frames: Array[Image] = []
	for k in ICON_FRAMES:
		frames.append(strip.get_region(Rect2i(k * MODEL_ICON_RES, 0, MODEL_ICON_RES, MODEL_ICON_RES)))
	model_icons[key] = frames[0]
	model_icon_frames[key] = frames
	return true


func _save_cached_icon(key: String, sig: String, frames: Array) -> void:
	var strip := Image.create(MODEL_ICON_RES * ICON_FRAMES, MODEL_ICON_RES, false, Image.FORMAT_RGBA8)
	for k in frames.size():
		strip.blit_rect(frames[k], Rect2i(0, 0, MODEL_ICON_RES, MODEL_ICON_RES), Vector2i(k * MODEL_ICON_RES, 0))
	strip.save_png("%s/%s.png" % [ICON_CACHE_DIR, key.replace("/", "_")])
	icon_index[key] = sig


func _icon_size(folder: String, id: String) -> float:
	if folder == "ores":
		# fill the icon, but keep the tall shapes (scaled up in-game) inside the frame
		var sc := float(shape_scale.get(Data.ORE_SHAPES.get(id, ""), 1.0))
		return 0.82 / maxf(sc, 1.0)
	if folder == "bombs" and ICON_SHRINK.has(id):
		return 0.9 * float(ICON_SHRINK[id])
	return 0.9


## Boxy models look bigger from the icon camera's corner view, so they're drawn a bit smaller.
const ICON_SHRINK := {"tnt": 0.68}


## Bombs and ores: a spinning, bobbing loop (like a dropped item in Minecraft).
## All frames of one model render at once in a row of small viewports, then get cleaned up a
## few per frame so the game doesn't stutter.
func _render_spin_icons() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var keys: Array = []
	for k in model_icons.keys():
		if not model_icon_frames.has(k):
			keys.append(k)
	if keys.is_empty():
		return
	# bombs first (hotbar), then ores
	keys.sort_custom(func(a, b): return String(a).begins_with("bombs") and not String(b).begins_with("bombs"))
	var pool: Array = []
	for k in ICON_FRAMES:
		var v := _make_icon_viewport(MODEL_ICON_RES)
		v.render_target_update_mode = SubViewport.UPDATE_DISABLED
		pool.append(v)
	for key in keys:
		var parts := String(key).split("/")
		var folder := parts[0]
		var id := parts[1]
		var nodes: Array = []
		for k in ICON_FRAMES:
			var v: SubViewport = pool[k]
			var node: Node3D = _world_icon_node(int(id)) if folder == "world" else make_icon_model(folder, id, _icon_size(folder, id), Color.BLACK)
			var t := float(k) / ICON_FRAMES
			node.rotation.y = _icon_turn(node) + float(ICON_TURN.get(id, 0.0)) + TAU * t
			node.position.y = sin(TAU * t) * ICON_BOB
			v.get_meta("cam").size = 1.3 if folder in ["bombs", "relics", "world"] else 1.0
			v.add_child(node)
			v.render_target_update_mode = SubViewport.UPDATE_ONCE
			nodes.append(node)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var raw: Array = []
		for k in ICON_FRAMES:
			raw.append(pool[k].get_texture().get_image())
			nodes[k].queue_free()
		var frames: Array[Image] = []
		for k in raw.size():
			var img: Image = raw[k]
			if img == null or img.is_empty():
				break
			frames.append(_pixelize(img))
			if k % 4 == 3:
				await get_tree().process_frame
		if frames.size() == ICON_FRAMES:
			model_icon_frames[key] = frames
			var parts2 := String(key).split("/")
			_save_cached_icon(key, _icon_sig(parts2[0], parts2[1]), frames)
			if ui:
				ui.spin_ready(key)
			if loading_screen and is_instance_valid(loading_screen):
				loading_screen.spin_ready(key)
	_save_icon_index()
	for v in pool:
		v.queue_free()


## A small transparent viewport with its own light and an orthographic camera, for icons.
func _make_icon_viewport(res: int) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(res, res)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var ienv := Environment.new()
	ienv.background_mode = Environment.BG_CLEAR_COLOR
	ienv.background_color = Color(0, 0, 0, 0)
	ienv.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	ienv.ambient_light_color = Color.WHITE
	ienv.ambient_light_energy = 1.0
	var we := WorldEnvironment.new()
	we.environment = ienv
	vp.add_child(we)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, 20, 0)
	light.light_energy = 1.7
	vp.add_child(light)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.0
	vp.add_child(cam)
	cam.position = Vector3(1.0, 1.0, 1.0).normalized() * 4.0
	cam.look_at(Vector3.ZERO)
	vp.set_meta("cam", cam)
	return vp


## Render each ore shape once and count how many pixels it covers, then pick a size multiplier
## per shape so they all cover about the same area (thin shards get bigger, flat relics smaller).
func _measure_shapes(vp: SubViewport, cam: Camera3D) -> void:
	var shapes := {}
	for oid in Data.ORE_SHAPES:
		shapes[Data.ORE_SHAPES[oid]] = true
	vp.size = Vector2i(64, 64)
	cam.size = 1.6
	var areas := {}
	var saved: Dictionary = icon_index.get("shape_areas", {})
	for shape in shapes:
		var path := ""
		for ext in [".glb", ".gltf"]:
			if ResourceLoader.exists("res://models/ores/shapes/%s%s" % [shape, ext]):
				path = "res://models/ores/shapes/%s%s" % [shape, ext]
				break
		if path == "":
			continue
		var sig := (FileAccess.get_md5(path + ".import") if FileAccess.file_exists(path + ".import") else str(FileAccess.get_modified_time(path))) + "|%d" % ICON_CACHE_VERSION
		if saved.has(shape) and str(saved[shape][0]) == sig:
			areas[shape] = float(saved[shape][1])     # measured on an earlier launch
			continue
		var node := _fit(load(path).instantiate(), 1.0)
		node.rotation.y = -0.35
		vp.add_child(node)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		node.queue_free()
		if img == null or img.is_empty():
			continue
		var count := 0
		for y in img.get_height():
			for x in img.get_width():
				if img.get_pixel(x, y).a > 0.45:
					count += 1
		if count > 0:
			areas[shape] = float(count)
			saved[shape] = [sig, float(count)]
	icon_index["shape_areas"] = saved
	vp.size = Vector2i(ICON_RES, ICON_RES)
	if areas.is_empty():
		return
	var vals := areas.values()
	vals.sort()
	var target: float = vals[vals.size() / 2]   # the middle-sized shape is the reference
	for shape in areas:
		shape_scale[shape] = clampf(sqrt(target / areas[shape]), 0.6, 1.8)


## Extra turn for specific icons (radians). Positive = model turned to its left (front comes toward you).
const ICON_TURN := {"mega": PI / 4.0, "acid": PI / 4.0}


## How to turn a model for its icon: flat things (like the heart) face the camera, others a 3/4 view.
func _icon_turn(node: Node3D) -> float:
	var acc: Array = [null]
	_collect_aabb(node, Transform3D.IDENTITY, acc)
	if acc[0] == null:
		return -0.35
	var sz: Vector3 = (acc[0] as AABB).size
	if sz.z < sz.x * 0.6 and sz.z < sz.y:
		return PI / 4.0      # flat along z: face +z toward the camera
	if sz.x < sz.z * 0.6 and sz.x < sz.y:
		return -PI / 4.0     # flat along x
	return -0.35


## Hard-edged alpha + dark 1px outline + light top-left edge, so rendered icons match the
## hand-drawn ones. Works on the raw bytes (much faster than pixel-by-pixel Color calls).
func _pixelize(src: Image) -> Image:
	var img: Image = src.duplicate()
	img.convert(Image.FORMAT_RGBA8)
	var n := img.get_width()
	var d := img.get_data()
	var solid := PackedByteArray()
	solid.resize(n * n)
	for i in n * n:
		solid[i] = 1 if d[i * 4 + 3] > 115 else 0
	var out := PackedByteArray()
	out.resize(n * n * 4)
	for y in n:
		for x in n:
			var i := y * n + x
			var o := i * 4
			if solid[i] == 1:
				var r := d[o]
				var g := d[o + 1]
				var b := d[o + 2]
				if y == 0 or x == 0 or solid[i - n] == 0 or solid[i - 1] == 0:
					r += int((255 - r) * 0.3)
					g += int((255 - g) * 0.3)
					b += int((255 - b) * 0.3)
				out[o] = r
				out[o + 1] = g
				out[o + 2] = b
				out[o + 3] = 255
			elif (x > 0 and solid[i - 1] == 1) or (x < n - 1 and solid[i + 1] == 1) \
					or (y > 0 and solid[i - n] == 1) or (y < n - 1 and solid[i + n] == 1):
				out[o] = 18
				out[o + 1] = 14
				out[o + 2] = 11
				out[o + 3] = 255
	return Image.create_from_data(n, n, false, Image.FORMAT_RGBA8, out)


## A mini 2x2x3 pillar made of the world's own blocks (top layer, next layer, rock with an ore).
func _world_icon_node(w: int) -> Node3D:
	var world: Dictionary = Data.WORLDS[w]
	var layers: Array = world["layers"]
	var rows := [
		blocks.index_of("%s_%s" % [world["id"], layers[0]["id"]]),
		blocks.index_of("%s_%s" % [world["id"], layers[1]["id"]]),
		blocks.index_of("%s_%s" % [world["id"], layers[2]["id"]]),
	]
	var ore_b: int = blocks.index_of("ore_" + world["ores"][3]["id"])
	var sz := 0.36
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var inds := PackedInt32Array()
	for y in 3:
		for x in 2:
			for z in 2:
				var t: int = rows[y]
				if y == 2 and x == 1 and z == 1:
					t = ore_b
				var base := Vector3((x - 1) * sz, (1.5 - y - 1) * sz, (z - 1) * sz)
				for f in 6:
					var nx: int = x + PillarScript.FDX[f]
					var ny: int = y + PillarScript.FDD[f]
					var nz: int = z + PillarScript.FDZ[f]
					if nx >= 0 and nx < 2 and nz >= 0 and nz < 2 and ny >= 0 and ny < 3:
						continue
					var r: Rect2 = blocks.uv(t, f >= 2, 0)
					var sh: float = PillarScript.FACE_SHADE[f]
					var start := verts.size()
					var corners: Array = PillarScript.FACE_CORNERS[f]
					for k in 4:
						verts.append(base + corners[k] * sz)
						cols.append(Color(sh, sh, sh))
					uvs.append(r.position)
					uvs.append(Vector2(r.end.x, r.position.y))
					uvs.append(r.end)
					uvs.append(Vector2(r.position.x, r.end.y))
					for k in [0, 1, 2, 0, 2, 3]:
						inds.append(start + k)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = inds
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = pillar.material
	var root := Node3D.new()
	root.add_child(mi)
	# a flower and some grass on the grass world
	if layers[0].get("style", "") == "grass":
		var n: float = float(blocks.PLANT_NAMES.size())
		var top := 1.5 * sz
		var pv := PackedVector3Array()
		var pu := PackedVector2Array()
		var pidx := PackedInt32Array()
		for pl in [[2, Vector3(-0.5, 0, -0.5)], [0, Vector3(0.5, 0, 0.5)]]:
			var kind: int = pl[0]
			var c: Vector3 = (pl[1] as Vector3) * sz + Vector3(0, top, 0)
			for diag in 2:
				var a := Vector3(-0.45, 0, -0.45) * sz if diag == 0 else Vector3(-0.45, 0, 0.45) * sz
				var st := pv.size()
				pv.append(c + a + Vector3(0, sz, 0))
				pv.append(c - a + Vector3(0, sz, 0))
				pv.append(c - a)
				pv.append(c + a)
				pu.append(Vector2(kind / n, 0))
				pu.append(Vector2((kind + 1) / n, 0))
				pu.append(Vector2((kind + 1) / n, 1))
				pu.append(Vector2(kind / n, 1))
				for k in [0, 1, 2, 0, 2, 3]:
					pidx.append(st + k)
		var pa := []
		pa.resize(Mesh.ARRAY_MAX)
		pa[Mesh.ARRAY_VERTEX] = pv
		pa[Mesh.ARRAY_TEX_UV] = pu
		pa[Mesh.ARRAY_INDEX] = pidx
		var pm := ArrayMesh.new()
		pm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, pa)
		var pmi := MeshInstance3D.new()
		pmi.mesh = pm
		var mat: StandardMaterial3D = pillar.plant_material.duplicate()
		mat.vertex_color_use_as_albedo = false
		pmi.material_override = mat
		root.add_child(pmi)
	return root


func _collect_aabb(node: Node, parent_xf: Transform3D, acc: Array) -> void:
	var xf := parent_xf
	if node is Node3D:
		xf = parent_xf * (node as Node3D).transform
	if node is VisualInstance3D:
		var box: AABB = xf * (node as VisualInstance3D).get_aabb()
		acc[0] = box if acc[0] == null else (acc[0] as AABB).merge(box)
	for c in node.get_children():
		_collect_aabb(c, xf, acc)


func _mat(c: Color) -> StandardMaterial3D:
	var key := c.to_html()
	if not mat_cache.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = c
		mat_cache[key] = m
	return mat_cache[key]


func _placeholder(folder: String, size: float, color: Color) -> Node3D:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE * size * (0.85 if folder == "bombs" else 1.0)
	body.mesh = box
	body.material_override = _mat(color)
	root.add_child(body)
	# darker bottom half so the cube reads as 3D under unshaded lighting
	var shade := MeshInstance3D.new()
	var sbox := BoxMesh.new()
	sbox.size = Vector3(box.size.x * 1.01, box.size.y * 0.35, box.size.z * 1.01)
	shade.mesh = sbox
	shade.position.y = -box.size.y * 0.33
	shade.material_override = _mat(color.darkened(0.3))
	root.add_child(shade)
	if folder == "bombs":
		var fuse := MeshInstance3D.new()
		var fbox := BoxMesh.new()
		fbox.size = Vector3(size * 0.18, size * 0.3, size * 0.18)
		fuse.mesh = fbox
		fuse.position.y = box.size.y * 0.6
		fuse.material_override = _mat(Color("6b4a2e"))
		root.add_child(fuse)
	return root


# =============================================================================================
# Frame update
# =============================================================================================

## Time a piece of work for the hitch reporter.
func prof(section: String, start_usec: int) -> void:
	_prof[section] = int(_prof.get(section, 0)) + Time.get_ticks_usec() - start_usec


func _check_hitch(delta: float) -> void:
	if delta > 0.1:
		var keys := _prof.keys()
		keys.sort_custom(func(a, b): return _prof[a] > _prof[b])
		var parts: Array[String] = []
		for k in keys.slice(0, 4):
			parts.append("%s %d" % [k, int(_prof[k] / 1000)])
		var phys := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		last_hitch = "last hitch %d ms: %s | physics %d" % [int(delta * 1000.0), ", ".join(parts) if not parts.is_empty() else "nothing in game code", int(phys)]
	_prof.clear()


func _process(delta: float) -> void:
	_check_hitch(delta)
	var __t := Time.get_ticks_usec()
	pillar.process_dirty(delta)
	prof("blocks", __t)
	if ui == null:
		return  # still starting up (rendering icons)
	stats["time"] = float(stats.get("time", 0.0)) + delta
	_update_grow(delta)
	_check_hints(delta)
	afford_timer -= delta
	if afford_timer <= 0.0:
		afford_timer = 0.5
		_check_new_bombs()

	if holding:
		hold_timer -= delta
		if hold_timer <= 0.0:
			hold_timer = TAP_REPEAT
			_tap_drop()

	# auto-bomber in this world drops real bombs (and stops once there's nothing left to blast)
	empty_timer -= delta
	if empty_timer <= 0.0:
		empty_timer = 1.0
		worlds[current_world]["empty"] = not pillar.blocks_left()
	var rate := auto_rate(current_world)
	if rate > 0.0 and not world_empty(current_world):
		auto_accum += rate * delta
		while auto_accum >= 1.0:
			auto_accum -= 1.0
			if bombs_node.get_child_count() < MAX_BOMBS:
				_spawn_bomb("bomb", _spawn_point(1.0))
				stat("auto_bombs")

	# auto-bombers in other worlds earn from their averages
	bg_timer += delta
	if bg_timer >= 1.0:
		bg_timer -= 1.0
		for w in unlocked_worlds:
			if w != current_world and int(worlds[w]["auto"]) > 0 and not world_empty(w):
				_idle_income(w, auto_rate(w) * IDLE_EFFICIENCY)

	for id in cooldowns.keys():
		cooldowns[id] = maxf(0.0, float(cooldowns[id]) - delta)

	if portal_open and portal_node and not portal_locked():
		fx.portal_upright(portal_node.position + Vector3(0, PORTAL_H * 0.5, 0.15), PORTAL_W, PORTAL_H)

	_update_camera(delta, false)

	ui_timer += delta
	if ui_timer >= 0.2:
		ui_timer = 0.0
		var __u := Time.get_ticks_usec()
		ui.refresh()
		prof("menus", __u)
	save_timer += delta
	if save_timer >= 20.0:
		save_timer = 0.0
		save_game()


## True when a world has nothing left to blast - its auto-bomber takes a break.
var empty_timer := 0.0

func world_empty(w: int) -> bool:
	return bool(worlds[w].get("empty", false))


## Gives the coins/ores a world's auto-bomber would make for `bombs` bombs. Returns what was given.
func _idle_income(w: int, bombs: float) -> Dictionary:
	var e: Dictionary = worlds[w]
	var c := float(e["ema_coins"]) * bombs
	add_coins(c)
	if not bg_acc.has(w):
		bg_acc[w] = {}
	var acc: Dictionary = bg_acc[w]
	var got := {}
	var eo: Dictionary = e["ema_ores"]
	for k in eo:
		acc[k] = float(acc.get(k, 0.0)) + float(eo[k]) * bombs
		var whole := int(floor(acc[k]))
		if whole > 0:
			acc[k] -= whole
			ores[k] = int(ores.get(k, 0)) + whole
			ores_seen[k] = true
			got[k] = whole
	return {"coins": c, "ores": got}


## Something worth watching (like a black hole) can hold the camera on itself for a moment.
var cam_hold_y := INF

func _focus_target() -> Vector3:
	if cam_hold_y != INF:
		return Vector3(0, cam_hold_y, 0)
	return Vector3(0, pillar.top_y() - 1.5, 0)


func _update_camera(delta: float, snap: bool) -> void:
	var target := _focus_target()
	cam_focus = target if snap else cam_focus.lerp(target, clampf(delta * 3.0, 0.0, 1.0))
	var offset := Vector3(7.2, 8.6, 10.4)
	var shake_off := Vector3.ZERO
	if reduce_flash:
		shake = 0.0
	if shake > 0.0:
		shake = maxf(0.0, shake - delta * 2.5)
		shake_off = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * shake * 0.35
	camera.position = cam_focus + offset + shake_off
	camera.look_at(cam_focus + Vector3(0, -4.2, 0) + shake_off, Vector3.UP)


func _vibrate(ms: int) -> void:
	if vibrate_on:
		Input.vibrate_handheld(ms)


# =============================================================================================
# Offline income, saving, loading
# =============================================================================================

func grant_offline(seconds: float) -> void:
	if seconds < 60.0:
		return
	seconds = minf(seconds, OFFLINE_CAP)
	var total_c := 0.0
	var total_o := {}
	for w in unlocked_worlds:
		if int(worlds[w]["auto"]) <= 0 or world_empty(w):
			continue
		var r := _idle_income(w, auto_rate(w) * IDLE_EFFICIENCY * seconds)
		total_c += float(r["coins"])
		for k in r["ores"]:
			total_o[k] = int(total_o.get(k, 0)) + int(r["ores"][k])
	if total_c <= 0.0 and total_o.is_empty():
		return
	var lines := "Gone %s. Your auto-bombers found [color=#ffcf5a]%s coins[/color]" % [_duration(seconds), fmt(total_c)]
	var sorted_ores := total_o.keys()
	sorted_ores.sort_custom(func(a, b): return ore_table[a]["value"] > ore_table[b]["value"])
	for i in mini(3, sorted_ores.size()):
		var k: String = sorted_ores[i]
		lines += ", %s %s" % [fmt(float(total_o[k])), ore_table[k]["name"]]
	ui.notify("WELCOME BACK", lines + ".", ui.icon("auto", 3), [], Callable(), 8.0)
	sfx.play("gem_rare")


func _duration(sec: float) -> String:
	var s := int(sec)
	if s >= 3600:
		return "%dh %dm" % [s / 3600, (s % 3600) / 60]
	return "%dm" % (s / 60)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED:
			save_game()
			pause_unix = Time.get_unix_time_from_system()
		NOTIFICATION_APPLICATION_RESUMED:
			if pause_unix > 0.0 and ui:
				grant_offline(Time.get_unix_time_from_system() - pause_unix)
			pause_unix = 0.0
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_CLOSE_REQUEST:
			save_game()


func save_game() -> void:
	if pillar == null or pillar.types.is_empty() or switching_save:
		return
	worlds[current_world]["state"] = pillar.get_state()
	worlds[current_world]["depth"] = pillar.floor_depth()
	var data := {
		"version": 1,
		"coins": coins, "total_coins": total_coins, "levels": levels,
		"ores": ores, "ores_seen": ores_seen,
		"current_world": current_world, "unlocked_worlds": unlocked_worlds,
		"worlds": worlds, "specials": specials, "cooldowns": cooldowns, "mirror_copy": mirror_copy,
		"relics": relics, "rebirths": rebirths, "rebirth_ready": rebirth_ready, "hide_early_worlds": hide_early_worlds,
		"sound_on": sound_on, "vibrate_on": vibrate_on, "reduce_flash": reduce_flash,
		"stats": stats, "hints_seen": hints_seen,
		"time": Time.get_unix_time_from_system(),
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))


# ---- Save slots -----------------------------------------------------------------------------
## Your game always plays from the main save file; slots are copies you can save to / load from.
const SAVE_SLOTS := 3
var switching_save := false     # true while a slot is being loaded (stops the old game re-saving)

func slot_path(i: int) -> String:
	return "user://blast_pillar_slot_%d.json" % i

## {"exists", "world", "coins", "time"} for a save slot.
func slot_info(i: int) -> Dictionary:
	if not FileAccess.file_exists(slot_path(i)):
		return {"exists": false}
	var d = JSON.parse_string(FileAccess.get_file_as_string(slot_path(i)))
	if typeof(d) != TYPE_DICTIONARY:
		return {"exists": false}
	var w := clampi(int(d.get("current_world", 0)), 0, Data.WORLDS.size() - 1)
	return {"exists": true, "world": Data.WORLDS[w]["name"], "coins": float(d.get("coins", 0.0)),
		"time": float(d.get("time", 0.0)), "worlds": int(d.get("unlocked_worlds", 1))}

func save_to_slot(i: int) -> void:
	save_game()
	var f := FileAccess.open(slot_path(i), FileAccess.WRITE)
	if f:
		f.store_string(FileAccess.get_file_as_string(SAVE_PATH))
	sfx.play("unlock")

## ---- Stats ---------------------------------------------------------------------------------
func stat(key: String, n := 1.0) -> void:
	stats[key] = float(stats.get(key, 0.0)) + n


## ---- First-time guide: short notes that slide in once, the first time something matters ----
const HINTS := {
	"start": ["WELCOME TO BLAST PILLAR!", "Tap anywhere to drop bombs. Hold your finger down to keep dropping them."],
	"first_upgrade": ["BUY UPGRADES", "You can afford an upgrade! Open the [color=#ffcf5a]UPGRADES[/color] tab below to make your bombs stronger."],
	"auto": ["AUTO-BOMBERS", "Auto-Bombers drop bombs for you - even while the game is closed. Buy them in [color=#ffcf5a]UPGRADES[/color]."],
	"ores": ["ORES", "Ores pay out coins as you dig them. The [color=#ffcf5a]ORES[/color] tab shows every ore you've found."],
	"special": ["SPECIAL BOMBS", "Special bombs live in the bar above the menu. Tap one to fire it - then it reloads."],
	"special_used": ["RELOADING", "Special bombs reload over time. Upgrade their reload in the [color=#ffcf5a]BOMBS[/color] tab."],
	"portal": ["THE PORTAL", "Clear the pillar down to the bedrock to open the portal to the next world. Switch worlds any time in [color=#ffcf5a]WORLDS[/color]."],
	"bedrock": ["BEDROCK", "Something is hidden under every world's bedrock. A [color=#b46bff]Bedrock Bomb[/color] (BOMBS tab) breaks it - it costs Cosmic Eggs, which are buried in every world."],
	"egg": ["COSMIC EGGS", "Use your egg on a Bedrock Bomb in the [color=#ffcf5a]BOMBS[/color] tab. Bedrock goes in order, starting with Grasslands."],
	"vault": ["THE VAULT", "Dig to the very bottom of the vault - there's a prize waiting in the crate."],
}
var hint_timer := 0.0

func hint(id: String) -> void:
	if hints_seen.has(id) or not HINTS.has(id) or ui == null:
		return
	hints_seen[id] = true
	ui.notify(HINTS[id][0], HINTS[id][1], ui.icon("hint", 3), [], Callable(), 8.0)


func _check_hints(delta: float) -> void:
	hint_timer -= delta
	if hint_timer > 0.0:
		return
	hint_timer = 0.5
	if hints_seen.size() >= HINTS.size():
		return
	if float(stats.get("time", 0.0)) > 1.0:
		hint("start")
	for u in Data.UPGRADES:
		if not upgrade_maxed(u) and coins >= upgrade_cost(u):
			hint("first_upgrade")
			break
	if hints_seen.has("first_upgrade") and can_afford(auto_cost(current_world)) and int(worlds[current_world]["auto"]) == 0:
		hint("auto")
	if float(stats.get("ores", 0.0)) >= 5.0:
		hint("ores")
	for id in specials:
		hint("special")
		break
	if portal_open:
		hint("portal")
	if portal_open and not pillar.bedrock_broken():
		hint("bedrock")
	if int(ores.get(Data.BEDROCK_BOMB_ORE, 0)) > 0:
		hint("egg")
	if pillar.bedrock_broken() and pillar.cache_left():
		hint("vault")


## ---- Save backup: the whole game as one code you can copy and paste back in ----------------
const SAVE_CODE_PREFIX := "BLASTPILLAR1:"

func export_save_code() -> String:
	save_game()
	var raw := FileAccess.get_file_as_string(SAVE_PATH).to_utf8_buffer()
	var packed := raw.compress(FileAccess.COMPRESSION_GZIP)
	return SAVE_CODE_PREFIX + "%d:" % raw.size() + Marshalls.raw_to_base64(packed)


## Returns "" when the code is good (and restarts into it), otherwise what's wrong with it.
func import_save_code(code: String) -> String:
	code = code.strip_edges()
	if not code.begins_with(SAVE_CODE_PREFIX):
		return "That isn't a Blast Pillar save code."
	var rest := code.substr(SAVE_CODE_PREFIX.length())
	var colon := rest.find(":")
	if colon < 0:
		return "The save code is cut off."
	var size := int(rest.substr(0, colon))
	var packed := Marshalls.base64_to_raw(rest.substr(colon + 1))
	if packed.is_empty() or size <= 0:
		return "The save code is cut off."
	var raw := packed.decompress(size, FileAccess.COMPRESSION_GZIP)
	var d = JSON.parse_string(raw.get_string_from_utf8())
	if typeof(d) != TYPE_DICTIONARY or not d.has("version"):
		return "The save code is damaged."
	d["time"] = Time.get_unix_time_from_system()
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return "Couldn't write the save."
	f.store_string(JSON.stringify(d))
	f.close()
	_restart()
	return ""


## Replace the current game with a slot and restart from it (no offline income for the gap).
func load_slot(i: int) -> void:
	if not FileAccess.file_exists(slot_path(i)):
		sfx.play("error")
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(slot_path(i)))
	if typeof(d) != TYPE_DICTIONARY:
		sfx.play("error")
		return
	d["time"] = Time.get_unix_time_from_system()
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))
		f.close()
	_restart()

## Wipe the current game (save slots are kept) and start over in Grasslands.
func new_game() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	_restart()

## Restarts from inside the game (rebirth, loading a save, a new game) go straight back in,
## without the loading / START screen. Static, so it survives the scene being reloaded.
static var quick_restart := false
static var cheats_unlocked := false

func _restart() -> void:
	quick_restart = true
	switching_save = true
	get_tree().reload_current_scene.call_deferred()


# ---- Testing cheats ---------------------------------------------------------------------------
func cheat_coins() -> void:
	add_coins(maxf(1.0e6, coins * 1000.0))
	sfx.play("gem_rare")
	ui.refresh()

func cheat_set_coins(v: float) -> void:
	coins = maxf(0.0, v)
	total_coins = maxf(total_coins, coins)
	sfx.play("gem_rare")
	save_game()
	ui.refresh()

## Cheats: everything, all at once - every upgrade, world, bomb, relic and 20 rebirths.
func cheat_max_out() -> void:
	for u in Data.UPGRADES:
		levels[u["id"]] = int(u["max"]) if int(u["max"]) >= 0 else 60
	unlocked_worlds = Data.WORLDS.size()
	for w in Data.WORLDS.size():
		worlds[w]["done"] = true
		worlds[w]["bedrock_done"] = true
		worlds[w]["auto"] = AUTO_MAX
	for sp in Data.SPECIALS:
		specials[sp["id"]] = Data.SPECIAL_MAX_LEVEL
		cooldowns[sp["id"]] = 0.0
	for rl in Data.RELICS:
		relics[rl["id"]] = true
	rebirths = maxi(rebirths, 20)
	for oid in ore_table:
		ores[oid] = int(ores.get(oid, 0)) + 1000
		ores_seen[oid] = true
	add_coins(1.0e30)
	save_game()
	_restart()


func cheat_upgrades() -> void:
	for u in Data.UPGRADES:
		var l := lvl(u["id"]) + 5
		if int(u["max"]) >= 0:
			l = mini(l, int(u["max"]))
		levels[u["id"]] = l
	worlds[current_world]["auto"] = mini(int(worlds[current_world]["auto"]) + 5, AUTO_MAX)
	for id in specials:
		specials[id] = mini(int(specials[id]) + 5, Data.SPECIAL_MAX_LEVEL)
	sfx.play("unlock")
	ui.refresh()

func cheat_eggs() -> void:
	ores[Data.BEDROCK_BOMB_ORE] = int(ores.get(Data.BEDROCK_BOMB_ORE, 0)) + 10
	ores_seen[Data.BEDROCK_BOMB_ORE] = true
	sfx.play("gem_rare")
	ui.refresh()


# ---- Rebirth ----------------------------------------------------------------------------------
var new_rebirth_bombs: Array = []   # unlocked by the rebirth that just happened (for the popup)

func _grant_rebirth_bombs() -> void:
	for sp in Data.SPECIALS:
		if sp.has("rebirth") and rebirths >= int(sp["rebirth"]) and not specials.has(sp["id"]):
			specials[sp["id"]] = 0
			cooldowns[sp["id"]] = 0.0
			new_rebirth_bombs.append(sp["id"])


func show_rebirth_popup() -> void:
	var next := rebirths + 1
	var body := "Rebirths: [color=#ffcf5a]%d[/color]   Damage: [color=#ffcf5a]x%s[/color]   Coins: [color=#ffcf5a]x%d[/color]\n\n" % [rebirths, fmt(rebirth_mult()), int(rebirth_coin_mult())]
	var buttons: Array
	if rebirth_ready:
		body += "Start over from Grasslands with [color=#ffcf5a]x%s damage[/color] in Worlds 1-6 (the Deep Realms ignore it) and [color=#ffcf5a]x%d coins[/color] everywhere, for good.\n\nEverything resets - coins, ores, upgrades, worlds, relics and vault bombs. You keep your rebirths and rebirth bombs." % [fmt(Data.REBIRTH_MULT * next), next + 1]
		buttons = [["CANCEL", Callable(), "gold"], ["REBIRTH", func(): do_rebirth(), "red"]]
	else:
		body += "Break the Star Core at the bottom of %s's vault to rebirth again." % Data.WORLDS[Data.STAR_CORE_WORLD]["name"]
		buttons = [["CLOSE", Callable(), "green"]]
	body += "\n\n[color=#ffcf5a]REBIRTH BOMBS (PERMANENT)[/color]"
	ui.show_popup("REBIRTH" if not rebirth_ready else "REBIRTH?", body, buttons, ui.icon("rebirth", 5), [], ui.rebirth_bomb_strip())


## Start over: only the rebirth count, rebirth bombs and settings carry over.
func do_rebirth() -> void:
	if not rebirth_ready:
		sfx.play("error")
		return
	var keep := {}
	for sp in Data.SPECIALS:
		if sp.has("rebirth") and specials.has(sp["id"]):
			keep[sp["id"]] = 0
	var data := {
		"version": 1, "rebirths": rebirths + 1, "specials": keep, "just_reborn": true,
		"sound_on": sound_on, "vibrate_on": vibrate_on, "reduce_flash": reduce_flash,
		"stats": stats, "hints_seen": hints_seen, "time": Time.get_unix_time_from_system(),
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		f.close()
	_restart()


func _reborn_popup() -> void:
	var body := "Damage is now [color=#ffcf5a]x%s[/color] in Worlds 1-6, and coins [color=#ffcf5a]x%d[/color] everywhere. Blast your way down again!" % [fmt(rebirth_mult()), int(rebirth_coin_mult())]
	var spin: Array = []
	var tex: Texture2D = ui.icon("rebirth", 3)
	if not new_rebirth_bombs.is_empty():
		for id in new_rebirth_bombs:
			body += "\n[color=#b46bff]NEW BOMB: %s[/color] - %s" % [special_name(id), Data.get_special(id)["desc"]]
		tex = ui.micon("bombs", new_rebirth_bombs[0], new_rebirth_bombs[0], 3)
		spin = ["bombs", new_rebirth_bombs[0]]
		ui.rebuild_hotbar()
	new_rebirth_bombs.clear()
	sfx.play("unlock")
	ui.notify("REBIRTH #%d!" % rebirths, body, tex, spin, Callable(), 8.0)
	save_game()


## Returns how many seconds passed since the last save (for offline income).
func load_game() -> float:
	if not FileAccess.file_exists(SAVE_PATH):
		return 0.0
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return 0.0
	var d = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY:
		return 0.0
	coins = float(d.get("coins", 0.0))
	total_coins = float(d.get("total_coins", 0.0))
	reduce_flash = bool(d.get("reduce_flash", false))
	stats = d.get("stats", {}) if typeof(d.get("stats")) == TYPE_DICTIONARY else {}
	if typeof(d.get("hints_seen")) == TYPE_DICTIONARY:
		hints_seen = d["hints_seen"]
	elif total_coins > 0.0 or int(d.get("rebirths", 0)) > 0:
		for h in HINTS:
			hints_seen[h] = true   # a save from before the guide existed: you know the game already
	levels = _int_dict(d.get("levels", {}))
	ores = _int_dict(d.get("ores", {}))
	ores_seen = d.get("ores_seen", {}) if typeof(d.get("ores_seen")) == TYPE_DICTIONARY else {}
	specials = {}
	var sp = d.get("specials", {})
	if typeof(sp) == TYPE_DICTIONARY:
		for k in sp:
			specials[k] = 0 if typeof(sp[k]) == TYPE_BOOL else int(sp[k])
	if specials.has("lava"):
		specials["acid"] = specials["lava"]
		specials.erase("lava")
	for old_id in RENAMED_SPECIALS:   # bombs that were replaced keep their reload level
		if specials.has(old_id):
			specials[RENAMED_SPECIALS[old_id]] = specials[old_id]
			specials.erase(old_id)
	rebirths = maxi(0, int(d.get("rebirths", 0)))
	rebirth_ready = bool(d.get("rebirth_ready", false))
	just_reborn = bool(d.get("just_reborn", false))
	relics = {}
	hide_early_worlds = bool(d.get("hide_early_worlds", false))
	var rl = d.get("relics", {})
	if typeof(rl) == TYPE_DICTIONARY:
		for k in rl:
			if not Data.get_relic(str(k)).is_empty():
				relics[str(k)] = true
	_grant_rebirth_bombs()
	mirror_copy = str(d.get("mirror_copy", d.get("last_special", "")))
	mirror_copy = RENAMED_SPECIALS.get(mirror_copy, mirror_copy)
	cooldowns = {}
	var cd = d.get("cooldowns", {})
	if typeof(cd) == TYPE_DICTIONARY:
		for k in cd:
			cooldowns[RENAMED_SPECIALS.get(k, {"lava": "acid"}.get(k, k))] = float(cd[k])
	unlocked_worlds = clampi(int(d.get("unlocked_worlds", 1)), 1, Data.WORLDS.size())
	current_world = clampi(int(d.get("current_world", 0)), 0, unlocked_worlds - 1)
	sound_on = bool(d.get("sound_on", true))
	vibrate_on = bool(d.get("vibrate_on", true))
	sfx.enabled = sound_on
	var ws = d.get("worlds", [])
	if typeof(ws) == TYPE_ARRAY:
		for i in mini(ws.size(), worlds.size()):
			if typeof(ws[i]) != TYPE_DICTIONARY:
				continue
			var src: Dictionary = ws[i]
			var e: Dictionary = worlds[i]
			e["seed"] = int(src.get("seed", e["seed"]))
			e["state"] = src.get("state", {}) if typeof(src.get("state")) == TYPE_DICTIONARY else {}
			e["auto"] = int(src.get("auto", 0))
			e["done"] = bool(src.get("done", false))
			e["depth"] = float(src.get("depth", 0.0))
			e["ema_coins"] = float(src.get("ema_coins", 0.0))
			e["ema_ores"] = src.get("ema_ores", {}) if typeof(src.get("ema_ores")) == TYPE_DICTIONARY else {}
			if bool(src.get("bedrock_broken", false)):
				e["bedrock_broken"] = true
			if bool(src.get("bedrock_done", false)) or bool(src.get("bedrock_broken", false)):
				e["bedrock_done"] = true
			e["empty"] = bool(src.get("empty", false))
			for key in ["hp_scale", "coin_scale"]:
				if src.has(key):
					e[key] = float(src[key])
			# a realm entered before REALM_TOUGHNESS was changed: retune it to the current value
			if e.has("hp_scale"):
				var old_t := float(src.get("realm_t", 1.8))
				if absf(old_t - REALM_TOUGHNESS) > 0.0001:
					e["hp_scale"] = maxf(1.0, float(e["hp_scale"]) * REALM_TOUGHNESS / old_t)
				e["realm_t"] = REALM_TOUGHNESS
	# older saves: a world whose vault prize you already have had its bedrock broken before
	for vault_bomb in Data.SPECIALS:
		if vault_bomb.has("find") and specials.has(vault_bomb["id"]):
			worlds[int(vault_bomb["find"])]["bedrock_done"] = true
	for vault_relic in Data.RELICS:
		if relics.has(vault_relic["id"]):
			worlds[int(vault_relic["find"])]["bedrock_done"] = true
	if rebirth_ready:
		worlds[Data.STAR_CORE_WORLD]["bedrock_done"] = true
	_try_unlock()
	current_world = clampi(current_world, 0, unlocked_worlds - 1)
	var t := float(d.get("time", 0.0))
	return maxf(0.0, Time.get_unix_time_from_system() - t) if t > 0.0 else 0.0


func _int_dict(v) -> Dictionary:
	var out := {}
	if typeof(v) == TYPE_DICTIONARY:
		for k in v:
			out[str(k)] = int(v[k])
	return out


# =============================================================================================
# Number formatting
# =============================================================================================

const SUFFIXES := ["K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc"]

func fmt(n: float) -> String:
	if n < 1000.0:
		if n < 10.0 and n != floorf(n):
			return "%.1f" % n
		return str(int(floorf(n)))
	var e := int(floor(log(n) / log(1000.0)))
	if e - 1 < SUFFIXES.size():
		return "%.2f%s" % [n / pow(1000.0, e), SUFFIXES[e - 1]]
	var e10 := int(floor(log(n) / log(10.0)))
	return "%.2fe%d" % [n / pow(10.0, e10), e10]
