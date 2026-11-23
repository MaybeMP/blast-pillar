extends Control
## All on-screen UI: top bar, ore pickup messages, special-bomb hotbar, tabbed bottom panel, popups.
## Everything is drawn with chunky bevelled pixel frames and hand-made pixel icons (pixel_art.gd).

const Data = preload("res://scripts/data.gd")
const PA = preload("res://scripts/pixel_art.gd")

const C_TEXT := Color("f3e9d2")
const C_SUB := Color("b9a990")
const C_GOLD := Color("ffcf5a")
const C_BAD := Color("ff6b5a")
const C_GOOD := Color("9be36b")
const C_DARK := Color("2a1a08")

var game
var vp := Vector2(px(720), px(1280))
var top_inset := 0.0
var bottom_inset := 0.0
var font_body: Font
var font_bold: Font
var st := {}
var icon_cache := {}

var coins_label: Label
var rebirth_btn: Button
var world_label: Label
var depth_label: Label
var depth_bar: Control
var hint_label: Label
var perf_label: Label
var perf_timer := 0.0
var toast_box: VBoxContainer
var hud_panel: PanelContainer
var note_layer: Control
var notes: Array = []   # notifications on screen or waiting: {node, time, x, y}
var toasts := {}
var toast_timer := 0.0
var hotbar := {}
var hotbar_box: Control
var tab_buttons := {}
var tab_labels := {}
var flippers: Array = []   # 2D icons that 'spin' by squashing side to side
var current_tab := ""
var tab_scroll := {}      # tab -> how far down it was scrolled
var scroll: ScrollContainer
var content: VBoxContainer
var refreshers: Array[Callable] = []
var popup_layer: Control
var popup_box: VBoxContainer
var panel_top := 0.0
var _waiting := {}             # "ores/ruby" -> [[Control, property, scale], ...] until the loop is ready
var U := 1.0   # UI scale: the layout was designed 720 wide; the game is 585 wide (1170 px at 2x)


## Scale a layout size.
func px(v: float) -> float:
	return round(v * U)


## Scale a font size, snapped to multiples of 5 so the pixel font stays crisp at 2x.
func fs(v: float) -> int:
	return maxi(20, int(round(v * U / 5.0)) * 5)


# =============================================================================================
# Setup
# =============================================================================================

func build() -> void:
	vp = game.vp_size
	U = vp.x / 720.0
	top_inset = game.top_inset
	bottom_inset = game.bottom_inset
	position = Vector2.ZERO
	size = vp
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	font_body = _font("res://fonts/jersey10.woff")
	font_bold = font_body
	_make_styles()
	theme = _make_theme()
	_build_hud()
	_build_panel()
	_build_hotbar()
	_build_toasts()
	_build_hint()
	_build_perf()
	_build_notes()
	_build_popup_layer()
	switch_tab("upgrades")


func _font(path: String) -> Font:
	if ResourceLoader.exists(path):
		var f = load(path)
		if f is FontFile:
			f.hinting = TextServer.HINTING_NONE
			f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
			f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
			return f
	return ThemeDB.fallback_font


func _make_styles() -> void:
	var btn_pad := Vector4(px(14), px(8), px(14), px(11))
	var btn_pad_down := Vector4(px(14), px(11), px(14), px(8))  # pressed: content moves down 3px
	st["hud"] = PA.frame(Color("2b241f"), Color("43392f"), Color("17120f"), 3, false, Vector4(px(16), px(10), px(14), px(12)))
	st["panel"] = PA.frame(Color("3d342c"), Color("5a4d41"), Color("241e19"), 3, false, Vector4(px(14), px(12), px(14), px(14)))
	st["row"] = PA.frame(Color("2e2721"), Color("3f362e"), Color("1c1713"), 2, false, Vector4(px(12), px(10), px(12), px(10)))
	st["slot"] = PA.frame(Color("1f1a16"), Color("4a4038"), Color("100c0a"), 2, true, Vector4(px(6), px(6), px(6), px(6)))
	st["gold"] = PA.frame(Color("e8b33a"), Color("ffdf7f"), Color("a8741c"), 2, false, btn_pad)
	st["gold_p"] = PA.frame(Color("d09e2c"), Color("ffdf7f"), Color("8a5f15"), 2, true, btn_pad_down)
	st["green"] = PA.frame(Color("6cbf3f"), Color("a4e877"), Color("3f7f22"), 2, false, btn_pad)
	st["green_p"] = PA.frame(Color("5aa834"), Color("a4e877"), Color("336a1b"), 2, true, btn_pad_down)
	st["red"] = PA.frame(Color("d9472c"), Color("ff8a6a"), Color("8f2414"), 2, false, btn_pad)
	st["red_p"] = PA.frame(Color("bf3d24"), Color("ff8a6a"), Color("701c10"), 2, true, btn_pad_down)
	st["blue"] = PA.frame(Color("3a7bd5"), Color("7fb4ff"), Color("1f4c8f"), 2, false, btn_pad)
	st["blue_p"] = PA.frame(Color("3169bb"), Color("7fb4ff"), Color("193f78"), 2, true, btn_pad_down)
	st["gray"] = PA.frame(Color("4f4a44"), Color("625c55"), Color("37332f"), 2, false, btn_pad)
	st["tab_on"] = PA.frame(Color("5a4d41"), Color("7a6a5a"), Color("3d342c"), 2, false, Vector4(px(6), px(8), px(6), px(10)))
	st["tab_off"] = PA.frame(Color("2a231d"), Color("3a312a"), Color("1a1512"), 2, false, Vector4(px(6), px(8), px(6), px(10)))
	st["note_epic"] = PA.frame(Color(0.2, 0.08, 0.3, 0.97), Color(1.0, 0.82, 0.35, 1.0), Color(0.45, 0.2, 0.6, 1.0), 3, false, Vector4(px(14), px(10), px(16), px(11)))
	# soft pastel lavender, for small happy finds (Cosmic Eggs)
	st["note_soft"] = PA.frame(Color("8e7cc3"), Color("c9bcf0"), Color("5f4f93"), 3, false, Vector4(px(12), px(8), px(14), px(9)))
	st["note"] = PA.frame(Color(0.13, 0.1, 0.08, 0.95), Color(0.36, 0.3, 0.22, 0.95), Color(0.05, 0.04, 0.03, 0.95), 3, false, Vector4(px(12), px(8), px(14), px(9)))
	st["toast"] = PA.frame(Color(0.1, 0.08, 0.06, 0.88), Color(0.25, 0.21, 0.17, 0.88), Color(0.05, 0.04, 0.03, 0.88), 2, false, Vector4(px(8), px(4), px(12), px(5)))
	st["slot_btn"] = PA.frame(Color("2a231d"), Color("4a4038"), Color("100c0a"), 2, true, Vector4(px(4), px(4), px(4), px(4)))
	st["slot_ready"] = PA.frame(Color("3a2f20"), Color("ffd977"), Color("8a5f15"), 2, true, Vector4(px(4), px(4), px(4), px(4)))


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = font_body
	t.default_font_size = fs(30)
	t.set_color("font_color", "Label", C_TEXT)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.65))
	t.set_constant("shadow_offset_x", "Label", 2)
	t.set_constant("shadow_offset_y", "Label", 2)
	t.set_color("default_color", "RichTextLabel", C_SUB)
	t.set_color("font_shadow_color", "RichTextLabel", Color(0, 0, 0, 0.55))
	t.set_constant("shadow_offset_x", "RichTextLabel", 2)
	t.set_constant("shadow_offset_y", "RichTextLabel", 2)
	t.set_font_size("normal_font_size", "RichTextLabel", fs(25))
	t.set_font_size("bold_font_size", "RichTextLabel", fs(25))
	t.set_font("bold_font", "RichTextLabel", font_bold)
	t.set_stylebox("normal", "Button", st["gold"])
	t.set_stylebox("hover", "Button", st["gold"])
	t.set_stylebox("pressed", "Button", st["gold_p"])
	t.set_stylebox("hover_pressed", "Button", st["gold_p"])
	t.set_stylebox("disabled", "Button", st["gray"])
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(c, "Button", C_DARK)
	t.set_color("font_disabled_color", "Button", Color("a8a197"))
	t.set_font("font", "Button", font_bold)
	t.set_font_size("font_size", "Button", fs(30))
	t.set_constant("h_separation", "Button", int(px(8)))
	t.set_stylebox("panel", "PanelContainer", st["panel"])
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.08, 0.06, 0.05, 0.6)
	bar_bg.content_margin_left = 4
	bar_bg.content_margin_right = 4
	var grab := StyleBoxFlat.new()
	grab.bg_color = Color("8a7a66")
	grab.content_margin_left = 4
	grab.content_margin_right = 4
	t.set_stylebox("scroll", "VScrollBar", bar_bg)
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", grab)
	t.set_stylebox("grabber_pressed", "VScrollBar", grab)
	return t


func icon(name: String, scale := 3, tint := Color(-1, 0, 0)) -> Texture2D:
	var key := "%s_%d_%s" % [name, scale, tint.to_html()]
	if not icon_cache.has(key):
		var png := "res://icons/%s.png" % name
		if ResourceLoader.exists(png):
			# a ready-made picture (e.g. the 32x32 rebirth arrows), zoomed to about the same size
			var im: Image = (load(png) as Texture2D).get_image()
			var f := maxi(1, int(round(scale * 16.0 / im.get_width())))
			im.resize(im.get_width() * f, im.get_height() * f, Image.INTERPOLATE_NEAREST)
			icon_cache[key] = ImageTexture.create_from_image(im)
		else:
			icon_cache[key] = PA.icon(name, scale, tint)
	return icon_cache[key]


## Icon from a rendered model (your Blockbench files / world mini-pillars) if there is one,
## otherwise the hand-drawn pixel icon.
func micon(folder: String, id: String, fallback: String, scale := 3, tint := Color(-1, 0, 0)) -> Texture2D:
	var key := "%s/%s" % [folder, id]
	if game.model_icons.has(key):
		# whole-number zoom so pixels stay square; detailed (56px) icons usually show 1:1
		var w: int = game.model_icons[key].get_width()
		var f := maxi(1, int(round(scale * 16.0 * 1.15 / w)))
		var ck := "m_%s_%d" % [key, f]
		if not icon_cache.has(ck):
			var im: Image = game.model_icons[key].duplicate()
			im.resize(im.get_width() * f, im.get_height() * f, Image.INTERPOLATE_NEAREST)
			icon_cache[ck] = ImageTexture.create_from_image(im)
		return icon_cache[ck]
	return icon(fallback, scale, tint)


## One texture holding every frame of a model's spin loop side by side (null if none yet).
func spin_strip(folder: String, id: String, scale := 3) -> ImageTexture:
	var key := "%s/%s" % [folder, id]
	if not game.model_icon_frames.has(key):
		return null
	var frames: Array = game.model_icon_frames[key]
	var w: int = frames[0].get_width()
	var f := maxi(1, int(round(scale * 16.0 * 1.15 / w)))
	var ck := "strip_%s_%d" % [key, f]
	if not icon_cache.has(ck):
		var strip := Image.create(w * frames.size(), w, false, Image.FORMAT_RGBA8)
		for k in frames.size():
			strip.blit_rect(frames[k], Rect2i(0, 0, w, w), Vector2i(k * w, 0))
		if f > 1:
			strip.resize(strip.get_width() * f, strip.get_height() * f, Image.INTERPOLATE_NEAREST)
		icon_cache[ck] = ImageTexture.create_from_image(strip)
	return icon_cache[ck]


## The spin animation runs on the graphics chip: the shader picks the frame from the clock, so
## nothing on the CPU changes and the menus never have to re-layout.
var _spin_mat: ShaderMaterial

func spin_material() -> ShaderMaterial:
	if _spin_mat == null:
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
		_spin_mat = ShaderMaterial.new()
		_spin_mat.shader = sh
		_spin_mat.set_shader_parameter("frames", float(game.ICON_FRAMES))
		_spin_mat.set_shader_parameter("fps", game.ICON_FPS)
	return _spin_mat


## Put a model icon on a TextureRect; it spins if its loop is ready (or as soon as it is).
func set_model_icon(target: TextureRect, folder: String, id: String, fallback: String, scale := 3, tint := Color(-1, 0, 0)) -> void:
	var strip := spin_strip(folder, id, scale)
	if strip == null:
		target.material = null
		target.texture = micon(folder, id, fallback, scale, tint)
		var key := "%s/%s" % [folder, id]
		if game.model_icons.has(key):
			if not _waiting.has(key):
				_waiting[key] = []
			_waiting[key].append([target, scale])
		return
	var size := float(strip.get_height())
	if target.has_meta("fixed_size"):
		size = float(target.get_meta("fixed_size"))
	# size first, then the texture, so the wide strip never stretches the layout
	target.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	target.stretch_mode = TextureRect.STRETCH_SCALE
	target.custom_minimum_size = Vector2(size, size)
	target.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	target.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	target.material = spin_material()
	target.texture = strip
	target.size = Vector2(size, size)


## A small spinning icon of a set size: the model's spin loop if it has one, otherwise the
## picture turning side to side like a flipping coin.
func _spin_icon(folder: String, id: String, fallback: Texture2D, size: float) -> TextureRect:
	var ic := TextureRect.new()
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.custom_minimum_size = Vector2(size, size)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ic.set_meta("fixed_size", size)
	if folder != "" and game.model_icons.has("%s/%s" % [folder, id]):
		set_model_icon(ic, folder, id, "gem", 3)
	else:
		ic.texture = fallback
		flippers.append(ic)
	return ic


## Called by the game when a spinning icon loop has finished rendering.
func spin_ready(key: String) -> void:
	if not _waiting.has(key):
		return
	var parts := key.split("/")
	for w in _waiting[key]:
		var target = w[0]
		if is_instance_valid(target):
			set_model_icon(target, parts[0], parts[1], "gem", w[1])
	_waiting.erase(key)


func ore_icon(oid: String, scale := 2, tint := Color(-1, 0, 0)) -> Texture2D:
	var t: Color = tint if tint.r >= 0.0 else game.ore_table[oid]["color"]
	return micon("ores", oid, "gem", scale, t)


func world_icon(w: int, scale := 3) -> Texture2D:
	return micon("world", str(w), "world", scale, Color.html(Data.WORLDS[w]["sky_top"]).lightened(0.15))


func _label(text: String, size: int, color := C_TEXT, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if bold:
		l.add_theme_font_override("font", font_bold)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _style_button(b: Button, style: String) -> void:
	if b.get_meta("style", "") == style:
		return   # already styled this way; re-applying would force a full menu re-layout
	b.set_meta("style", style)
	b.add_theme_stylebox_override("normal", st[style])
	b.add_theme_stylebox_override("hover", st[style])
	b.add_theme_stylebox_override("pressed", st[style + "_p"])
	b.add_theme_stylebox_override("hover_pressed", st[style + "_p"])


# =============================================================================================
# HUD
# =============================================================================================

func _build_hud() -> void:
	var hud := PanelContainer.new()
	hud_panel = hud
	hud.add_theme_stylebox_override("panel", st["hud"])
	hud.position = Vector2(px(10), top_inset + px(8))
	hud.size = Vector2(vp.x - px(20), 0)
	add_child(hud)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(px(10)))
	hud.add_child(row)

	var coin := TextureRect.new()
	coin.texture = icon("coin", 3)
	coin.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(coin)

	coins_label = _label("0", fs(50), C_GOLD, true)
	coins_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	coins_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	coins_label.clip_text = true
	row.add_child(coins_label)

	# rebirth button: shows once you can rebirth (or have before); sits just left of the world progress
	rebirth_btn = Button.new()
	rebirth_btn.icon = icon("rebirth", 4)
	rebirth_btn.custom_minimum_size = Vector2(px(60), px(60))
	rebirth_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rebirth_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rebirth_btn.add_theme_stylebox_override("normal", st["slot_btn"])
	rebirth_btn.add_theme_stylebox_override("hover", st["slot_btn"])
	rebirth_btn.add_theme_stylebox_override("pressed", st["slot"])
	rebirth_btn.pressed.connect(func():
		game.sfx.play("click")
		game.show_rebirth_popup())
	rebirth_btn.visible = false
	row.add_child(rebirth_btn)

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(px(240), 0)
	right.add_theme_constant_override("separation", int(px(4)))
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(right)
	world_label = _label("", fs(25), C_TEXT, true)
	world_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(world_label)
	depth_bar = Control.new()
	depth_bar.custom_minimum_size = Vector2(px(240), px(18))
	depth_bar.draw.connect(_draw_depth_bar)
	right.add_child(depth_bar)
	depth_label = _label("", fs(20), C_SUB)
	depth_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(depth_label)

	var gear := Button.new()
	gear.icon = icon("gear", 2)
	gear.custom_minimum_size = Vector2(px(60), px(60))
	gear.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gear.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gear.add_theme_stylebox_override("normal", st["slot_btn"])
	gear.add_theme_stylebox_override("hover", st["slot_btn"])
	gear.add_theme_stylebox_override("pressed", st["slot"])
	gear.pressed.connect(show_settings)
	row.add_child(gear)


func _draw_depth_bar() -> void:
	var r := Rect2(Vector2.ZERO, depth_bar.size)
	depth_bar.draw_rect(r, Color("120e0b"))
	depth_bar.draw_rect(r.grow(-3), Color("2a231d"))
	var segs := 20
	var p: float = game.pillar.progress() if game.pillar else 0.0
	var filled := int(round(p * segs))
	var w := (r.size.x - 6) / segs
	for i in segs:
		if i < filled:
			var c := Color("ffcf5a") if i < segs - 1 else Color("b46bff")
			depth_bar.draw_rect(Rect2(3 + i * w + 1, 4, w - 2, r.size.y - 8), c)


# =============================================================================================
# Bottom panel with tabs
# =============================================================================================

func _build_panel() -> void:
	var ph := clampf(round(vp.y * 0.37), px(430), px(640))
	panel_top = vp.y - bottom_inset - ph - px(6)
	var panel := PanelContainer.new()
	panel.position = Vector2(px(8), panel_top)
	panel.size = Vector2(vp.x - px(16), ph)
	add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(px(10)))
	panel.add_child(v)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", int(px(6)))
	v.add_child(tabs)
	# each tab: a little spinning icon, then its name
	var tab_icons := {
		"upgrades": ["ui", "coin", icon("coin", 2)],
		"bombs": ["bombs", "bomb", icon("bomb", 2)],
		"ores": ["ores", "diamond", ore_icon("diamond", 2)],
		"worlds": ["world", "0", world_icon(0, 2)],
		"relics": ["relics", "golden_bomb", icon("gem", 2, Color("ffc533"))],
	}
	for t in [["upgrades", "UPGRADES"], ["bombs", "BOMBS"], ["ores", "ORES"], ["worlds", "WORLDS"], ["relics", "RELICS"]]:
		var b := Button.new()
		b.text = ""
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(px(0), px(58))
		b.pressed.connect(func():
			game.sfx.play("click")
			switch_tab(t[0]))
		tabs.add_child(b)
		tab_buttons[t[0]] = b
		var hb := HBoxContainer.new()
		hb.set_anchors_preset(Control.PRESET_FULL_RECT)
		hb.alignment = BoxContainer.ALIGNMENT_CENTER
		hb.add_theme_constant_override("separation", int(px(4)))
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(hb)
		var info: Array = tab_icons[t[0]]
		hb.add_child(_spin_icon(info[0], info[1], info[2], 56.0 if px(58) >= 64.0 else 28.0))
		var l := _label(t[1], fs(25), C_TEXT, true)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hb.add_child(l)
		tab_labels[t[0]] = l
	update_tabs()

	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", int(px(8)))
	content.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.add_child(content)


## The RELICS tab only shows once you own a relic. With five tabs the labels get a bit smaller.
func update_tabs() -> void:
	if not tab_buttons.has("relics"):
		return
	var show_relics: bool = not game.relics.is_empty()
	tab_buttons["relics"].visible = show_relics
	for k in tab_labels:
		tab_labels[k].add_theme_font_size_override("font_size", fs(20) if show_relics else fs(25))
	if not show_relics and current_tab == "relics":
		switch_tab("upgrades")


func switch_tab(id: String) -> void:
	if id == "relics" and game.relics.is_empty():
		id = "upgrades"
	if current_tab != "":
		tab_scroll[current_tab] = scroll.scroll_vertical   # each tab remembers where you scrolled to
	current_tab = id
	for k in tab_buttons:
		var b: Button = tab_buttons[k]
		var s: StyleBox = st["tab_on"] if k == id else st["tab_off"]
		for state in ["normal", "hover", "pressed", "hover_pressed"]:
			b.add_theme_stylebox_override(state, s)
		if tab_labels.has(k):
			tab_labels[k].add_theme_color_override("font_color", C_GOLD if k == id else C_SUB)
	for c in content.get_children():
		content.remove_child(c)
		c.queue_free()
	refreshers.clear()
	match id:
		"upgrades": _tab_upgrades()
		"bombs": _tab_bombs()
		"ores": _tab_ores()
		"worlds": _tab_worlds()
		"relics": _tab_relics()
	refresh()
	_restore_scroll(id, int(tab_scroll.get(id, 0)))


## The new rows need a frame to be laid out before the list can scroll that far.
func _restore_scroll(id: String, to: int) -> void:
	scroll.scroll_vertical = to
	for i in 2:
		await get_tree().process_frame
		if current_tab != id:
			return
		scroll.scroll_vertical = to


func rebuild_tab() -> void:
	switch_tab(current_tab)


## A half-width card for the 2-per-row grids (BOMBS and WORLDS): icon and name on top, the
## description under it, buttons along the bottom. Returns the same pieces as _row().
func _card(icon_tex: Texture2D, title: String, parent: Control) -> Dictionary:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", st["row"])
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(px(6)))
	v.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", int(px(8)))
	top.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(top)
	var slot := PanelContainer.new()
	slot.add_theme_stylebox_override("panel", st["slot"])
	slot.custom_minimum_size = Vector2(px(60), px(60))
	slot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	slot.mouse_filter = Control.MOUSE_FILTER_PASS
	var ic := TextureRect.new()
	ic.texture = icon_tex
	ic.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(ic)
	var done := ColorRect.new()   # a soft green wash over the icon = this one's complete
	done.color = Color(0.35, 0.95, 0.35, 0.32)
	done.mouse_filter = Control.MOUSE_FILTER_IGNORE
	done.visible = false
	slot.add_child(done)
	top.add_child(slot)
	# name, and its details right under it, beside the icon
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override("separation", int(px(2)))
	side.mouse_filter = Control.MOUSE_FILTER_PASS
	top.add_child(side)
	var tl := _label(title, fs(32), C_TEXT, true)
	tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tl.custom_minimum_size = Vector2(px(40), 0)
	side.add_child(tl)
	var info := RichTextLabel.new()
	info.bbcode_enabled = true
	info.fit_content = true
	info.scroll_active = false
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_font_size_override("normal_font_size", fs(31))
	info.mouse_filter = Control.MOUSE_FILTER_PASS
	side.add_child(info)
	var fill := Control.new()   # pushes the buttons to the bottom of the card
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(fill)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", int(px(6)))
	hb.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(hb)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(px(60), px(60))
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.mouse_filter = Control.MOUSE_FILTER_PASS
	hb.add_child(btn)
	parent.add_child(row)
	return {"row": row, "title": tl, "info": info, "button": btn, "icon": ic, "done": done}


## Two cards side by side, row after row.
func _grid2() -> GridContainer:
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", int(px(8)))
	g.add_theme_constant_override("v_separation", int(px(8)))
	g.mouse_filter = Control.MOUSE_FILTER_PASS
	content.add_child(g)
	return g


func _row(icon_tex: Texture2D, title: String) -> Dictionary:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", st["row"])
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", int(px(12)))
	h.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(h)

	var slot := PanelContainer.new()
	slot.add_theme_stylebox_override("panel", st["slot"])
	slot.custom_minimum_size = Vector2(px(68), px(68))
	slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slot.mouse_filter = Control.MOUSE_FILTER_PASS
	var ic := TextureRect.new()
	ic.texture = icon_tex
	ic.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(ic)
	h.add_child(slot)

	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", int(px(2)))
	v.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(v)
	var tl := _label(title, fs(30), C_TEXT, true)
	v.add_child(tl)
	var info := RichTextLabel.new()
	info.bbcode_enabled = true
	info.fit_content = true
	info.scroll_active = false
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(info)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(px(190), px(72))
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(btn)
	content.add_child(row)
	return {"row": row, "title": tl, "info": info, "button": btn, "icon": ic}


## "Needs 12/25 Copper" style list for ore costs. Red when you don't have enough.
func cost_text(cost: Dictionary) -> String:
	var parts: Array[String] = []
	for k in cost:
		if k == "coins":
			continue
		var have := int(game.ores.get(k, 0))
		var need := int(cost[k])
		var col := C_GOOD if have >= need else C_BAD
		var nm: String = game.ore_table[k]["name"] if game.ores_seen.has(k) else "???"
		parts.append("[color=#%s]%s/%d[/color] %s" % [col.to_html(false), game.fmt(have), need, nm])
	return ", ".join(parts)


func _set_cost_button(b: Button, cost: Dictionary, label_if_free: String) -> void:
	var c := float(cost.get("coins", 0.0))
	if c > 0.0:
		b.text = game.fmt(c)
		b.icon = icon("coin", 2)
	else:
		b.text = label_if_free
		b.icon = null
	b.disabled = not game.can_afford(cost)


# ---------------------------------------------------------------------------------------------

func _tab_upgrades() -> void:
	for u in Data.UPGRADES:
		var r := _row(icon(u["icon"]), u["name"])
		var uid: String = u["id"]
		r["button"].pressed.connect(func(): game.buy_upgrade(uid))
		refreshers.append(func():
			var lvl: int = game.lvl(uid)
			r["info"].text = "LV %d  [color=#ffcf5a]%s[/color]" % [lvl, game.upgrade_effect(uid)]
			if game.upgrade_maxed(u):
				r["button"].text = "MAX"
				r["button"].icon = null
				r["button"].disabled = true
			else:
				var c: float = game.upgrade_cost(u)
				r["button"].text = game.fmt(c)
				r["button"].icon = icon("coin", 2)
				r["button"].disabled = game.coins < c)



## Relics tab: the ones you own, plus a "???" for each one still out there.
func _tab_relics() -> void:
	for rl in Data.RELICS:
		var rid: String = rl["id"]
		var col := Color(rl["col"])
		var r := _row(micon("relics", rid, "gem", 3, col), rl["name"])
		set_model_icon(r["icon"], "relics", rid, "gem", 3, col)
		r["button"].visible = false
		var fw: int = int(rl["find"])
		refreshers.append(func():
			if game.has_relic(rid):
				r["title"].text = rl["name"]
				r["icon"].modulate = Color.WHITE
				r["info"].text = "[color=#9be36b]%s[/color]" % rl["desc"]
			else:
				r["title"].text = "???"
				r["icon"].modulate = Color(0, 0, 0, 0.75)
				r["info"].text = ("Hidden in the vault under the bedrock of %s." % Data.WORLDS[fw]["name"]) if fw < game.unlocked_worlds else "Hidden somewhere deeper...")


func _tab_bombs() -> void:
	content.add_child(_label("BEDROCK BOMB", fs(25), C_GOLD, true))
	_bedrock_row()
	var tip := _label("Tap a bomb to see what it does.", fs(18), C_SUB)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(tip)
	# the rest in categories, as tiles like the ORES tab
	var cats := [
		["SHOP BOMBS", func(sp): return not sp.has("find") and not sp.has("rebirth")],
		["VAULT BOMBS (FOUND UNDER BEDROCK)", func(sp): return sp.has("find")],
		["REBIRTH BOMBS (PERMANENT)", func(sp): return sp.has("rebirth")],
	]
	for cat in cats:
		var list: Array = []
		for sp in Data.SPECIALS:
			if not cat[1].call(sp):
				continue
			if sp.has("rebirth") and game.rebirths < 1 and not game.specials.has(sp["id"]):
				continue   # the rebirth bombs show up after your first rebirth
			list.append(sp)
		if list.is_empty():
			continue
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, px(6))
		gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(gap)
		content.add_child(_label(cat[0], fs(22), C_GOLD, true))
		var grid := GridContainer.new()
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", int(px(6)))
		grid.add_theme_constant_override("v_separation", int(px(8)))
		grid.mouse_filter = Control.MOUSE_FILTER_PASS
		content.add_child(grid)
		for sp in list:
			grid.add_child(_bomb_tile(sp))


## Is this special bomb still a mystery (a vault bomb not found yet, or a rebirth bomb not earned)?
func _bomb_secret(s: Dictionary) -> bool:
	return (s.has("find") or s.has("rebirth")) and not game.specials.has(s["id"])


## One bomb tile in the BOMBS tab: its spinning icon and its reload time. Tap it for the details.
func _bomb_tile(s: Dictionary) -> Control:
	var sid: String = s["id"]
	var tile := Button.new()
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.custom_minimum_size = Vector2(0, px(128))
	tile.clip_contents = true
	tile.mouse_filter = Control.MOUSE_FILTER_PASS
	tile.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		tile.add_theme_stylebox_override(state, st["slot"])
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = px(4)
	v.offset_right = -px(4)
	v.offset_bottom = -px(4)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", int(px(2)))
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(v)
	var ic := TextureRect.new()
	ic.texture = micon("bombs", sid, sid, 3)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.custom_minimum_size = Vector2(px(54), px(54))
	ic.set_meta("fixed_size", px(54))
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_model_icon(ic, "bombs", sid, sid, 3)
	v.add_child(ic)
	# bottom: "45 sec" on the left (number in yellow, "sec" in white), green upgrade button on the right
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(px(3)))
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(row)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(px(4), 0)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(pad)
	var num := _label("0", fs(19), C_GOLD, true)
	num.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(num)
	var unit := _label("sec", fs(19), C_TEXT, true)
	unit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	unit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(unit)
	# the upgrade button runs along the bottom of the tile: arrow + price
	var up := Button.new()
	up.icon = icon("up", 1)
	up.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	up.alignment = HORIZONTAL_ALIGNMENT_CENTER
	up.add_theme_font_size_override("font_size", fs(19))
	up.add_theme_constant_override("icon_max_width", int(px(22)))
	up.add_theme_constant_override("h_separation", int(px(3)))
	up.custom_minimum_size = Vector2(0, px(36))
	up.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	up.mouse_filter = Control.MOUSE_FILTER_STOP   # its own tap, not the tile's
	up.focus_mode = Control.FOCUS_NONE
	_style_button(up, "green")
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var sb: StyleBox = up.get_theme_stylebox(state)
		if sb:
			sb = sb.duplicate()
			sb.content_margin_left = px(5)
			sb.content_margin_right = px(5)
			sb.content_margin_top = px(4)
			sb.content_margin_bottom = px(6)
			up.add_theme_stylebox_override(state, sb)   # thin padding so the arrow can be big
	var up_row := HBoxContainer.new()
	up_row.mouse_filter = Control.MOUSE_FILTER_PASS
	up_row.add_child(up)
	v.add_child(up_row)
	up.pressed.connect(func():
		if game.coins >= game.special_upgrade_cost(sid):
			game.upgrade_special(sid)
		else:
			game.sfx.play("click")
			_bomb_popup(sid))   # can't afford it yet: show what it costs
	refreshers.append(func():
		var secret := _bomb_secret(s)
		var owned: bool = game.specials.has(sid)
		ic.modulate = Color(0, 0, 0, 0.75) if secret else (Color.WHITE if owned else Color(0.55, 0.55, 0.55))
		up.visible = owned and sid != "mirror" and game.special_level(sid) < Data.SPECIAL_MAX_LEVEL
		if up.visible:
			var c: float = game.special_upgrade_cost(sid)
			up.text = game.fmt(c)
			up.modulate = Color.WHITE if game.coins >= c else Color(1, 1, 1, 0.5)
		if secret:
			num.text = "?"
			unit.visible = false
			return
		unit.visible = true
		var cd: float = game.special_cooldown(sid)
		if sid == "mirror" and game.mirror_copy != "":
			cd = game.special_cooldown(game.mirror_copy)
		num.text = str(int(round(cd))))
	tile.pressed.connect(func():
		game.sfx.play("click")
		_bomb_popup(sid))
	return tile


## Tap a bomb: what it does, its reload, and the buttons to buy it or speed up its reload.
func _bomb_popup(sid: String) -> void:
	var s := Data.get_special(sid)
	var tex := micon("bombs", sid, sid, 4)
	var spin := ["bombs", sid]
	var close := ["CLOSE", Callable(), "gold"]
	if s.has("rebirth") and not game.specials.has(sid):
		show_popup("???", "Unlocks for good at [color=#ffcf5a]%d rebirths[/color] (you have %d)." % [int(s["rebirth"]), game.rebirths],
			[close], tex)
		return
	if s.has("find") and not game.specials.has(sid):
		var fw: int = int(s["find"])
		var where := ("Hidden in the vault under the bedrock of [color=#ffcf5a]%s[/color]." % Data.WORLDS[fw]["name"]) if fw < game.unlocked_worlds else "Hidden somewhere deeper..."
		show_popup("???", where, [close], tex)
		return
	var lvl: int = game.special_level(sid)
	var body: String = s["desc"] + "."
	var buttons: Array = []
	if not game.specials.has(sid):
		# a shop bomb you haven't bought yet
		body += "\nReload: [color=#ffcf5a]%d sec[/color]" % int(round(game.special_cooldown(sid)))
		body += "\nNeeds " + cost_text(s["cost"])
		if game.can_afford(s["cost"]):
			buttons.append(["UNLOCK", func():
				game.unlock_special(sid)
				_bomb_popup(sid), "green"])
	elif sid == "mirror":
		var copy: String = game.mirror_copy
		body += "\nReloads as long as the bomb it copies"
		if copy != "":
			body += " ([color=#ffcf5a]%d sec[/color])" % int(round(game.special_cooldown(copy)))
		body += ".\nNext copy: " + ("[color=#b46bff]%s[/color]" % game.special_name(copy) if copy != "" else "[color=#b9a990]fire another special bomb first[/color]")
	else:
		body += "\nReload: [color=#ffcf5a]%d sec[/color]" % int(round(game.special_cooldown(sid)))
		if lvl < Data.SPECIAL_MAX_LEVEL:
			var nxt: float = game.special_cooldown_at(sid, lvl + 1)
			var c: float = game.special_upgrade_cost(sid)
			body += "\nUpgrade to [color=#9be36b]%d sec[/color] for [color=#ffcf5a]%s coins[/color]." % [int(round(nxt)), game.fmt(c)]
			if game.coins >= c:
				buttons.append(["FASTER RELOAD", func():
					game.upgrade_special(sid)
					_bomb_popup(sid), "green"])
		else:
			body += "\n[color=#9be36b]Reload fully upgraded.[/color]"
		body += "\nFire it from the hotbar."
	buttons.append(close)
	show_popup(String(s["name"]).to_upper(), body, buttons, tex, spin)


## Rebirth popup: the five rebirth bombs spinning in a row, black until you've unlocked them,
## each with the number of rebirths it needs underneath.
func rebirth_bomb_strip() -> Control:
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", int(px(14)))
	for sp in Data.SPECIALS:
		if not sp.has("rebirth"):
			continue
		var sid: String = sp["id"]
		var owned: bool = game.specials.has(sid)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", int(px(2)))
		var ic := TextureRect.new()
		ic.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(ic)
		# a locked bomb with no model yet spins as a plain bomb silhouette
		var shown := sid if owned or game.has_model("bombs", sid) else "bomb"
		set_model_icon(ic, "bombs", shown, sid, 3)
		ic.modulate = Color.WHITE if owned else Color(0, 0, 0, 0.8)
		var n := _label(str(int(sp["rebirth"])), fs(26), Color("9be36b") if owned else C_SUB, true)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(n)
		hb.add_child(col)
	return hb


func _bedrock_row() -> void:
	var r := _row(micon("bombs", "bedrock", "bedrock"), "Bedrock Bomb")
	set_model_icon(r["icon"], "bombs", "bedrock", "bedrock", 3)
	r["button"].text = "USE"
	_style_button(r["button"], "red")
	r["button"].pressed.connect(func(): game.use_bedrock_bomb())
	refreshers.append(func():
		var w: int = game.current_world
		var tid: String = Data.BEDROCK_BOMB_ORE
		var have := int(game.ores.get(tid, 0))
		var tname: String = "Cosmic Eggs"
		var cost := Data.bedrock_cost(w)
		var state: String = game.bedrock_bomb_state()
		var line := "One use: shatters the whole bedrock layer of %s." % Data.WORLDS[w]["name"]
		match state:
			"not_reached":
				line += "\n[color=#b9a990]Dig down to the bedrock first.[/color]  Costs %d/%d %s (buried in every world)" % [have, cost, tname]
			"broken":
				line = "The bedrock of %s is already broken. Dig the vault!" % Data.WORLDS[w]["name"]
			"done_before":
				line = "You already broke the bedrock of %s and emptied its vault." % Data.WORLDS[w]["name"]
				var nxt: int = game.next_bedrock_world()
				if nxt >= 0:
					line += "\nYour next Bedrock Bomb goes to [color=#ffcf5a]%s[/color]." % Data.WORLDS[nxt]["name"]
			"falling":
				line += "\n[color=#9be36b]On its way down...[/color]"
			"out_of_order":
				var nb: int = game.next_bedrock_world()
				line += "\n[color=#ff6b5a]Bedrock Bombs go in order, World 1 to 12. Break the bedrock of %s first.[/color]" % Data.WORLDS[nb]["name"]
			_:
				var col := "9be36b" if have >= cost else "ff6b5a"
				line += "\nCosts [color=#%s]%d/%d[/color] %s (buried in every world)" % [col, have, cost, tname]
		r["info"].text = line
		r["button"].disabled = state != "ready")


func _tab_ores() -> void:
	# the big promise: ores survive a rebirth (they'll unlock bombs once you've piled up enough)
	var keep := _label("Your ores are KEPT when you rebirth!", fs(22), Color("9be36b"), true)
	keep.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	keep.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(keep)
	var tip := _label("Tap an ore to buy more.", fs(18), C_SUB)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(tip)
	# every world you've reached this run, or whose ores you've found before (they're still yours)
	var shown: Array = []
	for w in Data.WORLDS.size():
		var world: Dictionary = Data.WORLDS[w]
		var known: bool = w < game.unlocked_worlds
		if not known:
			for o in world["ores"]:
				if game.ores_seen.has(o["id"]):
					known = true
					break
		if known:
			shown.append(w)
	# two worlds side by side; each world is a 3x2 block of ore tiles
	for k in range(0, shown.size(), 2):
		if k > 0:
			var gap := Control.new()   # a little breathing room between each pair of worlds
			gap.custom_minimum_size = Vector2(0, px(14))
			gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
			content.add_child(gap)
		var pair := HBoxContainer.new()
		pair.add_theme_constant_override("separation", int(px(12)))
		pair.mouse_filter = Control.MOUSE_FILTER_PASS
		content.add_child(pair)
		for j in 2:
			var col := VBoxContainer.new()
			col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			col.size_flags_stretch_ratio = 1.0
			col.add_theme_constant_override("separation", int(px(4)))
			col.mouse_filter = Control.MOUSE_FILTER_PASS
			pair.add_child(col)
			if k + j >= shown.size():
				continue
			var world: Dictionary = Data.WORLDS[shown[k + j]]
			var head := _label(world["name"].to_upper(), fs(20), C_GOLD, true)
			head.clip_text = true
			head.custom_minimum_size = Vector2(px(40), 0)
			col.add_child(head)
			var grid := GridContainer.new()
			grid.columns = 3
			grid.add_theme_constant_override("h_separation", int(px(4)))
			grid.add_theme_constant_override("v_separation", int(px(8)))
			grid.mouse_filter = Control.MOUSE_FILTER_PASS
			col.add_child(grid)
			var ids: Array = []
			for o in world["ores"]:
				ids.append(o["id"])
			ids.append(world["treasure"]["id"])
			for oid in ids:
				grid.add_child(_ore_tile(oid))


## One ore tile in the ORES tab: its spinning icon and how many you have. Tap it to buy more.
func _ore_tile(oid: String) -> Control:
	var tile := Button.new()
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.custom_minimum_size = Vector2(0, px(92))
	tile.clip_contents = true   # a big spinning ore never spills over the tile below
	tile.mouse_filter = Control.MOUSE_FILTER_PASS
	tile.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		tile.add_theme_stylebox_override(state, st["slot"])
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(v)
	var seen: bool = game.ores_seen.has(oid)
	var ic := TextureRect.new()
	ic.texture = ore_icon(oid, 2)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.custom_minimum_size = Vector2(px(50), px(50))
	ic.set_meta("fixed_size", px(50))   # spinning icons keep to this size too
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if seen:
		set_model_icon(ic, "ores", oid, "gem", 2, game.ore_table[oid]["color"])
	else:
		ic.modulate = Color(0, 0, 0, 0.75)   # silhouette until you find it
	v.add_child(ic)
	var cnt := _label("0", fs(18), C_TEXT, true)
	cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cnt.clip_text = true
	cnt.custom_minimum_size = Vector2(px(20), 0)
	v.add_child(cnt)
	refreshers.append(func(): cnt.text = game.fmt(float(game.ores.get(oid, 0))) if seen else "?")
	if seen:
		tile.pressed.connect(func():
			game.sfx.play("click")
			_ore_popup(oid))
	return tile


## Tap an ore: what it is, how many you have, and buttons to buy more.
func _ore_popup(oid: String) -> void:
	var o: Dictionary = game.ore_table[oid]
	var have := int(game.ores.get(oid, 0))
	var wname: String = Data.WORLDS[int(o["world"])]["name"]
	var tex := micon("ores", oid, "gem", 4, o["color"])
	var spin := ["ores", oid, "gem", o["color"]]
	if not game.ore_tradable(oid):
		show_popup(String(o["name"]).to_upper(),
			"You have [color=#ffcf5a]%s[/color].\nCosmic Eggs can't be bought. Dig them up - every world hides a few." % game.fmt(float(have)),
			[["OK", Callable(), "green"]], tex, spin)
		return
	var price: float = game.ore_value(oid)
	var can: int = game.ores_affordable(oid)
	var body := "From %s.\nYou have [color=#ffcf5a]%s[/color].\nPrice: [color=#ffcf5a]%s coins[/color] each" % [wname, game.fmt(float(have)), game.fmt(price)]
	body += "\n[color=#%s]You can afford %s.[/color]" % ["9be36b" if can > 0 else "ff6b5a", game.fmt(float(can))]
	var buy := func(n: int):
		game.buy_ore(oid, n)
		_ore_popup(oid)   # reopen with the new numbers
	show_popup(String(o["name"]).to_upper(), body, [
		["BUY 1", func(): buy.call(1), "green"],
		["BUY 10", func(): buy.call(10), "green"],
		["BUY MAX", func(): buy.call(can), "green"],
		["CLOSE", Callable(), "gold"],
	], tex, spin)


const EARLY_WORLDS := 6   # Worlds 1-6 can be folded away in the WORLDS tab

func _tab_worlds() -> void:
	var fold := Button.new()
	fold.text = ("SHOW WORLDS 1-%d" if game.hide_early_worlds else "HIDE WORLDS 1-%d") % EARLY_WORLDS
	fold.custom_minimum_size = Vector2(0, px(60))
	fold.add_theme_font_size_override("font_size", fs(25))
	fold.mouse_filter = Control.MOUSE_FILTER_PASS
	_style_button(fold, "green" if game.hide_early_worlds else "gold")
	fold.pressed.connect(func():
		game.sfx.play("click")
		game.hide_early_worlds = not game.hide_early_worlds
		game.save_game()
		rebuild_tab())
	# folding Worlds 1-6 only makes sense once there's something past them to look at
	var can_fold: bool = game.unlocked_worlds >= EARLY_WORLDS
	if can_fold:
		content.add_child(fold)
	else:
		fold.queue_free()
	var grid := _grid2()
	for w in Data.WORLDS.size():
		if w < EARLY_WORLDS and game.hide_early_worlds and can_fold:
			continue
		if w > game.unlocked_worlds:
			break   # only the next world to unlock is shown; the rest stay a surprise
		var world: Dictionary = Data.WORLDS[w]
		var r := _card(world_icon(w, 3), world["name"], grid)
		set_model_icon(r["icon"], "world", str(w), "world", 3)
		var idx := w
		r["button"].pressed.connect(func(): game.travel(idx))
		# RESET: white refresh arrows on red.  TRAVEL: white arrow on green.
		var reset := Button.new()
		reset.icon = icon("reset", 2)
		reset.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		reset.custom_minimum_size = Vector2(px(60), px(60))
		reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		reset.mouse_filter = Control.MOUSE_FILTER_PASS
		_style_button(reset, "red")
		var hb: Node = r["button"].get_parent()
		hb.add_child(reset)
		hb.move_child(reset, r["button"].get_index())
		r["button"].icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		reset.pressed.connect(func():
			game.sfx.play("click")
			var eggs: int = game.egg_allotment(idx) + game.eggs_left_in(idx) + int(game.worlds[idx].get("egg_carry", 0))
			var egg_line := "\nCosmic Eggs in the new pillar: [color=#%s]%d[/color]" % ["fff1c9" if eggs > 0 else "ff6b5a", eggs]
			if eggs == 0:
				egg_line += " (this world's eggs are all used up)"
			show_popup("RESET %s?" % Data.WORLDS[idx]["name"].to_upper(),
				"This grows a brand new pillar so you can blast it again.\nYour coins, ores and upgrades stay." + egg_line,
				[["CANCEL", Callable(), "gold"], ["RESET", func(): game.reset_world(idx), "red"]], world_icon(idx, 5)))
		refreshers.append(func():
			var unlocked: bool = idx < game.unlocked_worlds
			var data: Dictionary = game.worlds[idx]
			reset.visible = unlocked and bool(data.get("done", false))
			# after a rebirth you've already been everywhere, so locked worlds stay in colour
			# (just dimmed) with their names showing, instead of going back to black "???"
			var known: bool = game.rebirths > 0
			r["icon"].modulate = Color.WHITE if unlocked else (Color(0.5, 0.5, 0.5) if known else Color(0, 0, 0, 0.75))
			if not unlocked:
				r["title"].text = Data.WORLDS[idx]["name"] if known else "???"
				if idx >= Data.ORIGINAL_WORLDS:
					var got: int = game.vault_bombs_found()
					var tot: int = game.vault_bombs_total()
					var col := "9be36b" if got >= tot else "ff6b5a"
					r["info"].text = "A Deep Realm. Reach the bottom of %s and find all %d vault bombs hidden under the bedrock of Worlds 1-6 ([color=#%s]%d/%d[/color])." % [Data.WORLDS[idx - 1]["name"], tot, col, got, tot]
				else:
					r["info"].text = "Break through the bottom of %s to open the portal." % Data.WORLDS[idx - 1]["name"]
				r["button"].text = ""
				r["button"].icon = icon("lock", 2)
				r["button"].disabled = true
				r["done"].visible = false
				return
			var txt := ""
			if data.get("bedrock_broken", false) and not game.world_prize_found(idx):
				txt = "[color=#ffcf5a]VAULT OPEN[/color]"
			for sp in Data.SPECIALS:
				if int(sp.get("find", -1)) == idx and game.specials.has(sp["id"]):
					txt = "[color=#b46bff]BOMB FOUND[/color]"
			for rl in Data.RELICS:
				if int(rl["find"]) == idx and game.has_relic(rl["id"]):
					txt = "[color=#b46bff]RELIC FOUND[/color]"
			if idx == Data.STAR_CORE_WORLD and game.world_prize_found(idx):
				txt = "[color=#b46bff]CORE FOUND[/color]"
			# the world's vault prize (bomb, relic or Star Core) is found: a green wash over its icon
			r["done"].visible = game.world_prize_found(idx)
			r["info"].text = txt
			if idx == game.current_world:
				r["button"].icon = null
				r["button"].text = "HERE"
				r["button"].disabled = true
			else:
				r["button"].icon = icon("go", 2)
				r["button"].text = ""
				_style_button(r["button"], "green")
				r["button"].disabled = false)


# =============================================================================================
# Hotbar, toasts, hint
# =============================================================================================

func _build_hotbar() -> void:
	rebuild_hotbar()


## The hotbar: the 4 shop bombs (locked ones show a padlock) plus any hidden bombs you've found.
## Up to 5 per row; a second row appears once you have more than 5.
## Rebirth bombs get their own column on the left, stacking upwards from just above the tabs.
var rebirth_box: Control

func rebuild_hotbar() -> void:
	if hotbar_box and is_instance_valid(hotbar_box):
		hotbar_box.queue_free()
	if rebirth_box and is_instance_valid(rebirth_box):
		rebirth_box.queue_free()
	hotbar.clear()
	var ids: Array = []
	var reborn: Array = []
	for s in Data.SPECIALS:
		if s.has("rebirth"):
			if game.specials.has(s["id"]):
				reborn.append(s["id"])
		elif not s.has("find") or game.specials.has(s["id"]):
			ids.append(s["id"])
	var per_row := 5 if ids.size() <= 10 else 8
	var cols := mini(per_row, ids.size())
	var rows := int(ceil(ids.size() / float(per_row)))
	var slot_size := px(80) if per_row == 5 else px(72)
	var gap := px(8) if per_row == 5 else px(6)
	var bar := GridContainer.new()
	bar.columns = cols
	bar.add_theme_constant_override("h_separation", int(gap))
	bar.add_theme_constant_override("v_separation", int(gap))
	var total_w := slot_size * cols + gap * (cols - 1)
	var total_h := slot_size * rows + gap * (rows - 1)
	bar.position = Vector2((vp.x - total_w) * 0.5, panel_top - total_h - px(12))
	bar.size = Vector2(total_w, total_h)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)
	if popup_layer and is_instance_valid(popup_layer):
		move_child(bar, popup_layer.get_index())   # stay under popups
	hotbar_box = bar
	for sid in ids:
		bar.add_child(_hotbar_slot(sid, px(80) if per_row == 5 else px(72)))
	# the rebirth column: first rebirth bomb at the bottom, the rest stacking up
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", int(px(8)))
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var r_size := px(80)
	var col_h := r_size * reborn.size() + px(8) * maxi(0, reborn.size() - 1)
	col.position = Vector2(px(12), panel_top - col_h - px(12))
	col.size = Vector2(r_size, col_h)
	add_child(col)
	if popup_layer and is_instance_valid(popup_layer):
		move_child(col, popup_layer.get_index())
	rebirth_box = col
	var stack := reborn.duplicate()
	stack.reverse()
	for sid in stack:
		col.add_child(_hotbar_slot(sid, r_size))


func _hotbar_slot(sid: String, slot_size: float) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(slot_size, slot_size)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.expand_icon = false
	b.pressed.connect(func():
		if game.specials.has(sid):
			game.fire_special(sid)
		else:
			game.sfx.play("error")
			switch_tab("bombs"))
	var spin := TextureRect.new()
	spin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(spin)
	b.add_child(center)
	var cd := _label("", fs(30), C_TEXT, true)
	cd.set_anchors_preset(Control.PRESET_FULL_RECT)
	cd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cd.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cd.add_theme_constant_override("outline_size", 6)
	cd.add_theme_color_override("font_outline_color", Color("120e0b"))
	b.add_child(cd)
	hotbar[sid] = {"button": b, "label": cd, "spin": spin, "state": ""}
	return b


func _refresh_hotbar() -> void:
	hotbar_box.visible = not game.specials.is_empty()
	if rebirth_box and is_instance_valid(rebirth_box):
		rebirth_box.visible = rebirth_box.get_child_count() > 0
	for sid in hotbar:
		var h: Dictionary = hotbar[sid]
		var b: Button = h["button"]
		var spin: TextureRect = h["spin"]
		var cd_label: Label = h["label"]
		var unlocked: bool = game.specials.has(sid)
		var cd: float = game.cooldowns.get(sid, 0.0)
		var state := "locked" if not unlocked else ("ready" if cd <= 0.0 else "cooling")
		if state == "ready" and sid == "mirror" and game.mirror_waiting():
			state = "waiting"   # reloaded, but nothing new to copy yet
		if state != h["state"]:
			# only touch styles/icons when something actually changed (cheap UI)
			var style: String = "slot_ready" if state == "ready" else "slot_btn"
			for st_name in ["normal", "hover", "disabled"]:
				b.add_theme_stylebox_override(st_name, st[style])
			b.add_theme_stylebox_override("pressed", st["slot"])
			b.add_theme_stylebox_override("hover_pressed", st["slot"])
			if state == "locked" or state == "waiting":
				b.icon = icon("lock", 3)
				spin.visible = false
				b.modulate = Color(1, 1, 1, 0.7)
			else:
				b.icon = null
				spin.visible = true
				if h["state"] in ["", "locked", "waiting"]:
					set_model_icon(spin, "bombs", sid, sid, 3)
				b.modulate = Color.WHITE if state == "ready" else Color(0.55, 0.55, 0.55)
			h["state"] = state
		cd_label.text = "" if state != "cooling" else str(int(ceil(cd)))
		cd_label.add_theme_color_override("font_color", C_TEXT)


func _build_toasts() -> void:
	toast_box = VBoxContainer.new()
	toast_box.position = Vector2(px(14), top_inset + px(140))
	toast_box.add_theme_constant_override("separation", int(px(6)))
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(toast_box)


func toast_ore(oid: String, n: int) -> void:
	var ore: Dictionary = game.ore_table[oid]
	if toasts.has(oid) and is_instance_valid(toasts[oid]["node"]):
		var t: Dictionary = toasts[oid]
		t["count"] += n
		t["time"] = 1.8
		t["dirty"] = true      # text is updated in _process, at most 10x a second
		return
	if toast_box.get_child_count() >= 6:
		var oldest := toast_box.get_child(0)
		for k in toasts.keys():
			if toasts[k]["node"] == oldest:
				toasts.erase(k)
		oldest.queue_free()
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", st["toast"])
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", int(px(8)))
	p.add_child(h)
	var ic := TextureRect.new()
	ic.texture = ore_icon(oid, 2)
	ic.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	set_model_icon(ic, "ores", oid, "gem", 2, ore["color"])
	h.add_child(ic)
	var col: Color = C_GOLD if ore["treasure"] else C_TEXT
	var l := _label("+%d %s" % [n, ore["name"].to_upper()], fs(25), col, true)
	h.add_child(l)
	toast_box.add_child(p)
	toasts[oid] = {"node": p, "label": l, "count": n, "time": 1.8, "dirty": false, "name": ore["name"].to_upper()}


# =============================================================================================
# Notifications: slide in from the right, just under the top bar, then slide away again.
# They never pause the game. Tap one to close it early (or to do its action, if it has one).
# =============================================================================================

const NOTE_MAX := 3          # on screen at once; the rest wait their turn
const NOTE_SLIDE := 0.3      # seconds to slide in / out

func _build_notes() -> void:
	note_layer = Control.new()
	note_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	note_layer.size = vp
	add_child(note_layer)


func notify(title: String, body: String, icon_tex: Texture2D = null, spin: Array = [], action := Callable(), secs := 5.0, epic := false, soft := false) -> void:
	var w := vp.x * (0.74 if epic else (0.6 if soft else 0.66))
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", st["note_epic"] if epic else (st["note_soft"] if soft else st["note"]))
	p.custom_minimum_size = Vector2(w, 0)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", int(px(10)))
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	var icon_w := 0.0
	if icon_tex:
		var ic := TextureRect.new()
		ic.texture = icon_tex
		ic.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(ic)
		if spin.size() >= 2:
			set_model_icon(ic, spin[0], spin[1], spin[1], 4 if epic else (2 if soft else 3))
		icon_w = maxf(ic.get_combined_minimum_size().x, px(56))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(px(2)))
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	var t := _label(title, fs(36) if epic else (fs(24) if soft else fs(26)), Color("fff1c9") if soft else C_GOLD, true)
	if epic:
		t.add_theme_constant_override("outline_size", int(px(8)))
		t.add_theme_color_override("font_outline_color", Color("5a1e8a"))
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size = Vector2(w - icon_w - px(40), 0)
	v.add_child(t)
	if body != "":
		var b := RichTextLabel.new()
		b.bbcode_enabled = true
		b.fit_content = true
		b.scroll_active = false
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.custom_minimum_size = Vector2(w - icon_w - px(40), 0)
		b.add_theme_font_size_override("normal_font_size", fs(25) if epic else (fs(20) if soft else fs(22)))
		b.add_theme_color_override("default_color", C_TEXT)
		b.text = body
		v.add_child(b)
	var note := {"node": p, "time": secs, "shown": false, "out": false, "epic": epic, "age": 0.0}
	p.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			p.accept_event()
			if note["out"]:
				return
			note["out"] = true
			note["time"] = minf(note["time"], NOTE_SLIDE)
			game.sfx.play("click")
			if action.is_valid():
				action.call())
	p.position = Vector2(vp.x + px(20), _notes_top())
	note_layer.add_child(p)
	notes.append(note)


## A quick full-screen flash of colour (fades by itself, never blocks taps).
func flash(c: Color, secs := 0.6) -> void:
	if game.reduce_flash:
		return
	var r := ColorRect.new()
	r.color = c
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.size = vp
	add_child(r)
	move_child(r, note_layer.get_index())
	var tw := r.create_tween()
	tw.tween_property(r, "color:a", 0.0, secs).set_ease(Tween.EASE_OUT)
	tw.tween_callback(r.queue_free)


## A colour wash over the whole screen that you fade in and out yourself (e.g. the red glow
## while the moon falls). Never blocks taps.
func screen_tint(c: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(c.r, c.g, c.b, 0.0)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.size = vp
	if game.reduce_flash:
		r.modulate.a = 0.35     # a gentle hint of colour instead
	add_child(r)
	move_child(r, note_layer.get_index())
	return r


## Grow Bomb: a big "tap!" readout in the middle of the screen while it charges.
var charge_box: VBoxContainer
var charge_title: Label
var charge_text: RichTextLabel

func show_charge(on: bool) -> void:
	if charge_box == null:
		charge_box = VBoxContainer.new()
		charge_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		charge_box.position = Vector2(0, vp.y * 0.3)
		charge_box.size = Vector2(vp.x, px(120))
		charge_title = _label("", fs(56), C_GOLD, true)
		charge_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		charge_title.add_theme_constant_override("outline_size", int(px(12)))
		charge_title.add_theme_color_override("font_outline_color", Color("120e0b"))
		charge_box.add_child(charge_title)
		charge_text = RichTextLabel.new()
		charge_text.bbcode_enabled = true
		charge_text.fit_content = true
		charge_text.scroll_active = false
		charge_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		charge_text.add_theme_font_size_override("normal_font_size", fs(32))
		charge_text.add_theme_constant_override("outline_size", int(px(8)))
		charge_text.add_theme_color_override("font_outline_color", Color("120e0b"))
		charge_box.add_child(charge_text)
		add_child(charge_box)
		move_child(charge_box, note_layer.get_index())
	charge_box.visible = on


func set_charge(title: String, body: String) -> void:
	if charge_box == null:
		show_charge(true)
	charge_title.text = title
	charge_text.text = "[center]%s[/center]" % body
	charge_title.pivot_offset = Vector2(vp.x * 0.5, fs(56) * 0.5)
	charge_title.scale = Vector2.ONE * (1.0 + 0.06 * sin(Time.get_ticks_msec() / 70.0))


func _notes_top() -> float:
	return hud_panel.position.y + hud_panel.size.y + px(10)


func _update_notes(delta: float) -> void:
	if game.loading_open:
		return   # wait until START is pressed
	var y := _notes_top()
	var k := 1.0 - exp(-delta * 14.0)
	var on_screen := 0
	for n in notes.duplicate():
		var p: PanelContainer = n["node"]
		if not is_instance_valid(p):
			notes.erase(n)
			continue
		var sz := p.get_combined_minimum_size()
		p.size = sz
		var showing := on_screen < NOTE_MAX
		if showing:
			on_screen += 1
			n["shown"] = true
			n["time"] -= delta
			if n["epic"]:
				# big moments glow and throb, with a little pop as they arrive
				n["age"] += delta
				var a: float = n["age"]
				p.pivot_offset = sz * 0.5
				p.scale = Vector2.ONE * (1.0 + 0.18 * exp(-a * 5.0) * absf(cos(a * 14.0)))
				var glow := 0.5 + 0.5 * sin(a * 7.0)
				p.modulate = Color(1.0 + 0.35 * glow, 1.0 + 0.25 * glow, 1.0 + 0.45 * glow)
		var leaving: bool = n["time"] <= NOTE_SLIDE
		var tx := vp.x - px(10) - sz.x if showing and not leaving else vp.x + px(20)
		p.position.x = lerpf(p.position.x, tx, k)
		p.position.y = lerpf(p.position.y, y, k) if n["shown"] else y
		if n["time"] <= 0.0:
			p.queue_free()
			notes.erase(n)
			continue
		if showing:
			y += sz.y + px(8)


## Optional performance readout (turn on in settings): frame rate and where the time goes.
func _build_perf() -> void:
	perf_label = _label("", fs(20), Color("9be36b"), true)
	perf_label.add_theme_constant_override("outline_size", 6)
	perf_label.add_theme_color_override("font_outline_color", Color("120e0b"))
	perf_label.position = Vector2(px(14), top_inset + px(120))
	perf_label.size = Vector2(vp.x - px(28), px(60))
	perf_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	perf_label.visible = false
	add_child(perf_label)


func _update_perf(delta: float) -> void:
	perf_label.visible = game.show_stats
	if not game.show_stats:
		return
	perf_timer -= delta
	if perf_timer > 0.0:
		return
	perf_timer = 0.5
	var fps := Engine.get_frames_per_second()
	var frame_ms := 1000.0 / maxf(fps, 1.0)
	var scripts := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var physics := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	perf_label.text = "FPS %d  (%.1f ms)\nscripts %.1f ms  physics %.1f ms\nbombs %d  gems %d  particles %d  draw calls %d\n%s" % [
		fps, frame_ms, scripts, physics, game.bombs_node.get_child_count(), game.gems_node.get_child_count(),
		game.fx.count, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), game.last_hitch]
	perf_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	perf_label.size = Vector2(vp.x - px(28), px(140))


func _build_hint() -> void:
	hint_label = _label("TAP TO DROP BOMBS", fs(40), C_TEXT, true)
	hint_label.add_theme_constant_override("outline_size", 8)
	hint_label.add_theme_color_override("font_outline_color", Color("120e0b"))
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.position = Vector2(0, top_inset + px(150))
	hint_label.size = Vector2(vp.x, px(50))
	add_child(hint_label)
	hint_label.visible = false


func _process(delta: float) -> void:
	_update_perf(delta)
	var turn: float = Time.get_ticks_msec() / 1000.0 * TAU / (float(game.ICON_FRAMES) / float(game.ICON_FPS))
	for f in flippers:
		if is_instance_valid(f):
			f.pivot_offset = f.size * 0.5
			f.scale.x = cos(turn)
	_update_notes(delta)
	toast_timer -= delta
	var update_text := toast_timer <= 0.0
	if update_text:
		toast_timer = 0.1
	for k in toasts.keys():
		var t: Dictionary = toasts[k]
		t["time"] -= delta
		if not is_instance_valid(t["node"]):
			toasts.erase(k)
			continue
		if update_text and t.get("dirty", false):
			t["dirty"] = false
			t["label"].text = "+%s %s" % [game.fmt(float(t["count"])), t["name"]]
			t["node"].modulate.a = 1.0
		if t["time"] < 0.4:
			t["node"].modulate.a = maxf(0.0, t["time"] / 0.4)
		if t["time"] <= 0.0:
			t["node"].queue_free()
			toasts.erase(k)
	if hint_label.visible:
		hint_label.modulate.a = 0.6 + 0.4 * sin(Time.get_ticks_msec() / 250.0)


func refresh() -> void:
	if coins_label == null:
		return
	coins_label.text = game.fmt(game.coins)
	rebirth_btn.visible = game.rebirth_ready or game.rebirths > 0
	rebirth_btn.modulate = Color.WHITE if game.rebirth_ready else Color(0.75, 0.75, 0.75)
	var w: int = game.current_world
	world_label.text = Data.WORLDS[w]["name"].to_upper()
	var main_d: int = game.pillar.depth
	if game.pillar.bedrock_broken():
		var vd := int(maxf(0.0, game.pillar.floor_depth() - main_d - 1) * Data.VOXEL)
		var vt := int(Data.VAULT_LAYERS * Data.VOXEL)
		depth_label.text = "VAULT %dm / %dm" % [mini(vd, vt), vt]
	else:
		var depth_m := int(game.pillar.floor_depth() * Data.VOXEL)
		var total_m := int(main_d * Data.VOXEL)
		depth_label.text = "%dm / %dm" % [mini(depth_m, total_m), total_m]
	depth_bar.queue_redraw()
	_refresh_hotbar()
	for f in refreshers:
		f.call()


# =============================================================================================
# Popups
# =============================================================================================

func _build_popup_layer() -> void:
	popup_layer = Control.new()
	popup_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	popup_layer.visible = false
	add_child(popup_layer)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.02, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup_layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup_layer.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(minf(px(600), vp.x - px(40)), 0)
	center.add_child(panel)
	popup_box = VBoxContainer.new()
	popup_box.add_theme_constant_override("separation", int(px(18)))
	panel.add_child(popup_box)


## buttons: [[text, Callable, style("gold"/"green"/"red")], ...]
## spin: [folder, id] of a bomb/ore model to show spinning instead of the still icon.
func show_popup(title: String, body: String, buttons: Array, icon_tex: Texture2D = null, spin: Array = [], extra: Control = null) -> void:
	for c in popup_box.get_children():
		c.queue_free()
	if icon_tex:
		var ic := TextureRect.new()
		ic.texture = icon_tex
		ic.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		popup_box.add_child(ic)
		if spin.size() >= 4:   # [folder, id, fallback icon, tint]
			set_model_icon(ic, spin[0], spin[1], spin[2], 5, spin[3])
		elif spin.size() >= 2:
			set_model_icon(ic, spin[0], spin[1], spin[1], 5)
	var t := _label(title, fs(40), C_GOLD, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	popup_box.add_child(t)
	var b := RichTextLabel.new()
	b.bbcode_enabled = true
	b.fit_content = true
	b.scroll_active = false
	b.add_theme_font_size_override("normal_font_size", fs(30))
	b.add_theme_color_override("default_color", C_TEXT)
	b.text = "[center]%s[/center]" % body
	popup_box.add_child(b)
	if extra:
		popup_box.add_child(extra)
	# up to 3 buttons sit in a row; more than that go in a 2-wide grid
	var row: Container
	if buttons.size() > 3:
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", int(px(12)))
		grid.add_theme_constant_override("v_separation", int(px(10)))
		row = grid
	else:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", int(px(12)))
		row = hb
	popup_box.add_child(row)
	for bd in buttons:
		var btn := Button.new()
		btn.text = bd[0]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(px(0), px(80))
		btn.add_theme_font_size_override("font_size", fs(30))
		if bd.size() > 2 and bd[2] != "gold":
			_style_button(btn, bd[2])
		var cb: Callable = bd[1]
		btn.pressed.connect(func():
			game.sfx.play("click")
			popup_layer.visible = false
			if cb.is_valid():
				cb.call())
		row.add_child(btn)
	popup_layer.visible = true


func popup_open() -> bool:
	return popup_layer.visible


func show_settings() -> void:
	game.sfx.play("click")
	show_popup("SETTINGS", "Sound, vibration, flashing, stats, saves and cheats.\n[color=#b9a990]Reduce flashing turns off screen flashes and camera shake.[/color]", [
		["SOUND: " + ("ON" if game.sound_on else "OFF"), func():
			game.set_sound(not game.sound_on)
			show_settings(), "gold"],
		["VIBRATE: " + ("ON" if game.vibrate_on else "OFF"), func():
			game.vibrate_on = not game.vibrate_on
			show_settings(), "gold"],
		["REDUCE FLASHING: " + ("ON" if game.reduce_flash else "OFF"), func():
			game.reduce_flash = not game.reduce_flash
			game.save_game()
			show_settings(), "gold"],
		["FPS: " + ("ON" if game.show_stats else "OFF"), func():
			game.show_stats = not game.show_stats
			show_settings(), "gold"],
		["STATS", func(): show_stats_page(), "gold"],
		["SAVES", func(): show_saves(), "gold"],
		["CHEATS", func(): _cheats_door(), "red"],
		["CLOSE", Callable(), "green"],
	], icon("gear", 4))


func show_saves() -> void:
	game.sfx.play("click")
	var lines := "Your game saves itself. Copy it into a slot to keep it, or load a slot to go back to it.\n"
	var buttons: Array = []
	for i in range(1, game.SAVE_SLOTS + 1):
		var info: Dictionary = game.slot_info(i)
		if info["exists"]:
			var when := Time.get_datetime_string_from_unix_time(int(info["time"]) + int(Time.get_time_zone_from_system()["bias"]) * 60, true)
			lines += "\n[color=#ffcf5a]SLOT %d[/color]  %s, %s coins\n[color=#b9a990]%s[/color]" % [i, info["world"], game.fmt(info["coins"]), when.substr(0, 16)]
		else:
			lines += "\n[color=#ffcf5a]SLOT %d[/color]  [color=#b9a990]empty[/color]" % i
		var idx := i
		buttons.append(["SAVE %d" % i, func():
			if info["exists"]:
				_confirm("OVERWRITE SLOT %d?" % idx, "The game in slot %d will be replaced by your current game." % idx, "SAVE", func():
					game.save_to_slot(idx)
					show_saves())
			else:
				game.save_to_slot(idx)
				show_saves(), "gold"])
		buttons.append(["LOAD %d" % i, func():
			if not info["exists"]:
				game.sfx.play("error")
				show_saves()
				return
			_confirm("LOAD SLOT %d?" % idx, "Your current game will be replaced by slot %d.\nSave it to another slot first if you want to keep it." % idx, "LOAD", func(): game.load_slot(idx)), "green" if info["exists"] else "gold"])
	buttons.append(["EXPORT SAVE", func(): _export_save(), "green"])
	buttons.append(["IMPORT SAVE", func(): _import_save(), "gold"])
	buttons.append(["NEW GAME", func():
		_confirm("START OVER?", "Your current game is wiped and you start fresh in Grasslands.\nSave slots are kept.", "START OVER", func(): game.new_game()), "red"])
	buttons.append(["BACK", func(): show_settings(), "gold"])
	show_popup("SAVES", lines, buttons, icon("world", 4))


## CHEATS need a password (once per time the app is opened).
const CHEAT_PASSWORD := "NECROPOLIS"

func _cheats_door() -> void:
	game.sfx.play("click")
	if game.cheats_unlocked:
		show_testing()
		return
	var box := LineEdit.new()
	box.placeholder_text = "Password"
	box.alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.custom_minimum_size = Vector2(px(380), px(70))
	box.add_theme_font_size_override("font_size", fs(32))
	box.secret = true
	var try := func():
		if box.text.strip_edges().to_upper() == CHEAT_PASSWORD:
			game.cheats_unlocked = true
			game.sfx.play("unlock")
			show_testing()
		else:
			game.sfx.play("error")
			show_popup("WRONG PASSWORD", "That's not it.", [["TRY AGAIN", func(): _cheats_door(), "gold"], ["BACK", func(): show_settings(), "green"]], icon("lock", 4))
	box.text_submitted.connect(func(_t): popup_layer.visible = false; try.call())
	var row := CenterContainer.new()
	row.add_child(box)
	show_popup("CHEATS", "Enter the password.", [["BACK", func(): show_settings(), "gold"], ["ENTER", try, "green"]], icon("lock", 4), [], row)
	box.call_deferred("grab_focus")


func show_testing() -> void:
	game.sfx.play("click")
	show_popup("CHEATS", "Free stuff for testing the game.\nCoins: %s" % game.fmt(game.coins), [
		["+ COINS", func():
			game.cheat_coins()
			show_testing(), "gold"],
		["+5 UPGRADES", func():
			game.cheat_upgrades()
			show_testing(), "gold"],
		["+10 COSMIC EGGS", func():
			game.cheat_eggs()
			show_testing(), "gold"],
		["READY TO REBIRTH", func():
			game.rebirth_ready = true
			game.save_game()
			rebuild_tab()
			game.show_rebirth_popup(), "gold"],
		["+1 RELIC", func():
			for rl in Data.RELICS:
				if not game.has_relic(rl["id"]):
					game._open_cache(int(rl["find"]))
					return
			show_testing(), "gold"],
		["SET COINS", func(): _set_coins(), "blue"],
		["BACK", func(): show_settings(), "green"],
		["MAX OUT ACCOUNT", func():
			_confirm("MAX OUT?", "Every upgrade, world, bomb and relic, 20 rebirths, and more coins than you can spend.\nExport your save first if you want to keep it as it is.", "MAX OUT", func(): game.cheat_max_out(), func(): show_testing()), "red"],
	], icon("coin", 4))


## Cheats: type an exact coin amount. Accepts 1500, 2.5M, 3qa, 1e30, 1,000,000.
func _set_coins() -> void:
	game.sfx.play("click")
	var box := LineEdit.new()
	box.placeholder_text = "e.g. 2.5M or 1e30"
	box.text = game.fmt(game.coins)
	box.alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.custom_minimum_size = Vector2(px(380), px(70))
	box.add_theme_font_size_override("font_size", fs(32))
	box.select_all_on_focus = true
	var apply := func():
		var v := parse_amount(box.text)
		if v < 0.0:
			game.sfx.play("error")
			show_popup("NOT A NUMBER", "Try something like [color=#ffcf5a]5000[/color], [color=#ffcf5a]2.5M[/color], [color=#ffcf5a]3Qa[/color] or [color=#ffcf5a]1e30[/color].", [["BACK", func(): show_testing(), "gold"], ["TRY AGAIN", func(): _set_coins(), "blue"]], icon("coin", 4))
			return
		game.cheat_set_coins(v)
		show_testing()
	box.text_submitted.connect(func(_t): popup_layer.visible = false; apply.call())
	var row := CenterContainer.new()
	row.add_child(box)
	var sfx_list := ", ".join(game.SUFFIXES)
	show_popup("SET COINS", "How many coins?\nSuffixes: [color=#ffcf5a]%s[/color]" % sfx_list, [["BACK", func(): show_testing(), "gold"], ["SET", apply, "blue"]], icon("coin", 4), [], row)
	box.call_deferred("grab_focus")


## Reads "2.5M", "3qa", "1e30", "1,000" etc. Returns -1 if it can't.
func parse_amount(text: String) -> float:
	var t := text.strip_edges().replace(",", "").replace(" ", "").replace("_", "")
	if t.is_empty():
		return -1.0
	var mult := 1.0
	var low := t.to_lower()
	for i in range(game.SUFFIXES.size() - 1, -1, -1):
		var suf: String = String(game.SUFFIXES[i]).to_lower()
		if low.ends_with(suf) and low.length() > suf.length():
			var num := t.substr(0, t.length() - suf.length())
			if num.is_valid_float():
				mult = pow(1000.0, i + 1)
				t = num
				break
	if not t.is_valid_float():
		return -1.0
	var v := t.to_float() * mult
	if is_nan(v) or is_inf(v) or v < 0.0:
		return -1.0
	return floorf(v)


## Save backup: copies the whole game as a code you can paste somewhere safe (like Notes).
func _export_save() -> void:
	var code: String = game.export_save_code()
	DisplayServer.clipboard_set(code)
	game.sfx.play("unlock")
	show_popup("SAVE COPIED",
		"Your whole game was copied as a save code ([color=#ffcf5a]%s[/color] letters).\n\nPaste it somewhere safe, like the Notes app.\nTo get it back: copy the code, then tap [color=#ffcf5a]IMPORT SAVE[/color]." % game.fmt(float(code.length())),
		[["OK", func(): show_saves(), "green"]], icon("world", 4))


func _import_save() -> void:
	game.sfx.play("click")
	var code := DisplayServer.clipboard_get().strip_edges()
	if not code.begins_with(game.SAVE_CODE_PREFIX):
		game.sfx.play("error")
		show_popup("NO SAVE CODE", "Copy your save code first (the whole thing, starting with [color=#ffcf5a]BLASTPILLAR1:[/color]), then tap IMPORT SAVE again.",
			[["OK", func(): show_saves(), "gold"]], icon("world", 4))
		return
	_confirm("IMPORT SAVE?", "Your current game will be replaced by the copied save.\nExport it first if you want to keep it.", "IMPORT", func():
		var err: String = game.import_save_code(code)
		if err != "":
			game.sfx.play("error")
			show_popup("IMPORT FAILED", err, [["OK", func(): show_saves(), "gold"]], icon("world", 4)))


## Lifetime stats (kept through rebirths) and how far this run has got.
func show_stats_page() -> void:
	game.sfx.play("click")
	var st: Dictionary = game.stats
	var secs := int(float(st.get("time", 0.0)))
	var played := "%dh %dm" % [secs / 3600, (secs / 60) % 60] if secs >= 3600 else "%dm %ds" % [secs / 60, secs % 60]
	var n := func(k: String) -> String: return game.fmt(float(st.get(k, 0.0)))
	var hidden := 0
	var hidden_total := 0
	for sp in Data.SPECIALS:
		if sp.has("find"):
			hidden_total += 1
			if game.specials.has(sp["id"]):
				hidden += 1
	var lines := "[color=#ffcf5a]ALL TIME[/color]"
	lines += "\nPlay time: [color=#ffcf5a]%s[/color]" % played
	lines += "\nRebirths: [color=#ffcf5a]%d[/color]" % game.rebirths
	lines += "\nBlocks blasted: [color=#ffcf5a]%s[/color]" % n.call("blocks")
	lines += "\nTaps: [color=#ffcf5a]%s[/color]   Bombs you dropped: [color=#ffcf5a]%s[/color]" % [n.call("taps"), n.call("bombs")]

	lines += "\nSpecial bombs fired: [color=#ffcf5a]%s[/color]" % n.call("specials")
	lines += "\nCoins earned: [color=#ffcf5a]%s[/color]" % n.call("coins")
	lines += "\nOres dug up: [color=#ffcf5a]%s[/color]" % n.call("ores")
	lines += "\nPillars cleared: [color=#ffcf5a]%s[/color]" % n.call("bottoms")
	lines += "\nBedrock broken: [color=#ffcf5a]%s[/color]   Cosmic Eggs: [color=#ffcf5a]%s[/color]" % [n.call("bedrocks"), n.call("eggs")]
	lines += "\n\n[color=#ffcf5a]THIS RUN[/color]"
	lines += "\nWorlds open: [color=#ffcf5a]%d/%d[/color]" % [game.unlocked_worlds, Data.WORLDS.size()]
	lines += "\nHidden bombs: [color=#ffcf5a]%d/%d[/color]   Relics: [color=#ffcf5a]%d/%d[/color]" % [hidden, hidden_total, game.relics.size(), Data.RELICS.size()]
	lines += "\nCoins: [color=#ffcf5a]%s[/color]" % game.fmt(game.coins)
	show_popup("STATS", lines, [["BACK", func(): show_settings(), "gold"]], icon("power", 4))


func _confirm(title: String, body: String, yes: String, action: Callable, back := Callable()) -> void:
	var cancel := back if back.is_valid() else func(): show_saves()
	show_popup(title, body, [["CANCEL", cancel, "gold"], [yes, action, "red"]], icon("world", 4))
