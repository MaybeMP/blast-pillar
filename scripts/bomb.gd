extends RigidBody3D
## A falling bomb. The fuse starts burning when it first hits the pillar,
## then it explodes (the game handles what each kind of bomb does).

const RADIUS := 0.28
## How big each bomb model is drawn (longest side, in meters). The cluster is wider because of its rope.
const SIZES := {"bomb": 0.62, "mini": 0.5, "drill": 0.62, "cluster": 0.9, "acid": 0.66, "mega": 0.95,
	"chain": 0.62, "freeze": 0.78, "magnet": 0.62, "mirror": 0.62, "blackhole": 1.0, "bedrock": 0.8,
	"spore": 0.62, "tnt": 0.62, "gold": 0.66, "sushi": 0.7, "grow": 0.66, "moon": 0.9}

var game
var kind := "bomb"
var fuse := 1.5
var fuse_left := -1.0
var exploded := false
var age := 0.0
var spark_timer := 0.0
var visual: Node3D
var spinner: Node3D           # the part of the model that spins (the drill bit)
var drilling := false
var touched_blocks := false
var drill_steps := 0
var drill_timer := 0.0

const DRILL_STEPS := 16       # how many blocks deep the drill bores (0.5m each)
## Bomb models made out of mini bombs, scaled so each little bomb matches a real mini bomb.
const MADE_OF_MINIS := ["chain", "sticky"]
## Collision ball size for oddly shaped bombs, as a share of the model size.
const COLLIDE_SCALE := {"chain": 0.55, "blackhole": 0.6}
## Parts of a model that spin, matched by node name (lowercase, "contains").
const SPIN_PARTS := ["cone", "drillbottom", "bit", "spin"]


func _ready() -> void:
	var size := float(SIZES.get(kind, 0.62))
	var cl: float = game.model_longest("bombs", "cluster")
	var mi: float = game.model_longest("bombs", "mini")
	var mini_size := float(SIZES["cluster"]) * mi / cl if cl > 0.0 and mi > 0.0 else 0.5
	if kind == "mini":
		# same size as the little bombs on the cluster model (both models use the same units)
		size = mini_size
	elif kind in MADE_OF_MINIS:
		# models built from mini bombs (like the Chain Bomb's 4 linked bombs): each bomb in it is
		# exactly mini-bomb size, however long the whole thing is
		var me: float = game.model_longest("bombs", kind)
		if me > 0.0 and mi > 0.0:
			size = mini_size * me / mi
	var cs := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = RADIUS * clampf(size / 0.62, 0.35, 1.6)
	if COLLIDE_SCALE.has(kind):
		# long or flat shapes: a snugger ball so they sit on the blocks instead of hovering
		sphere.radius = RADIUS * clampf(size / 0.62 * float(COLLIDE_SCALE[kind]), 0.35, 1.6)
	cs.shape = sphere
	add_child(cs)
	mass = 2.0
	var mat := PhysicsMaterial.new()
	mat.bounce = 0.25
	mat.friction = 0.7
	physics_material_override = mat
	collision_layer = 2
	collision_mask = 1
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 1
	body_entered.connect(_on_hit)
	visual = game.make_model("bombs", kind, size, game.bomb_color(kind))
	add_child(visual)
	if kind == "tnt":
		lock_rotation = true      # a block of TNT stays upright, like in Minecraft
		visual.rotation.y = randf() * TAU
		_tnt_flash = StandardMaterial3D.new()
		_tnt_flash.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_tnt_flash.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_tnt_flash.albedo_color = Color(1, 1, 1, 0.0)
		_set_overlay(visual, _tnt_flash)
		_tnt_scale = visual.scale
		return
	if kind == "grow":
		lock_rotation = true      # no tumbling: the red target on its front always faces the player
		_face_camera()
		return
	if kind == "drill":
		lock_rotation = true      # falls upright, bit pointing down
		spinner = _find_spinner(visual)
		if spinner == null:
			spinner = visual
	else:
		angular_velocity = Vector3(randf_range(-3, 3), 0, randf_range(-3, 3))


func _find_spinner(node: Node) -> Node3D:
	var n := String(node.name).to_lower()
	if node is Node3D and node != visual:
		for key in SPIN_PARTS:
			if n.contains(key):
				return node
	for c in node.get_children():
		var found := _find_spinner(c)
		if found:
			return found
	return null


func light(seconds: float) -> void:
	if fuse_left < 0.0:
		fuse_left = seconds


func _on_hit(body: Node) -> void:
	# only blocks light the fuse - bouncing off the invisible side walls doesn't count
	if body == game.pillar.walls:
		return
	if kind == "sticky":
		_stick()
		return
	if kind == "grow":
		# sits where it lands and soaks up taps until the game sets it off
		if not stuck:
			_stick()
			game.grow_landed(self)
		return
	if body is RigidBody3D:
		# landed on another bomb: a pile lights up once the bomb underneath has hit the blocks
		if not body.get("touched_blocks"):
			return
	touched_blocks = true
	if kind == "drill":
		if not drilling:
			_start_drilling()
		return
	if fuse_left < 0.0:
		fuse_left = fuse
		if kind == "tnt":
			# primed: the fuse hisses and it gives a little hop
			game.sfx.play("tnt_fuse", 1.0, 2.0, 0.05)
			apply_central_impulse.call_deferred(Vector3(0, mass * 2.2, 0))
			return
		game.sfx.play("land", randf_range(0.9, 1.1), -8.0)


## Sticky Bomb slime balls: glue to whatever they hit (blocks or other balls) and stay put,
## even if the block underneath gets blown away, until their fuse runs out.
var stuck := false
var sticky_group = null      # the rain this ball belongs to; they all go off together

func _stick() -> void:
	if stuck:
		return
	stuck = true
	touched_blocks = true
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	set_deferred("freeze", true)
	set_deferred("linear_velocity", Vector3.ZERO)
	set_deferred("angular_velocity", Vector3.ZERO)
	if sticky_group != null:
		game.sticky_landed(sticky_group)
	elif fuse_left < 0.0 and kind != "grow":
		fuse_left = fuse
	game.sfx.play("land", randf_range(1.3, 1.6), -10.0)


func _start_drilling() -> void:
	drilling = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	linear_velocity = Vector3.ZERO
	game.sfx.play("land", 0.7)


func _physics_process(delta: float) -> void:
	age += delta
	if drilling:
		drill_timer -= delta
		if drill_timer <= 0.0:
			drill_timer = 0.07
			game.drill_step(global_position)
			global_position.y -= 0.5
			drill_steps += 1
			if drill_steps >= DRILL_STEPS or global_position.y < game.pillar.solid_floor_y() + 0.3:
				explode()
		return
	if fuse_left >= 0.0:
		fuse_left -= delta
		if fuse_left <= 0.0:
			explode()
			return
	if age > (30.0 if kind == "grow" else 12.0):
		explode()
		return
	if global_position.y < game.pillar.bottom_y() - 6.0:
		queue_free()  # fell through the bottom of the pillar


## TNT: once lit it flashes white every quarter second, and swells up just before it blows,
## the way primed TNT does in Minecraft.
var _tnt_flash: StandardMaterial3D
var _tnt_scale := Vector3.ONE

func _set_overlay(node: Node, m: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_overlay = m
	for c in node.get_children():
		_set_overlay(c, m)


func _tnt_animate() -> void:
	if _tnt_flash == null or fuse_left < 0.0:
		return
	var burnt := fuse - fuse_left
	_tnt_flash.albedo_color.a = 0.8 if int(burnt / 0.25) % 2 == 0 else 0.0
	if fuse_left < 0.5:
		var f := 1.0 - fuse_left / 0.5
		f = f * f * f * f
		visual.scale = _tnt_scale * (1.0 + f * 0.3)


## Grow Bomb: its model's front (-Z, where the red target is painted) turns to look at the camera.
func _face_camera() -> void:
	var cam: Camera3D = game.camera
	if cam == null or not visual.is_inside_tree():
		return
	var to_cam := cam.global_position - visual.global_position
	if to_cam.length_squared() < 0.0001:
		return
	visual.look_at(cam.global_position, Vector3.UP)


func _process(delta: float) -> void:
	_tnt_animate()
	if kind == "grow":
		_face_camera()
	if spinner:
		spinner.rotate_object_local(Vector3.UP, (32.0 if drilling else 9.0) * delta)
	spark_timer -= delta
	if spark_timer <= 0.0 and kind != "tnt":   # TNT is just a block, no fuse sticking out
		spark_timer = 0.06
		var up: Vector3 = visual.global_transform.basis.y.normalized() if kind == "grow" else global_transform.basis.y
		game.fx.spark(global_position + up * 0.4)


func explode() -> void:
	if exploded:
		return
	exploded = true
	game.on_bomb_explode(self)
	queue_free()
