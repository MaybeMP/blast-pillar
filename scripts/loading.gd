extends CanvasLayer
## The loading screen: the title from the launch picture, with every bomb in the game spinning
## in a checkerboard around it. Bombs you haven't unlocked yet are black.
## It stays up a moment after the game is ready, then fades; a tap skips it.

const PA = preload("res://scripts/pixel_art.gd")
const Data = preload("res://scripts/data.gd")
const COLUMNS := 5

var game
var root_ctl: Control
var grid: Control
var shown_at := -1.0
var done := false
var _mat: ShaderMaterial


func setup(g) -> void:
	game = g
	layer = 50
	var vp: Vector2 = g.vp_size
	root_ctl = Control.new()
	root_ctl.size = vp
	root_ctl.mouse_filter = Control.MOUSE_FILTER_STOP
	root_ctl.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(root_ctl)
	# animated sky: slowly turning sun rays, drifting pixel clouds and twinkling sparkles
	var bg := ColorRect.new()
	bg.size = vp
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SKY_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("size", vp)
	mat.set_shader_parameter("pixel", maxf(3.0, round(vp.x / 160.0)))
	mat.set_shader_parameter("centre", Vector2(0.5, (TITLE_SPAN.y + LOADING_SPAN.x) * 0.5))
	bg.material = mat
	root_ctl.add_child(bg)
	grid = Control.new()
	grid.size = vp
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_ctl.add_child(grid)
	# the title and LOADING line as real text in the pixel font, so they stay sharp on any screen
	var size := int(vp.x * 0.205)
	_text("BLAST", size, vp.y * TITLE_SPAN.x, Color("ffd64a"))
	_text("PILLAR", size, vp.y * TITLE_SPAN.x + size * 0.9, Color("ffd64a"))
	loading_label = _text("LOADING...", int(size * 0.4), vp.y * LOADING_SPAN.x, Color.WHITE)


var loading_label: Label

func _font() -> Font:
	var f = load("res://fonts/jersey10.woff")
	if f is FontFile:
		f.hinting = TextServer.HINTING_NONE
		f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	return f


const SKY_SHADER := """
shader_type canvas_item;
uniform vec2 size = vec2(720.0, 1280.0);
uniform float pixel = 6.0;              // chunky pixels, to match the game's look
uniform vec2 centre = vec2(0.5, 0.55);   // where the sun rays come from

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 4; i++) { v += a * noise(p); p *= 2.03; a *= 0.5; }
	return v;
}

void fragment() {
	vec2 px = floor(UV * size / pixel) * pixel;      // snap to the big pixel grid
	vec2 q = px / size;
	vec3 col = mix(vec3(0.31, 0.56, 0.84), vec3(0.73, 0.86, 0.96), q.y);
	// sun rays behind the bombs, slowly turning
	vec2 d = (q - centre) * vec2(size.x / size.y, 1.0);
	float r = length(d);
	float ang = atan(d.y, d.x) + TIME * 0.12;
	float ray = step(0.0, sin(ang * 10.0));
	col = mix(col, vec3(1.0, 0.95, 0.72), ray * 0.16 * (1.0 - smoothstep(0.05, 0.75, r)));
	col = mix(col, vec3(1.0, 0.93, 0.6), 0.35 * (1.0 - smoothstep(0.0, 0.32, r)));
	// two layers of clouds drifting sideways (the near one faster)
	float far = fbm(vec2(q.x * 3.0 + TIME * 0.012, q.y * 7.0));
	col = mix(col, vec3(0.86, 0.93, 1.0), step(0.66, far) * 0.55);
	float near = fbm(vec2(q.x * 2.2 - TIME * 0.025, q.y * 5.0 + 9.0));
	float cloud = step(0.68, near);
	float shade = step(0.68, fbm(vec2(q.x * 2.2 - TIME * 0.025, (q.y - 0.012) * 5.0 + 9.0)));
	col = mix(col, mix(vec3(0.78, 0.86, 0.95), vec3(1.0), shade), cloud * 0.85);
	// twinkling sparkles
	vec2 cell = floor(px / (pixel * 6.0));
	float h = hash(cell);
	if (h < 0.05) {
		float tw = pow(max(0.0, sin(TIME * 2.5 + h * 300.0)), 12.0);
		vec2 spot = floor(vec2(hash(cell + 3.1), hash(cell + 7.7)) * 6.0);
		vec2 here = floor(px / pixel) - cell * 6.0;
		float star = step(distance(here, spot), 0.5) + 0.5 * step(abs(distance(here, spot) - 1.0), 0.01) ;
		col = mix(col, vec3(1.0, 1.0, 0.9), clamp(star, 0.0, 1.0) * tw);
	}
	COLOR = vec4(col, 1.0);
}
"""


func _text(t: String, size: int, y: float, col: Color) -> Label:
	var f := _font()
	var l := Label.new()
	l.text = t
	l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color("120e0b"))
	l.add_theme_constant_override("outline_size", maxi(4, int(size * 0.16)))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.position = Vector2(0, y)
	l.size = Vector2(game.vp_size.x, size * 1.1)
	root_ctl.add_child(l)
	return l


## Call once the bomb icons are loaded: fills the checkerboard.
func fill_icons() -> void:
	var vp: Vector2 = game.vp_size
	var ids: Array = ["bomb"]
	for sp in Data.SPECIALS:
		ids.append(sp["id"])
	# a checkerboard of bombs as big as will fit between the title and LOADING; a part-filled
	# last row is centred
	var band_top := vp.y * TITLE_SPAN.y + vp.x * 0.02
	var band_bottom := vp.y * LOADING_SPAN.x - vp.x * 0.02
	var band_h := band_bottom - band_top
	var best_cols := 5
	var best_cell := 0.0
	for cols in [3, 5, 7]:
		var rows := 0
		var count := 0
		while count < ids.size():
			count += int(ceil(cols / 2.0)) if rows % 2 == 0 else cols / 2
			rows += 1
		var cell := minf(vp.x / cols, band_h / rows)
		if cell > best_cell:
			best_cell = cell
			best_cols = cols
	var cols: int = best_cols
	var cell := best_cell
	var size := cell * 0.95
	# lay out the slots row by row
	var slots: Array = []
	var r := 0
	while slots.size() < ids.size():
		var row: Array = []
		for c in cols:
			if (r + c) % 2 == 0:
				row.append(c)
		var left := ids.size() - slots.size()
		if row.size() > left:
			# last row: centre what's left, keeping the same spacing
			var span := (left - 1) * 2.0
			var start := (cols - 1) * 0.5 - span * 0.5
			row = []
			for i in left:
				row.append(start + i * 2.0)
		for c in row:
			slots.append(Vector2(float(c), float(r)))
		r += 1
	var rows_used := r
	var x0 := (vp.x - cols * cell) * 0.5
	var y0 := band_top + (band_h - rows_used * cell) * 0.5
	var k := 0
	for slot in slots:
		var centre := Vector2(x0 + (slot.x + 0.5) * cell, y0 + (slot.y + 0.5) * cell)
		var id: String = ids[k]
		k += 1
		var ic := TextureRect.new()
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_SCALE
		ic.size = Vector2(size, size)
		ic.position = centre - ic.size * 0.5
		var key := "bombs/" + id
		waiting[key] = ic
		if game.model_icon_frames.has(key):
			ic.texture = _strip(key)
			ic.material = _spin_material()
		elif game.model_icons.has(key):
			ic.texture = ImageTexture.create_from_image(game.model_icons[key])
		else:
			ic.texture = PA.icon(id, 3)
			ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var owned: bool = id == "bomb" or game.specials.has(id)
		ic.modulate = Color.WHITE if owned else Color(0, 0, 0, 0.85)
		ic.modulate.a *= 0.0
		grid.add_child(ic)
		var tw := ic.create_tween()
		tw.tween_property(ic, "modulate:a", 1.0 if owned else 0.85, 0.25).set_delay(0.02 * k)
	shown_at = Time.get_ticks_msec() / 1000.0


## Where the title and the LOADING line sit, as parts of the screen height (matches the
## launch picture shown before the game starts).
const TITLE_SPAN := Vector2(0.09, 0.29)
const LOADING_SPAN := Vector2(0.78, 0.83)


## The game is ready: LOADING... turns into a START button. Look at the bombs as long as you
## like; tapping START fades the screen away.
func finish() -> void:
	while shown_at < 0.0:
		await get_tree().process_frame
	var vp: Vector2 = game.vp_size
	var w := vp.x * 0.46
	var h := vp.x * 0.16
	var btn := Button.new()
	btn.text = "START"
	btn.add_theme_font_override("font", _font())
	btn.add_theme_font_size_override("font_size", int(h * 0.62))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		btn.add_theme_color_override(c, Color.WHITE)
	btn.add_theme_color_override("font_outline_color", Color("120e0b"))
	btn.add_theme_constant_override("outline_size", maxi(4, int(h * 0.1)))
	var pad := Vector4(h * 0.2, h * 0.1, h * 0.2, h * 0.12)
	var up := PA.frame(Color("6cbf3f"), Color("a4e877"), Color("3f7f22"), 3, false, pad)
	var down := PA.frame(Color("5aa83c"), Color("3f7f22"), Color("a4e877"), 3, true, pad)
	for st in ["normal", "hover", "focus"]:
		btn.add_theme_stylebox_override(st, up)
	btn.add_theme_stylebox_override("pressed", down)
	btn.size = Vector2(w, h)
	btn.position = Vector2((vp.x - w) * 0.5, vp.y * LOADING_SPAN.x - h * 0.2)
	btn.pivot_offset = btn.size * 0.5
	btn.modulate.a = 0.0
	btn.pressed.connect(func():
		game.sfx.play("click")
		_fade())
	root_ctl.add_child(btn)
	var tw := btn.create_tween()
	tw.tween_property(btn, "modulate:a", 1.0, 0.25)
	if loading_label:
		loading_label.queue_free()
	# a gentle pulse so it's clear what to tap
	var pulse := btn.create_tween().set_loops()
	pulse.tween_property(btn, "scale", Vector2.ONE * 1.05, 0.55).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(btn, "scale", Vector2.ONE, 0.55).set_trans(Tween.TRANS_SINE)


func _fade() -> void:
	if done:
		return
	done = true
	game.loading_open = false
	root_ctl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := root_ctl.create_tween()
	tw.tween_property(root_ctl, "modulate:a", 0.0, 0.35)
	tw.tween_callback(queue_free)


## A bomb whose spin loop was still being made when the screen filled: start it spinning now.
var waiting := {}

func spin_ready(key: String) -> void:
	if not waiting.has(key) or not is_instance_valid(waiting[key]):
		return
	var ic: TextureRect = waiting[key]
	ic.stretch_mode = TextureRect.STRETCH_SCALE
	ic.texture = _strip(key)
	ic.material = _spin_material()


func _strip(key: String) -> ImageTexture:
	var frames: Array = game.model_icon_frames[key]
	var w: int = frames[0].get_width()
	var img := Image.create(w * frames.size(), w, false, Image.FORMAT_RGBA8)
	for i in frames.size():
		img.blit_rect(frames[i], Rect2i(0, 0, w, w), Vector2i(i * w, 0))
	return ImageTexture.create_from_image(img)


func _spin_material() -> ShaderMaterial:
	if _mat == null:
		var sh := Shader.new()
		sh.code = """
shader_type canvas_item;
uniform float frames = 24.0;
uniform float fps = 8.0;
varying vec4 tint;
void vertex() {
	tint = COLOR;
}
void fragment() {
	float f = floor(mod(TIME * fps, frames));
	COLOR = texture(TEXTURE, vec2((UV.x + f) / frames, UV.y)) * tint;
}
"""
		_mat = ShaderMaterial.new()
		_mat.shader = sh
		_mat.set_shader_parameter("frames", float(game.ICON_FRAMES))
		_mat.set_shader_parameter("fps", game.ICON_FPS)
	return _mat
