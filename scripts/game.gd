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
var storm_count := 0             # Storm Battery: counts normal bombs going off
var cooldowns := {}
var sound_on := true
var vibrate_on := true
var show_stats := false
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
	_load_world(current_world)
	await _render_icons()
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
	sfx.play("portal")
	_load_world(w)
	save_game()
	ui.rebuild_tab()
	ui.refresh()


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
void fragment() {
	vec2 uv = floor(UV * vec2(16.0, 24.0)) / vec2(16.0, 24.0) - 0.5;
	uv.y *= 1.5;
	float a = atan(uv.y, uv.x);
	float r = length(uv);
	float swirl = sin(a * 3.0 + r * 18.0 - TIME * 4.0) * 0.5 + 0.5;
	vec3 c = mix(vec3(0.3, 0.08, 0.6), vec3(0.65, 0.3, 1.0), step(0.5, swirl));
	c = mix(c, vec3(0.9, 0.75, 1.0), step(r, 0.12) * 0.6);
	ALBEDO = c;
}
"""
	var qmat := ShaderMaterial.new()
	qmat.shader = sh
	quad.material_override = qmat
	portal_node.add_child(quad)


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
		sfx.play("portal", 1.0, 0.0, 0.5)
		if Data.WORLDS[current_world]["treasure"]["id"] == Data.BEDROCK_BOMB_ORE:
			_grant_eggs(first_time)
		if not first_time:
			return
		var w := current_world
		_try_unlock()
		if w + 1 < Data.WORLDS.size() and unlocked_worlds <= w + 1:
			# the next world is a realm whose door needs a hidden bomb you don't have yet
			var need := world_needs(w + 1)
			var home := special_home(need)
			ui.show_popup("YOU HIT BEDROCK!",
				"You blasted all the way down %s.\n\nThe portal to [color=#ffcf5a]%s[/color] is sealed. It opens once you find the [color=#b46bff]%s[/color], hidden under the bedrock of %s." % [Data.WORLDS[w]["name"], Data.WORLDS[w + 1]["name"], special_name(need), Data.WORLDS[home]["name"]],
				[["OK", Callable(), "gold"]], ui.world_icon(w, 5))
		elif w + 1 < Data.WORLDS.size():
			var next_name: String = Data.WORLDS[w + 1]["name"]
			ui.show_popup("YOU HIT BEDROCK!",
				"You blasted all the way down %s.\nA portal to [color=#ffcf5a]%s[/color] opened on the back wall!\n\nSomething is hidden under the bedrock...\nYou can always come back from the WORLDS tab." % [Data.WORLDS[w]["name"], next_name],
				[["STAY", Callable(), "gold"], ["ENTER PORTAL", func(): travel(w + 1), "green"]], ui.world_icon(w + 1, 5))
		else:
			ui.show_popup("YOU CONQUERED IT ALL!", "Every pillar in every world and every realm has been blasted down to bedrock. Legendary.\n\nHave you found every hidden bomb?",
				[["NICE", Callable(), "green"]], ui.micon("bombs", "mega", "mega", 5), ["bombs", "mega"])
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

func bomb_power() -> float:
	var p := 2.5 * pow(1.28, lvl("power")) * rebirth_mult()
	if has_relic("golden_bomb"):
		p *= Data.GOLDEN_RELIC_MULT
	return p

## +25% damage for every rebirth (added up: 4 rebirths = 2x).
func rebirth_mult() -> float:
	return 1.0 + Data.REBIRTH_DAMAGE * rebirths

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

func ore_value(oid: String) -> float:
	var v := float(ore_table[oid]["value"]) * value_mult() * coin_scale(int(ore_table[oid]["world"]))
	return v * (Data.ORE_RELIC_MULT if has_relic("pearl_of_plenty") else 1.0)


# ---- The Deep Realms (worlds 7+) -------------------------------------------------------------
## How much tougher a realm is than its base numbers, relative to your bombs when you first enter.
## Tuned so that walking into a realm feels like starting Grasslands on day one.
const REALM_TOUGHNESS := 0.6
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
	# rebirth damage isn't counted, so rebirths make the realms easier
	worlds[w]["hp_scale"] = maxf(1.0, bomb_power() / rebirth_mult() / 2.5 * float(bombs_per_tap()) * r * r * REALM_TOUGHNESS)
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
	return opened

func upgrade_effect(id: String) -> String:
	match id:
		"radius": return "%.1fm blast" % blast_radius()
		"power":
			var extra := ""
			if rebirths > 0:
				extra += "  rebirth x%.2f" % rebirth_mult()
			if has_relic("golden_bomb"):
				extra += "  golden x%.1f" % Data.GOLDEN_RELIC_MULT
			return "%s power%s" % [fmt(bomb_power()), extra]
		"multi": return ("%d bombs per tap" if bombs_per_tap() > 1 else "%d bomb per tap") % bombs_per_tap()
		"fuse": return "%.2fs fuse" % fuse_time()
		"value": return "x%s ore coins" % fmt(value_mult())
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
	# the Mirror Bomb reloads as long as the bomb it just copied does
	cooldowns[id] = special_cooldown(mirror_payload if id == "mirror" else id)
	if id in MIRRORABLE:
		mirror_copy = id
	if id == "sticky":
		_sticky_rain()
		sfx.play("drop", 1.3)
		ui.refresh()
		return
	_spawn_bomb(id, _spawn_point(0.6))
	sfx.play("drop", 0.8)
	ui.refresh()

## Buy/sell ores one at a time. Both use the same price: what the ore earns when you mine it.
## Cosmic Eggs only come from reaching the bottom of World 6.
func ore_tradable(oid: String) -> bool:
	return oid != Data.BEDROCK_BOMB_ORE


func _grant_eggs(first_time: bool) -> void:
	var eid: String = Data.BEDROCK_BOMB_ORE
	ores[eid] = int(ores.get(eid, 0)) + Data.EGGS_PER_RUN
	ores_seen[eid] = true
	ui.toast_ore(eid, Data.EGGS_PER_RUN)
	if not first_time:
		# the first time, the "you hit bedrock" popup is enough; after a reset, say what you got
		ui.show_popup("+%d COSMIC EGG" % Data.EGGS_PER_RUN,
			"You reached the bottom of %s again.\n%d Cosmic Eggs make a Bedrock Bomb (BOMBS tab).\nYou have %d." % [Data.WORLDS[current_world]["name"], Data.BEDROCK_BOMB_COST, int(ores[eid])],
			[["NICE", Callable(), "green"]], ui.micon("ores", eid, "gem", 5, ore_table[eid]["color"]), ["ores", eid])
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
	if bombs_node.get_child_count() >= MAX_BOMBS:
		return
	for i in bombs_per_tap():
		_spawn_bomb("bomb", _spawn_point(1.0))
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
	var __t := Time.get_ticks_usec()
	_spawn_bomb_now(kind, pos, vel, lit)
	prof("new bombs", __t)


func _spawn_bomb_now(kind: String, pos: Vector3, vel := Vector3(0, -3, 0), lit := -1.0) -> void:
	var b = BombScript.new()
	b.game = self
	b.kind = kind
	b.fuse = fuse_time() if kind != "mini" else 0.2
	if overclocked() and kind == "bomb":
		b.fuse = 0.05
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
	if overclocked():
		power *= 2.0
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
		"mega":
			_mega(pos)
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
		"anchor":
			_anchor(pos, radius, power)
		"overclock":
			_overclock(pos, radius, power)
		"lightning":
			_lightning(pos, power)
		"phantom":
			_phantom(pos, radius, power)
		"supernova":
			_supernova(pos, radius, power)
		"bomb":
			storm_count += 1
			if has_relic("storm_battery") and storm_count % Data.STORM_EVERY == 0:
				_mega(pos)
			else:
				_blast(pos, radius, power)
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


const RENAMED_SPECIALS := {"prism": "mirror", "quake": "sticky"}

## Mirror Bomb: becomes a copy of the last special bomb you fired, right where it lands.
## (Drills land and bore as usual; everything else goes off on the spot.) It needs a special
## fired since it was last used - until then it stays locked, even when its reload is done.
const MIRRORABLE := ["drill", "cluster", "acid", "mega", "chain", "freeze", "sticky", "magnet", "blackhole",
	"spore", "anchor", "overclock", "lightning", "phantom", "supernova"]
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


## Anchor Bomb: sinks straight down through 24 layers, blasting every 2 layers.
func _anchor(pos: Vector3, radius: float, power: float) -> void:
	var token := world_token
	var p := pos
	sfx.play("explode_big", 0.7, -2.0, 0.1)
	for i in 12:
		if token != world_token or not is_inside_tree():
			return
		_blast(p, radius, power, Color(0.5, 0.7, 0.9), i == 0, i > 0)
		p.y -= 2.0 * Data.VOXEL
		shake = maxf(shake, 0.25)
		await get_tree().create_timer(0.09).timeout


## Overclock Bomb: for OVERCLOCK_SECONDS every bomb you drop has an instant fuse and double power.
const OVERCLOCK_SECONDS := 10.0
var overclock_until := 0

func overclocked() -> bool:
	return Time.get_ticks_msec() < overclock_until

func overclock_left() -> float:
	return maxf(0.0, (overclock_until - Time.get_ticks_msec()) / 1000.0)

func _overclock(pos: Vector3, radius: float, power: float) -> void:
	_blast(pos, radius, power, Color(1.0, 0.8, 0.3), true)
	overclock_until = Time.get_ticks_msec() + int(OVERCLOCK_SECONDS * 1000.0)
	sfx.play("unlock", 1.4, 0.0, 0.1)


## Lightning Bomb: 8 bolts hit random columns one after another, each boring 10 layers down.
func _lightning(pos: Vector3, power: float) -> void:
	var token := world_token
	_blast(pos, 0.8, power, Color(1.0, 0.95, 0.4), false, true)
	for bolt in 8:
		if token != world_token or not is_inside_tree():
			return
		var top: Vector3 = pillar.high_point(1)
		var from := Vector3(top.x, top.y + 6.0, top.z)
		fx.streak(from, top, Color("fff04a"))
		for j in 10:
			var p := top + Vector3(0, -j * Data.VOXEL, 0)
			_apply(pillar.explode(p, 0.7, power * 2.0), p)
			if j % 3 == 0:
				fx.beam(p, Color("fff8a0"))
		sfx.play("crack", 1.6, 0.0, 0.05)
		shake = maxf(shake, 0.35)
		await get_tree().create_timer(0.15).timeout


## Phantom Bomb: passes through 12 layers of rock like a ghost, then a huge blast deep inside.
func _phantom(pos: Vector3, radius: float, power: float) -> void:
	var token := world_token
	var deep := pos + Vector3(0, -12.0 * Data.VOXEL, 0)
	fx.streak(pos, deep, Color("c8ffff"))
	sfx.play("portal", 1.6, -2.0, 0.1)
	await get_tree().create_timer(0.5).timeout
	if token != world_token or not is_inside_tree():
		return
	_blast(deep, radius, power, Color(0.7, 1.0, 1.0), true)


## Supernova Bomb: charges for a moment (pulling bombs in), then erupts.
func _supernova(pos: Vector3, radius: float, power: float) -> void:
	var token := world_token
	sfx.play("portal", 0.4, 2.0, 0.1)
	for i in 10:
		if token != world_token or not is_inside_tree():
			return
		fx.implode(pos, 3.0 - i * 0.25)
		shake = maxf(shake, 0.1 + i * 0.03)
		await get_tree().create_timer(0.12).timeout
	_apply(pillar.dissolve(pos, 6.0 * Data.VOXEL * reach(), 0.6), pos)
	_blast(pos, radius, power, Color(1.0, 0.75, 0.3), true)
	fx.explosion(pos, 4.0, Color(1.0, 0.95, 0.7))
	shake = maxf(shake, 2.0)
	_vibrate(150)


# ---------------------------------------------------------------------------------------------
# Bedrock, vault and the bomb cache
# ---------------------------------------------------------------------------------------------

func treasure_id(w: int) -> String:
	return Data.WORLDS[w]["treasure"]["id"]


## Can the Bedrock Bomb be used in the world you're in right now?
func bedrock_bomb_state() -> String:
	if not pillar.reached_bedrock():
		return "not_reached"
	if pillar.bedrock_broken():
		return "broken"
	if int(ores.get(Data.BEDROCK_BOMB_ORE, 0)) < Data.BEDROCK_BOMB_COST:
		return "need_treasure"
	return "ready"


func use_bedrock_bomb() -> void:
	if bedrock_bomb_state() != "ready" or ui.popup_open():
		sfx.play("error")
		return
	ores[Data.BEDROCK_BOMB_ORE] = int(ores.get(Data.BEDROCK_BOMB_ORE, 0)) - Data.BEDROCK_BOMB_COST
	_spawn_bomb("bedrock", _spawn_point(0.3))
	sfx.play("drop", 0.6)
	ui.refresh()


func _break_bedrock() -> void:
	var spots: Array = pillar.break_bedrock()
	for i in mini(spots.size(), 60):
		var p: Vector3 = spots[randi() % spots.size()]
		fx.debris(p, Color("4a4a4e"), p + Vector3(randf_range(-1, 1), -1, randf_range(-1, 1)))
	fx.explosion(Vector3(0, -pillar.depth * Data.VOXEL, 0), 3.0, Color(0.7, 0.7, 0.75))
	sfx.play("explode_big", 0.5, 4.0, 0.1)
	shake = maxf(shake, 1.5)
	_vibrate(120)
	worlds[current_world]["bedrock_broken"] = true
	worlds[current_world]["empty"] = false
	ui.show_popup("THE BEDROCK SHATTERED!",
		("A vault lies below %s.\nDig to the bottom to find the bomb cache." if current_world < Data.ORIGINAL_WORLDS else "A vault full of ore lies below %s.\nDig it out!") % Data.WORLDS[current_world]["name"],
		[["DIG IN", Callable(), "green"]], ui.micon("bombs", "bedrock", "bedrock", 5), ["bombs", "bedrock"])
	save_game()


## Breaking the bomb cache at the bottom of a vault unlocks that world's hidden bomb (Worlds 1-6),
## a relic (Worlds 7-11), or - in the Starforge - lets you rebirth.
func _open_cache(w: int) -> void:
	if w == Data.STAR_CORE_WORLD:
		rebirth_ready = true
		save_game()
		show_rebirth_popup()
		ui.rebuild_tab()
		return
	for rl in Data.RELICS:
		if int(rl["find"]) == w and not relics.has(rl["id"]):
			relics[rl["id"]] = true
			sfx.play("unlock")
			_vibrate(100)
			var col := Color(rl["col"])
			ui.show_popup("YOU FOUND THE %s!" % rl["name"].to_upper(),
				"A relic!\n%s.\nIt works in every world until you rebirth." % rl["desc"],
				[["AWESOME", Callable(), "green"]], ui.micon("relics", rl["id"], "gem", 5, col), ["relics", rl["id"]])
			ui.rebuild_tab()
			save_game()
			return
	for sp in Data.SPECIALS:
		if int(sp.get("find", -1)) == w and not specials.has(sp["id"]):
			specials[sp["id"]] = 0
			cooldowns[sp["id"]] = 0.0
			sfx.play("unlock")
			_vibrate(100)
			var body := "%s.\nIt's in your hotbar now." % sp["desc"]
			for ow in _try_unlock():
				body += "\n\n[color=#ffcf5a]%s[/color] has opened! Travel there from the WORLDS tab." % Data.WORLDS[ow]["name"]
			for rw in range(Data.ORIGINAL_WORLDS, Data.WORLDS.size()):
				if world_needs(rw) == sp["id"] and rw >= unlocked_worlds:
					body += "\n\nThis bomb opens [color=#ffcf5a]%s[/color] once you reach the bottom of %s." % [Data.WORLDS[rw]["name"], Data.WORLDS[rw - 1]["name"]]
			ui.show_popup("YOU FOUND THE %s!" % sp["name"].to_upper(), body,
				[["AWESOME", Callable(), "green"]], ui.micon("bombs", sp["id"], sp["id"], 5), ["bombs", sp["id"]])
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
	var best_rank := -1
	var cache_world := -1
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
			var v := ore_value(oid)
			gained += v
			counts[oid] = int(counts.get(oid, 0)) + 1
			best_rank = maxi(best_rank, int(def.get("rank", 0)))
			_spawn_gem(oid, p)
			ui.toast_ore(oid, 1)
		else:
			gained += float(def.get("coins", 0.0)) * value_mult() * coin_scale(int(def["world"]))
			if debris and debris_budget > 0 and randf() < 0.55:
				fx.debris(p, def["c1"], center)
				debris_budget -= 1
	if cache_world >= 0:
		_open_cache.call_deferred(cache_world)
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
			if folder in ["bombs", "relics"] and not _soft_checked.has(path):
				_soft_checked[path] = true
				_soften_alpha(inst)
			if folder == "ores":
				# shared grey shape -> recolor for this ore; every ore model gets baked face shading
				var shared: bool = not path.get_file().get_basename() == id
				_shade_ore(inst, ore_table[id]["color"] if shared else Color.WHITE)
			if folder == "ores" and Data.ORE_SHAPES.has(id):
				size *= float(shape_scale.get(Data.ORE_SHAPES[id], 1.0))
			return _fit(inst, size)
	return _placeholder(folder, size, color)


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
	for ext in [".glb", ".gltf"]:
		var p := "res://models/%s/%s%s" % [folder, id, ext]
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
	if folder == "ores":
		extra += "|%s|%.3f" % [ore_table[id]["color"].to_html(), float(shape_scale.get(Data.ORE_SHAPES.get(id, ""), 1.0))]
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
	return 0.9


## Bombs and ores: a spinning, bobbing loop (like a dropped item in Minecraft).
## All frames of one model render at once in a row of small viewports, then get cleaned up a
## few per frame so the game doesn't stutter.
func _render_spin_icons() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var keys: Array = []
	for k in model_icons.keys():
		if not String(k).begins_with("world/") and not model_icon_frames.has(k):
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
			var node := make_icon_model(folder, id, _icon_size(folder, id), Color.BLACK)
			var t := float(k) / ICON_FRAMES
			node.rotation.y = _icon_turn(node) + float(ICON_TURN.get(id, 0.0)) + TAU * t
			node.position.y = sin(TAU * t) * ICON_BOB
			v.get_meta("cam").size = 1.3 if folder in ["bombs", "relics"] else 1.0
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

	# auto-bombers in other worlds earn from their averages
	bg_timer += delta
	if bg_timer >= 1.0:
		bg_timer -= 1.0
		for w in unlocked_worlds:
			if w != current_world and int(worlds[w]["auto"]) > 0 and not world_empty(w):
				_idle_income(w, auto_rate(w) * IDLE_EFFICIENCY)

	for id in cooldowns.keys():
		cooldowns[id] = maxf(0.0, float(cooldowns[id]) - delta)

	if portal_open and portal_node:
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
	var lines := "You were gone for %s.\nYour auto-bombers found:\n\n[color=#ffcf5a]%s coins[/color]" % [_duration(seconds), fmt(total_c)]
	var sorted_ores := total_o.keys()
	sorted_ores.sort_custom(func(a, b): return ore_table[a]["value"] > ore_table[b]["value"])
	for i in mini(5, sorted_ores.size()):
		var k: String = sorted_ores[i]
		lines += "\n%s %s" % [fmt(float(total_o[k])), ore_table[k]["name"]]
	ui.show_popup("WELCOME BACK", lines, [["COLLECT", Callable(), "green"]], ui.icon("auto", 5))
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
		"relics": relics, "rebirths": rebirths, "rebirth_ready": rebirth_ready,
		"sound_on": sound_on, "vibrate_on": vibrate_on,
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

func _restart() -> void:
	switching_save = true
	get_tree().reload_current_scene.call_deferred()


# ---- Testing cheats ---------------------------------------------------------------------------
func cheat_coins() -> void:
	add_coins(maxf(1.0e6, coins * 1000.0))
	sfx.play("gem_rare")
	ui.refresh()

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
	ores[Data.BEDROCK_BOMB_ORE] = int(ores.get(Data.BEDROCK_BOMB_ORE, 0)) + Data.BEDROCK_BOMB_COST
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
	var body := "Start over from Grasslands with [color=#ffcf5a]+%d%% damage[/color] for good.\nAfter this rebirth: [color=#ffcf5a]x%.2f damage[/color].\n\nEverything resets - coins, ores, upgrades, worlds, relics and vault bombs. You keep your rebirths and rebirth bombs.\n\n[color=#ffcf5a]REBIRTH BOMBS[/color]" % [int(Data.REBIRTH_DAMAGE * 100), 1.0 + Data.REBIRTH_DAMAGE * next]
	for sp in Data.SPECIALS:
		if not sp.has("rebirth"):
			continue
		var need := int(sp["rebirth"])
		if specials.has(sp["id"]):
			body += "\n[color=#9be36b]%s[/color]  (owned)" % sp["name"]
		else:
			body += "\n[color=#b9a990]??? - unlocks at %d rebirths[/color]" % need
	ui.show_popup("REBIRTH?", body, [["CANCEL", Callable(), "gold"], ["REBIRTH", func(): do_rebirth(), "red"]],
		ui.icon("world", 5, Color("ffcf5a")))


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
		"sound_on": sound_on, "vibrate_on": vibrate_on, "time": Time.get_unix_time_from_system(),
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		f.close()
	_restart()


func _reborn_popup() -> void:
	var body := "Damage is now [color=#ffcf5a]x%.2f[/color].\nBack to Grasslands - blast your way down again!" % rebirth_mult()
	var spin: Array = []
	var tex: Texture2D = ui.icon("world", 5, Color("ffcf5a"))
	if not new_rebirth_bombs.is_empty():
		for id in new_rebirth_bombs:
			body += "\n\n[color=#b46bff]NEW BOMB: %s[/color]\n%s" % [special_name(id), Data.get_special(id)["desc"]]
		tex = ui.micon("bombs", new_rebirth_bombs[0], new_rebirth_bombs[0], 5)
		spin = ["bombs", new_rebirth_bombs[0]]
		ui.rebuild_hotbar()
	new_rebirth_bombs.clear()
	sfx.play("unlock")
	ui.show_popup("REBIRTH #%d!" % rebirths, body, [["LET'S GO", Callable(), "green"]], tex, spin)
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
