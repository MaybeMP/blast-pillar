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
var world_label: Label
var depth_label: Label
var depth_bar: Control
var hint_label: Label
var perf_label: Label
var perf_timer := 0.0
var toast_box: VBoxContainer
var toasts := {}
var toast_timer := 0.0
var hotbar := {}
var hotbar_box: Control
var tab_buttons := {}
var current_tab := ""
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
	st["gray"] = PA.frame(Color("4f4a44"), Color("625c55"), Color("37332f"), 2, false, btn_pad)
	st["tab_on"] = PA.frame(Color("5a4d41"), Color("7a6a5a"), Color("3d342c"), 2, false, Vector4(px(6), px(8), px(6), px(10)))
	st["tab_off"] = PA.frame(Color("2a231d"), Color("3a312a"), Color("1a1512"), 2, false, Vector4(px(6), px(8), px(6), px(10)))
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
	# size first, then the texture, so the wide strip never stretches the layout
	target.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	target.stretch_mode = TextureRect.STRETCH_SCALE
	target.custom_minimum_size = Vector2(size, size)
	target.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	target.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	target.material = spin_material()
	target.texture = strip
	target.size = Vector2(size, size)


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
	row.add_child(coins_label)

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
	for t in [["upgrades", "UPGRADES"], ["bombs", "BOMBS"], ["ores", "ORES"], ["worlds", "WORLDS"]]:
		var b := Button.new()
		b.text = t[1]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(px(0), px(58))
		b.add_theme_font_size_override("font_size", fs(25))
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
			b.add_theme_color_override(c, C_TEXT)
		b.pressed.connect(func():
			game.sfx.play("click")
			switch_tab(t[0]))
		tabs.add_child(b)
		tab_buttons[t[0]] = b

	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", int(px(8)))
	content.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.add_child(content)


func switch_tab(id: String) -> void:
	current_tab = id
	for k in tab_buttons:
		var b: Button = tab_buttons[k]
		var s: StyleBox = st["tab_on"] if k == id else st["tab_off"]
		for state in ["normal", "hover", "pressed", "hover_pressed"]:
			b.add_theme_stylebox_override(state, s)
		b.add_theme_color_override("font_color", C_GOLD if k == id else C_SUB)
		b.add_theme_color_override("font_hover_color", C_GOLD if k == id else C_SUB)
	for c in content.get_children():
		c.queue_free()
	refreshers.clear()
	scroll.scroll_vertical = 0
	match id:
		"upgrades": _tab_upgrades()
		"bombs": _tab_bombs()
		"ores": _tab_ores()
		"worlds": _tab_worlds()
	refresh()


func rebuild_tab() -> void:
	switch_tab(current_tab)


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
	# Auto-bomber for the world you're in
	var a := _row(icon("auto"), "Auto-Bomber")
	a["button"].pressed.connect(func(): game.buy_auto())
	refreshers.append(func():
		var w: int = game.current_world
		var lvl: int = game.worlds[w]["auto"]
		var cost: Dictionary = game.auto_cost(w)
		var wname: String = Data.WORLDS[w]["name"]
		if lvl >= game.AUTO_MAX:
			a["info"].text = "LV %d  [color=#ffcf5a]%.2f bombs/sec[/color] in %s" % [lvl, game.auto_rate(w), wname]
			if game.world_empty(w):
				a["info"].text += "\n[color=#b9a990]Resting: nothing left to blast here.[/color]"
			a["button"].text = "MAX"
			a["button"].icon = null
			a["button"].disabled = true
			return
		if lvl == 0:
			var needs := cost_text(cost)
			a["info"].text = "Drops bombs in %s, even while you're away." % wname + ("\nNeeds " + needs if needs != "" else "")
		else:
			var needs := cost_text(cost)
			a["info"].text = "LV %d  [color=#ffcf5a]%.2f bombs/sec[/color] in %s" % [lvl, game.auto_rate(w), wname] + ("\nNeeds " + needs if needs != "" else "")
			if game.world_empty(w):
				a["info"].text += "\n[color=#b9a990]Resting: nothing left to blast here.[/color]"
		_set_cost_button(a["button"], cost, "UNLOCK"))

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
	_relic_rows()


## Relics: shown once you can reach the Deep Realms (or already own one).
func _relic_rows() -> void:
	if game.unlocked_worlds <= Data.ORIGINAL_WORLDS and game.relics.is_empty():
		return
	content.add_child(_label("RELICS", fs(25), C_GOLD, true))
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
	_bedrock_row()
	var rebirth_row_done := false
	for s in Data.SPECIALS:
		var sid: String = s["id"]
		if s.has("rebirth"):
			if not rebirth_row_done:
				rebirth_row_done = true
				_rebirth_row()
			if game.rebirths < 1 and not game.specials.has(sid):
				continue   # the rebirth bombs show up after your first rebirth
		var r := _row(micon("bombs", sid, sid), s["name"])
		set_model_icon(r["icon"], "bombs", sid, sid, 3)
		r["button"].pressed.connect(func():
			if game.specials.has(sid):
				game.fire_special(sid)
			else:
				game.unlock_special(sid))
		if game.specials.has(sid):
			r["button"].custom_minimum_size = Vector2(px(130), px(72))
		# reload upgrade button (shows after unlocking)
		var up := Button.new()
		up.custom_minimum_size = Vector2(px(150), px(72))
		up.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		up.mouse_filter = Control.MOUSE_FILTER_PASS
		var hb: Node = r["button"].get_parent()
		hb.add_child(up)
		hb.move_child(up, r["button"].get_index())
		up.pressed.connect(func(): game.upgrade_special(sid))
		var hidden: bool = s.has("find")
		var reborn_bomb: bool = s.has("rebirth")
		refreshers.append(func():
			if reborn_bomb and not game.specials.has(sid):
				r["title"].text = "???"
				r["icon"].modulate = Color(0, 0, 0, 0.75)
				r["info"].text = "Unlocks for good at [color=#ffcf5a]%d rebirths[/color] (you have %d)." % [int(s["rebirth"]), game.rebirths]
				r["button"].text = "LOCKED"
				r["button"].icon = icon("lock", 2)
				r["button"].disabled = true
				up.visible = false
				return
			if reborn_bomb:
				r["title"].text = s["name"]
				r["icon"].modulate = Color.WHITE
			if hidden and not game.specials.has(sid):
				var fw: int = int(s["find"])
				r["title"].text = "???"
				r["icon"].modulate = Color(0, 0, 0, 0.75)
				r["info"].text = ("Hidden in the vault under the bedrock of %s." % Data.WORLDS[fw]["name"]) if fw < game.unlocked_worlds else "Hidden somewhere deeper..."
				r["button"].text = "HIDDEN"
				r["button"].icon = icon("lock", 2)
				r["button"].disabled = true
				up.visible = false
				return
			if hidden:
				r["title"].text = s["name"]
				r["icon"].modulate = Color.WHITE
			if game.specials.has(sid):
				var cd: float = game.cooldowns.get(sid, 0.0)
				var lvl: int = game.special_level(sid)
				var reload_txt := "Reload [color=#ffcf5a]%ds[/color]" % int(round(game.special_cooldown(sid)))
				if lvl < Data.SPECIAL_MAX_LEVEL:
					var nxt: float = game.special_cooldown_at(sid, lvl + 1)
					reload_txt += ", upgrade to [color=#9be36b]%ds[/color]" % int(round(nxt))
				r["info"].text = s["desc"] + "\n" + reload_txt
				if sid == "mirror":
					var copy: String = game.mirror_copy
					r["info"].text = s["desc"] + "\nReloads as long as the bomb it copies"
					if copy != "":
						r["info"].text += " ([color=#ffcf5a]%ds[/color])" % int(round(game.special_cooldown(copy)))
					r["info"].text += "\nNext copy: " + ("[color=#b46bff]%s[/color]" % game.special_name(copy) if copy != "" else "[color=#b9a990]locked until you fire another special bomb[/color]")
				r["button"].text = "FIRE"
				r["button"].icon = null
				_style_button(r["button"], "red")
				r["button"].disabled = cd > 0.0 or (sid == "mirror" and game.mirror_waiting())
				up.visible = sid != "mirror"   # its reload comes from the copied bomb, so nothing to upgrade
				if lvl >= Data.SPECIAL_MAX_LEVEL:
					up.text = "MAX"
					up.icon = null
					up.disabled = true
				else:
					var c: float = game.special_upgrade_cost(sid)
					up.text = game.fmt(c)
					up.icon = icon("coin", 2)
					up.disabled = game.coins < c
			else:
				up.visible = false
				r["info"].text = s["desc"] + "\nNeeds " + cost_text(s["cost"])
				_set_cost_button(r["button"], s["cost"], "UNLOCK"))


## Rebirth: shows once you've broken the Star Core (or have reborn before).
func _rebirth_row() -> void:
	if not game.rebirth_ready and game.rebirths < 1:
		return
	var head := _label("REBIRTH", fs(25), C_GOLD, true)
	content.add_child(head)
	var r := _row(icon("world", 3, Color("ffcf5a")), "Rebirth")
	r["button"].text = "REBIRTH"
	_style_button(r["button"], "red")
	r["button"].pressed.connect(func():
		game.sfx.play("click")
		game.show_rebirth_popup())
	refreshers.append(func():
		var line := "Rebirths: [color=#ffcf5a]%d[/color]   Damage [color=#ffcf5a]x%.2f[/color]" % [game.rebirths, game.rebirth_mult()]
		if game.rebirth_ready:
			line += "\nReady! Start over with +%d%% damage." % int(Data.REBIRTH_DAMAGE * 100)
		else:
			line += "\nBreak the Star Core at the bottom of %s's vault to rebirth again." % Data.WORLDS[Data.STAR_CORE_WORLD]["name"]
		r["info"].text = line
		r["button"].disabled = not game.rebirth_ready)


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
		var tname: String = game.ore_table[tid]["name"]
		var egg_world: String = Data.WORLDS[int(game.ore_table[tid]["world"])]["name"]
		var state: String = game.bedrock_bomb_state()
		var line := "One use: shatters the whole bedrock layer of %s." % Data.WORLDS[w]["name"]
		match state:
			"not_reached":
				line += "\n[color=#b9a990]Dig down to the bedrock first.[/color]  Costs %d/%d %s (from the bottom of %s)" % [have, Data.BEDROCK_BOMB_COST, tname, egg_world]
			"broken":
				line = "The bedrock of %s is already broken. Dig the vault!" % Data.WORLDS[w]["name"]
			_:
				var col := "9be36b" if have >= Data.BEDROCK_BOMB_COST else "ff6b5a"
				line += "\nCosts [color=#%s]%d/%d[/color] %s (from the bottom of %s)" % [col, have, Data.BEDROCK_BOMB_COST, tname, egg_world]
		r["info"].text = line
		r["button"].disabled = state != "ready")


func _tab_ores() -> void:
	for w in Data.WORLDS.size():
		var world: Dictionary = Data.WORLDS[w]
		var unlocked: bool = w < game.unlocked_worlds
		if w > game.unlocked_worlds:
			break
		var head := _label(world["name"].to_upper() if unlocked else "??? (LOCKED WORLD)", fs(25), C_GOLD if unlocked else C_SUB, true)
		content.add_child(head)
		if not unlocked:
			continue
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", int(px(8)))
		grid.add_theme_constant_override("v_separation", int(px(8)))
		grid.mouse_filter = Control.MOUSE_FILTER_PASS
		content.add_child(grid)
		var ids: Array = []
		for o in world["ores"]:
			ids.append(o["id"])
		ids.append(world["treasure"]["id"])
		for oid in ids:
			grid.add_child(_ore_cell(oid))


## One ore in the ORES tab: icon, name, how many you have, and the price with - (sell) / + (buy).
func _ore_cell(oid: String) -> Control:
	var cell := PanelContainer.new()
	cell.add_theme_stylebox_override("panel", st["slot"])
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.custom_minimum_size = Vector2(0, px(96))
	cell.mouse_filter = Control.MOUSE_FILTER_PASS
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", int(px(6)))
	h.mouse_filter = Control.MOUSE_FILTER_PASS
	cell.add_child(h)
	var seen: bool = game.ores_seen.has(oid)
	var ic := TextureRect.new()
	ic.texture = ore_icon(oid, 3)
	ic.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if seen:
		set_model_icon(ic, "ores", oid, "gem", 3, game.ore_table[oid]["color"])
	else:
		ic.modulate = Color(0, 0, 0, 0.75)   # silhouette until you find it
	h.add_child(ic)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	var nm := _label(game.ore_table[oid]["name"] if seen else "???", fs(20), C_SUB)
	nm.clip_text = true
	nm.custom_minimum_size = Vector2(px(60), 0)
	v.add_child(nm)
	var cnt := _label("0", fs(25), C_TEXT, true)
	v.add_child(cnt)
	refreshers.append(func(): cnt.text = game.fmt(float(game.ores.get(oid, 0))))
	if not seen:
		return cell
	if not game.ore_tradable(oid):
		var note := _label("Bottom of\nWorld 6", fs(20), C_SUB)
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		h.add_child(note)
		return cell

	# price on top, - and + underneath
	var trade := VBoxContainer.new()
	trade.add_theme_constant_override("separation", int(px(4)))
	trade.alignment = BoxContainer.ALIGNMENT_CENTER
	trade.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(trade)
	var price_row := HBoxContainer.new()
	price_row.alignment = BoxContainer.ALIGNMENT_CENTER
	price_row.add_theme_constant_override("separation", int(px(4)))
	price_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	trade.add_child(price_row)
	var coin := TextureRect.new()
	coin.texture = icon("coin", 1)
	coin.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	price_row.add_child(coin)
	var price := _label("0", fs(20), C_GOLD, true)
	price_row.add_child(price)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", int(px(4)))
	btns.mouse_filter = Control.MOUSE_FILTER_PASS
	trade.add_child(btns)
	var minus := Button.new()
	minus.text = "-"
	var plus := Button.new()
	plus.text = "+"
	for pair in [[minus, "red"], [plus, "green"]]:
		var b: Button = pair[0]
		b.custom_minimum_size = Vector2(px(56), px(46))
		b.mouse_filter = Control.MOUSE_FILTER_PASS
		b.add_theme_font_size_override("font_size", fs(30))
		_style_button(b, pair[1])
		btns.add_child(b)
	minus.pressed.connect(func(): game.sell_ore(oid))
	plus.pressed.connect(func(): game.buy_ore(oid))
	refreshers.append(func():
		var p: float = game.ore_value(oid)
		price.text = game.fmt(p)
		plus.disabled = game.coins < p
		minus.disabled = int(game.ores.get(oid, 0)) <= 0)
	return cell


func _tab_worlds() -> void:
	for w in Data.WORLDS.size():
		var world: Dictionary = Data.WORLDS[w]
		var r := _row(world_icon(w, 3), world["name"])
		var idx := w
		r["button"].pressed.connect(func(): game.travel(idx))
		var reset := Button.new()
		reset.text = "RESET"
		reset.custom_minimum_size = Vector2(px(130), px(72))
		reset.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		reset.mouse_filter = Control.MOUSE_FILTER_PASS
		reset.add_theme_font_size_override("font_size", fs(25))
		_style_button(reset, "red")
		var hb: Node = r["button"].get_parent()
		hb.add_child(reset)
		hb.move_child(reset, r["button"].get_index())
		r["button"].custom_minimum_size = Vector2(px(150), px(72))
		reset.pressed.connect(func():
			game.sfx.play("click")
			show_popup("RESET %s?" % Data.WORLDS[idx]["name"].to_upper(),
				"This grows a brand new pillar so you can blast it again.\nYour coins, ores and upgrades stay.",
				[["CANCEL", Callable(), "gold"], ["RESET", func(): game.reset_world(idx), "red"]], world_icon(idx, 5)))
		refreshers.append(func():
			var unlocked: bool = idx < game.unlocked_worlds
			var data: Dictionary = game.worlds[idx]
			reset.visible = unlocked and bool(data.get("done", false))
			r["icon"].modulate = Color.WHITE if unlocked else Color(0, 0, 0, 0.75)
			if not unlocked:
				r["title"].text = "???"
				var need: String = game.world_needs(idx)
				if need != "":
					var home: int = game.special_home(need)
					var have := "[color=#9be36b]found[/color]" if game.specials.has(need) else "[color=#ff6b5a]not found[/color]"
					r["info"].text = "A Deep Realm. Reach the bottom of %s and find the %s (%s), hidden under the bedrock of %s." % [Data.WORLDS[idx - 1]["name"], game.special_name(need), have, Data.WORLDS[home]["name"]]
				else:
					r["info"].text = "Break through the bottom of %s to open the portal." % Data.WORLDS[idx - 1]["name"]
				r["button"].text = "LOCKED"
				r["button"].icon = icon("lock", 2)
				r["button"].disabled = true
				return
			var tags: Array = []
			if int(data["auto"]) > 0:
				tags.append("Auto %.2f/s" % game.auto_rate(idx))
			if data.get("done", false):
				tags.append("[color=#9be36b]BEDROCK REACHED[/color]")
			var txt := "  ".join(tags)
			if data.get("bedrock_broken", false):
				txt += "  [color=#ffcf5a]VAULT OPEN[/color]"
			for sp in Data.SPECIALS:
				if int(sp.get("find", -1)) == idx and game.specials.has(sp["id"]):
					txt += "  [color=#b46bff]BOMB FOUND[/color]"
			for rl in Data.RELICS:
				if int(rl["find"]) == idx and game.has_relic(rl["id"]):
					txt += "  [color=#b46bff]RELIC FOUND[/color]"
			r["info"].text = txt
			r["button"].icon = null
			if idx == game.current_world:
				r["button"].text = "HERE"
				r["button"].disabled = true
			else:
				r["button"].text = "TRAVEL"
				_style_button(r["button"], "green")
				r["button"].disabled = false)


# =============================================================================================
# Hotbar, toasts, hint
# =============================================================================================

func _build_hotbar() -> void:
	rebuild_hotbar()


## The hotbar: the 4 shop bombs (locked ones show a padlock) plus any hidden bombs you've found.
## Up to 5 per row; a second row appears once you have more than 5.
func rebuild_hotbar() -> void:
	if hotbar_box and is_instance_valid(hotbar_box):
		hotbar_box.queue_free()
	hotbar.clear()
	var ids: Array = []
	for s in Data.SPECIALS:
		if (not s.has("find") and not s.has("rebirth")) or game.specials.has(s["id"]):
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
		bar.add_child(b)
		hotbar[sid] = {"button": b, "label": cd, "spin": spin, "state": ""}


func _refresh_hotbar() -> void:
	hotbar_box.visible = not game.specials.is_empty()
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
		if sid == "overclock" and game.overclocked():
			cd_label.text = "x2 %d" % int(ceil(game.overclock_left()))
			cd_label.add_theme_color_override("font_color", C_GOLD)
		else:
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
func show_popup(title: String, body: String, buttons: Array, icon_tex: Texture2D = null, spin: Array = []) -> void:
	for c in popup_box.get_children():
		c.queue_free()
	if icon_tex:
		var ic := TextureRect.new()
		ic.texture = icon_tex
		ic.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		popup_box.add_child(ic)
		if spin.size() >= 2:
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
	show_popup("SETTINGS", "Sound, vibration, saves and testing tools.", [
		["SOUND: " + ("ON" if game.sound_on else "OFF"), func():
			game.set_sound(not game.sound_on)
			show_settings(), "gold"],
		["VIBRATE: " + ("ON" if game.vibrate_on else "OFF"), func():
			game.vibrate_on = not game.vibrate_on
			show_settings(), "gold"],
		["STATS: " + ("ON" if game.show_stats else "OFF"), func():
			game.show_stats = not game.show_stats
			show_settings(), "gold"],
		["SAVES", func(): show_saves(), "gold"],
		["TESTING", func(): show_testing(), "red"],
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
	buttons.append(["NEW GAME", func():
		_confirm("START OVER?", "Your current game is wiped and you start fresh in Grasslands.\nSave slots are kept.", "START OVER", func(): game.new_game()), "red"])
	buttons.append(["BACK", func(): show_settings(), "gold"])
	show_popup("SAVES", lines, buttons, icon("world", 4))


func show_testing() -> void:
	game.sfx.play("click")
	show_popup("TESTING", "Free stuff for testing the game.\nCoins: %s" % game.fmt(game.coins), [
		["+ COINS", func():
			game.cheat_coins()
			show_testing(), "gold"],
		["+5 UPGRADES", func():
			game.cheat_upgrades()
			show_testing(), "gold"],
		["+%d COSMIC EGGS" % Data.BEDROCK_BOMB_COST, func():
			game.cheat_eggs()
			show_testing(), "gold"],
		["READY TO REBIRTH", func():
			game.rebirth_ready = true
			game.save_game()
			rebuild_tab()
			game.show_rebirth_popup(), "gold"],
		["BACK", func(): show_settings(), "green"],
	], icon("coin", 4))


func _confirm(title: String, body: String, yes: String, action: Callable) -> void:
	show_popup(title, body, [["CANCEL", func(): show_saves(), "gold"], [yes, action, "red"]], icon("world", 4))
