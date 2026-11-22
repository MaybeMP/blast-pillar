extends MultiMeshInstance3D
## Cheap voxel particles: every particle is a little cube drawn through one MultiMesh.
## Used for explosion fire, smoke, block debris, fuse sparks and portal swirls.

const MAX := 700

var pos := PackedVector3Array()
var vel := PackedVector3Array()
var life := PackedFloat32Array()
var max_life := PackedFloat32Array()
var size := PackedFloat32Array()
var grav := PackedFloat32Array()
var shrink := PackedFloat32Array()   # 1 = shrinks to nothing over its life, 0 = keeps size
var col := PackedColorArray()
var spin := PackedFloat32Array()
var count := 0
var time := 0.0
var buf := PackedFloat32Array()   # all particle transforms + colors, sent to the GPU in one go


func _ready() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	mm.mesh = box
	mm.instance_count = MAX
	mm.visible_instance_count = 0
	multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3(-50, -400, -50), Vector3(100, 450, 100))
	# (packed arrays are copied by value, so each one is resized directly)
	pos.resize(MAX)
	vel.resize(MAX)
	life.resize(MAX)
	max_life.resize(MAX)
	size.resize(MAX)
	grav.resize(MAX)
	shrink.resize(MAX)
	spin.resize(MAX)
	col.resize(MAX)
	buf.resize(MAX * 16)


func add(p: Vector3, v: Vector3, c: Color, s: float, l: float, g := 9.8, sh := 1.0) -> void:
	if count >= MAX:
		return
	pos[count] = p
	vel[count] = v
	col[count] = c
	size[count] = s
	life[count] = l
	max_life[count] = l
	grav[count] = g
	shrink[count] = sh
	spin[count] = randf_range(-6.0, 6.0)
	count += 1


func _process(delta: float) -> void:
	time += delta
	var i := 0
	while i < count:
		life[i] -= delta
		if life[i] <= 0.0:
			count -= 1
			pos[i] = pos[count]
			vel[i] = vel[count]
			col[i] = col[count]
			size[i] = size[count]
			life[i] = life[count]
			max_life[i] = max_life[count]
			grav[i] = grav[count]
			shrink[i] = shrink[count]
			spin[i] = spin[count]
			continue
		var v := vel[i]
		v.y -= grav[i] * delta
		v *= 1.0 - minf(delta * 1.5, 0.5)
		vel[i] = v
		var p := pos[i] + v * delta
		pos[i] = p
		var t := life[i] / max_life[i]
		var sc := size[i] * lerpf(1.0, t, shrink[i])
		var a := time * spin[i]
		var c := cos(a) * sc
		var sn := sin(a) * sc
		var cl := col[i]
		# one 3x4 transform (spinning around Y) + color, written straight into the buffer
		var o := i * 16
		buf[o] = c; buf[o + 1] = 0.0; buf[o + 2] = sn; buf[o + 3] = p.x
		buf[o + 4] = 0.0; buf[o + 5] = sc; buf[o + 6] = 0.0; buf[o + 7] = p.y
		buf[o + 8] = -sn; buf[o + 9] = 0.0; buf[o + 10] = c; buf[o + 11] = p.z
		buf[o + 12] = cl.r; buf[o + 13] = cl.g; buf[o + 14] = cl.b; buf[o + 15] = cl.a
		i += 1
	multimesh.buffer = buf
	multimesh.visible_instance_count = count


# ------------------------------------------------------------------ presets

func explosion(p: Vector3, radius: float, tint := Color(1.0, 0.55, 0.15)) -> void:
	var n := int(clampf(8.0 + radius * 7.0, 10.0, 40.0))
	for k in n:
		var dir := Vector3(randf_range(-1, 1), randf_range(-0.2, 1.2), randf_range(-1, 1)).normalized()
		var c := tint.lerp(Color(1.0, 0.92, 0.4), randf() * 0.6)
		add(p + dir * randf() * radius * 0.3, dir * randf_range(2.0, 5.0) * (0.6 + radius * 0.4), c,
			randf_range(0.18, 0.38) * (0.7 + radius * 0.3), randf_range(0.25, 0.5), 1.0)
	# smoke
	for k in n / 4:
		var dir := Vector3(randf_range(-1, 1), randf_range(0.3, 1.0), randf_range(-1, 1)).normalized()
		var g := randf_range(0.45, 0.65)
		add(p + dir * radius * 0.4, dir * randf_range(0.8, 2.0), Color(g, g, g), randf_range(0.14, 0.26) * (0.8 + radius * 0.2),
			randf_range(0.5, 0.9), -1.5)


func debris(p: Vector3, c: Color, from: Vector3) -> void:
	var dir := (p - from).normalized() + Vector3(randf_range(-0.4, 0.4), randf_range(0.3, 1.0), randf_range(-0.4, 0.4))
	add(p, dir * randf_range(3.0, 7.0), c, randf_range(0.12, 0.22), randf_range(0.6, 1.1), 18.0, 0.3)


## A whole block being pulled into a black hole: block-sized, flies to the centre, shrinking to
## nothing exactly as it arrives.
func suck(p: Vector3, c: Color, center: Vector3, s: float) -> void:
	var l := randf_range(0.35, 0.65)
	add(p, (center - p) / l, c, s, l, 0.0, 1.0)


## A ring-shaped burst flying outward in every direction (for big finales).
func shockwave(center: Vector3, radius: float, colors: Array) -> void:
	for k in 70:
		var a := TAU * k / 70.0
		var dir := Vector3(cos(a), randf_range(-0.25, 0.35), sin(a)).normalized()
		add(center, dir * radius * randf_range(1.6, 2.4), colors[k % colors.size()],
			randf_range(0.2, 0.4), randf_range(0.4, 0.7), 0.0)
	for k in 30:
		var dir := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
		add(center, dir * radius * randf_range(0.8, 1.6), colors[k % colors.size()], randf_range(0.25, 0.5), randf_range(0.5, 0.9), 2.0)


func spark(p: Vector3) -> void:
	add(p, Vector3(randf_range(-1, 1), randf_range(1, 2.5), randf_range(-1, 1)),
		Color(1.0, randf_range(0.5, 0.9), 0.1), randf_range(0.05, 0.09), randf_range(0.15, 0.3), 6.0)


func portal(p: Vector3, r: float) -> void:
	for k in 4:
		var a := randf() * TAU
		var off := Vector3(cos(a), 0, sin(a)) * r * randf_range(0.3, 1.0)
		add(p + off, Vector3(-off.z, randf_range(0.5, 2.0), off.x) * 0.8,
			Color(0.6, 0.2, 1.0).lerp(Color(0.2, 0.9, 1.0), randf()), randf_range(0.08, 0.18), randf_range(0.6, 1.2), -1.0)


## Green acid bubbles on the edge of the spreading acid.
func acid(center: Vector3, radius: float, half_width: float, top: float) -> void:
	for k in 10:
		var dir := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
		var p := center + dir * radius
		p.x = clampf(p.x, -half_width, half_width)
		p.z = clampf(p.z, -half_width, half_width)
		p.y = minf(p.y, top + 0.2)
		var c := Color("4fae2c").lerp(Color("c6ff5a"), randf())
		add(p, Vector3(randf_range(-0.4, 0.4), randf_range(0.6, 1.8), randf_range(-0.4, 0.4)), c,
			randf_range(0.08, 0.2), randf_range(0.4, 0.8), -0.5)


## Upright portal: sparkles drifting out of the doorway.
func portal_upright(center: Vector3, w: float, h: float) -> void:
	for k in 2:
		var p := center + Vector3(randf_range(-w, w) * 0.45, randf_range(-h, h) * 0.45, 0)
		add(p, Vector3(randf_range(-0.2, 0.2), randf_range(-0.1, 0.4), randf_range(0.3, 0.9)),
			Color(0.6, 0.2, 1.0).lerp(Color(0.85, 0.7, 1.0), randf()), randf_range(0.05, 0.12), randf_range(0.5, 1.0), -0.3)


## Freeze Bomb: ice shards bursting out.
func freeze_burst(center: Vector3, radius: float) -> void:
	for k in 50:
		var dir := Vector3(randf_range(-1, 1), randf_range(-0.6, 1), randf_range(-1, 1)).normalized()
		add(center + dir * randf() * radius * 0.4, dir * randf_range(2.0, 6.0),
			Color("bff4ff").lerp(Color.WHITE, randf() * 0.6), randf_range(0.08, 0.2), randf_range(0.5, 1.0), 4.0)


## Quake Bomb: a ring of dust shooting out across the whole slab.
func quake(y: float, half: float) -> void:
	for k in 70:
		var p := Vector3(randf_range(-half, half), y + randf_range(-0.5, 1.0), randf_range(-half, half))
		var g := randf_range(0.5, 0.75)
		add(p, Vector3(p.x, randf_range(1.0, 3.0), p.z).normalized() * randf_range(2.0, 5.0),
			Color(g, g * 0.92, g * 0.8), randf_range(0.12, 0.3), randf_range(0.5, 1.0), 6.0)


## Magnet Bomb: an ore piece flying toward the bomb.
func streak(from: Vector3, to: Vector3, c: Color) -> void:
	for k in 3:
		add(from, (to - from) * randf_range(1.6, 2.4), c, randf_range(0.08, 0.15), 0.4, 0.0)


## Prism Bomb: a bright point along a laser beam.
func beam(p: Vector3, c: Color) -> void:
	for k in 2:
		add(p + Vector3(randf_range(-0.1, 0.1), randf_range(-0.1, 0.1), randf_range(-0.1, 0.1)), Vector3.ZERO,
			c.lerp(Color.WHITE, randf() * 0.5), randf_range(0.15, 0.28), randf_range(0.2, 0.35), 0.0)


## Black Hole Bomb: dark specks being sucked inward.
## Black hole: specks of glowing gold and white gas spiralling inward (like the gas around a real one).
const IMPLODE_COLORS := [Color(1.0, 0.98, 0.92), Color(1.0, 0.93, 0.62), Color(1.0, 0.81, 0.31), Color(0.96, 0.66, 0.18)]

func implode(center: Vector3, radius: float) -> void:
	for k in 20:
		var dir := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
		var p := center + dir * (radius + randf_range(0.3, 1.5))
		add(p, (center - p) * 2.2, IMPLODE_COLORS[randi() % IMPLODE_COLORS.size()],
			randf_range(0.08, 0.18), 0.45, 0.0)


func clear_all() -> void:
	count = 0
	multimesh.visible_instance_count = 0
