extends Node3D
## An ore piece that pops out of a broken block, bounces up, spins and shrinks away.
## Uses your Blockbench model from res://models/ores/<ore_id>.glb when it exists.

var vel := Vector3.ZERO
var age := 0.0
var lifetime := 1.1
var spin_speed := 0.0


func _ready() -> void:
	vel = Vector3(randf_range(-1.5, 1.5), randf_range(5.0, 7.5), randf_range(-1.5, 1.5))
	spin_speed = randf_range(4.0, 8.0)
	rotation = Vector3(randf() * TAU, randf() * TAU, 0)


func _process(delta: float) -> void:
	age += delta
	vel.y -= 14.0 * delta
	position += vel * delta
	rotate_y(spin_speed * delta)
	var t := age / lifetime
	if t > 0.6:
		var s := clampf(1.0 - (t - 0.6) / 0.4, 0.0, 1.0)
		scale = Vector3(s, s, s)
	if age >= lifetime:
		queue_free()
