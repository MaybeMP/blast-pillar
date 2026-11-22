extends RefCounted
## Hand-drawn (in text) pixel icons and bevelled pixel frames for the UI.
## Icons are little ASCII maps: each character is one pixel, "." is transparent.

const PALETTE := {
	"k": "120e0b", "w": "ffffff", "l": "d8d0c4", "g": "8a8279", "d": "3b3631",
	"y": "ffd84a", "Y": "c08a1a", "o": "ff8a1f", "r": "e8402a", "R": "8f1d14",
	"b": "8a5a33", "G": "5ec43c", "c": "7fe3ff", "C": "2f8fd6", "p": "b46bff", "P": "6a2fb0",
}

## Bombs without their own drawing use the bomb drawing in their own color.
const BOMB_LOOKALIKES := ["mega", "chain", "freeze", "sticky", "magnet", "mirror", "blackhole", "bedrock",
	"spore", "anchor", "overclock", "lightning", "phantom", "supernova"]

## Colour used for "x" pixels when no tint is given.
const DEFAULT_TINT := {
	"bomb": "45403a", "mega": "c0182e", "acid": "6cd43a", "multi": "45403a", "auto": "45403a",
	"cluster": "e07a2a", "gem": "7fe3ff", "world": "3a7fd6",
	"chain": "8a8f99", "freeze": "8fe6ff", "sticky": "6fd24a", "magnet": "d23a3a", "mirror": "2a2a2a",
	"blackhole": "3a1866", "bedrock": "55555a",
	"spore": "b07ad0", "anchor": "4a5a6a", "overclock": "e0b84a", "lightning": "fff04a", "phantom": "c8ffff",
	"supernova": "ffb04a",
}

const ICONS := {
	"coin": [
		"....yyyyyy....",
		"..yyyyyyyyyy..",
		".yyyYYYYYYyyy.",
		".yyYyywwyyYyy.",
		"yyYyywyyyyyYyy",
		"yyYyyyyyyyyYyy",
		"yyYyyyYYyyyYyy",
		"yyYyyyYYyyyYyy",
		"yyYyyyyyyyyYyy",
		"yyYyyyyyyyyYyy",
		".yyYyyyyyyYyy.",
		".yyyYYYYYYyyy.",
		"..yyyyyyyyyy..",
		"....yyyyyy....",
	],
	"bomb": [
		"..........y.o.",
		".........oyy..",
		"........bb.o..",
		".......bb.....",
		".....gggg.....",
		"....xxxxxx....",
		"...xxxxxxxx...",
		"..xxwwxxxxxx..",
		"..xwwxxxxxxx..",
		"..xwxxxxxxxx..",
		"..xxxxxxxxxx..",
		"..xxxxxxxxxx..",
		"...xxxxxxxx...",
		"....xxxxxx....",
	],
	"acid": [
		"..........y.o.",
		".........oyy..",
		"........bb.o..",
		".......bb.....",
		".....gggg.....",
		"....xxxxxx....",
		"...xxhxxxxx...",
		"..xxhhxxxhxx..",
		"..xhxxxxhhxx..",
		"..xxxxxxxxxx..",
		"..xxhxxxxxxx..",
		"..xxxxxxxxxx..",
		"...xx.xx.xx...",
		"....x..x..x...",
	],
	"radius": [
		".....rrrr.....",
		"...rrrrrrrr...",
		"..rrllllllrr..",
		".rllllllllllr.",
		".rllrrrrrrllr.",
		"rrlrrrrrrrrlrr",
		"rrlrrryyrrrlrr",
		"rrlrrryyrrrlrr",
		"rrlrrrrrrrrlrr",
		".rllrrrrrrllr.",
		".rllllllllllr.",
		"..rrllllllrr..",
		"...rrrrrrrr...",
		".....rrrr.....",
	],
	"power": [
		".......yyyyy..",
		"......yyyyy...",
		".....yyyyy....",
		"....yyyyy.....",
		"...yyyyy......",
		"..yyyyyyyyyy..",
		".yyyyyyyyyy...",
		"......yyyy....",
		".....yyyy.....",
		"....yyyy......",
		"...yyy........",
		"..yyy.........",
		"..yy..........",
		"..y...........",
	],
	"multi": [
		".....o........",
		".....b........",
		"....gg........",
		"...xxxx.......",
		"..xwxxxx......",
		"..xxxxxx......",
		"...xxxx...o...",
		"..o.......b...",
		"..b......gg...",
		".gg.....xxxx..",
		"xxxx...xwxxxx.",
		"wxxxx..xxxxxx.",
		"xxxxx...xxxx..",
		".xxx..........",
	],
	"fuse": [
		".gggggggggggg.",
		".gggggggggggg.",
		"..lyyyyyyyyl..",
		"...lyyyyyyl...",
		"....lyyyyl....",
		".....lyyl.....",
		"......ll......",
		"......ll......",
		".....lyll.....",
		"....llyyll....",
		"...llyyyyll...",
		"..lyyyyyyyyl..",
		".gggggggggggg.",
		".gggggggggggg.",
	],
	"value": [
		"..........G...",
		".........GGG..",
		"........GGGGG.",
		"..........G...",
		"..........G...",
		".YyyyyyyY.....",
		".yyyyyyyy.....",
		".YYYYYYYY.....",
		".yyywyyyy.....",
		".YYYYYYYY.....",
		".yyyyyyyy.....",
		".YYYYYYYY.....",
		".yyyyyyyy.....",
		".YYYYYYYY.....",
	],
	"gem": [
		"..............",
		"....hhhhhh....",
		"...hhhxxxxx...",
		"..hhxxxxxxxX..",
		".hhhhhxxxXXXX.",
		"xxxxxxxxxxxxxx",
		".xxxxxxxxxxXX.",
		"..xxxxxxxxXX..",
		"...xxxxxxXX...",
		"....xxxxXX....",
		".....xxXX.....",
		"......xX......",
		"..............",
		"..............",
	],
	"auto": [
		".gggggggggggg.",
		".gllllllllllg.",
		".glrrlllyylg..",
		".gllllllllllg.",
		".gggggggggggg.",
		"....gddddg....",
		".....gddg.....",
		"..............",
		"......o.......",
		"......b.......",
		".....xxxx.....",
		"....xwxxxx....",
		"....xxxxxx....",
		".....xxxx.....",
	],
	"drill": [
		"...oooooooo...",
		"...oyyyyyyo...",
		"...oooooooo...",
		"....llllll....",
		"....gggggg....",
		"....llllll....",
		".....gggg.....",
		".....llll.....",
		"......gg......",
		"......ll......",
		"......gg......",
		"......l.......",
		"..............",
		"..............",
	],
	"cluster": [
		"......y.......",
		".....bo.......",
		".....gg.......",
		"....xxxx......",
		"...xwxxxx.....",
		"...xxxxxx.....",
		"....xxxx......",
		"..............",
		"ddd..ddd..ddd.",
		"dwd..dwd..dwd.",
		"ddd..ddd..ddd.",
		"..............",
		"..............",
		"..............",
	],
	"lock": [
		"....gggggg....",
		"...gg....gg...",
		"...g......g...",
		"...g......g...",
		"..yyyyyyyyyy..",
		"..ywyyyyyyyy..",
		"..yyyyddyyyy..",
		"..yyyyddyyyy..",
		"..yyyyyddyyy..",
		"..yyyyyddyyy..",
		"..yyyyyyyyyy..",
		"..YYYYYYYYYY..",
		"..............",
		"..............",
	],
	"world": [
		"....xxxxxx....",
		"..xxxxGGxxxx..",
		".xxxGGGGxxxxx.",
		".xxGGGGxxxGGx.",
		"xxxxGGxxxGGGxx",
		"xxxxxxxxxxGGxx",
		"xxGGxxxxxxxxxx",
		"xGGGGxxxxxxxxx",
		"xxGGGGxxxGGxxx",
		"xxxGGxxxGGGGxx",
		".xxxxxxxxGGxx.",
		".xxxxxxxxxxxx.",
		"..xxxxxxxxxx..",
		"....xxxxxx....",
	],
	"gear": [
		".....llll.....",
		"..ll.llll.ll..",
		".llllllllllll.",
		"..llllllllll..",
		"..lll....lll..",
		"llll......llll",
		"llll......llll",
		"llll......llll",
		"llll......llll",
		"..lll....lll..",
		"..llllllllll..",
		".llllllllllll.",
		"..ll.llll.ll..",
		".....llll.....",
	],
}


## Build an icon texture (16x16 before scaling). The drawing gets automatic pixel-art shading:
## lit top-left edges, shaded bottom-right edges, and a dark 1px outline.
## tint replaces x (main colour), h (light) and X (dark).
static func icon(name: String, scale := 3, tint := Color(-1, 0, 0)) -> ImageTexture:
	var rows: Array = ICONS.get("bomb" if name in BOMB_LOOKALIKES else name, ICONS["gem"])
	if tint.r < 0.0 and DEFAULT_TINT.has(name):
		tint = Color.html(DEFAULT_TINT[name])
	var n := 16
	var base := Image.create(n, n, false, Image.FORMAT_RGBA8)
	base.fill(Color(0, 0, 0, 0))
	var t := tint if tint.r >= 0.0 else Color("7fe3ff")
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			var ch := row[x]
			var c := Color(0, 0, 0, 0)
			if ch == "x":
				c = t
			elif ch == "h":
				c = t.lightened(0.4)
			elif ch == "X":
				c = t.darkened(0.3)
			elif PALETTE.has(ch):
				c = Color.html(PALETTE[ch])
			base.set_pixel(x + 1, y + 1, c)
	var out := Image.create(n, n, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	var outline := Color("120e0b")
	for y in n:
		for x in n:
			var c := base.get_pixel(x, y)
			if c.a > 0.0:
				var up := y == 0 or base.get_pixel(x, y - 1).a == 0.0
				var left := x == 0 or base.get_pixel(x - 1, y).a == 0.0
				var down := y == n - 1 or base.get_pixel(x, y + 1).a == 0.0
				var right := x == n - 1 or base.get_pixel(x + 1, y).a == 0.0
				if up or left:
					c = c.lightened(0.2)
				elif down or right:
					c = c.darkened(0.25)
				out.set_pixel(x, y, c)
			else:
				for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var q: Vector2i = Vector2i(x, y) + o
					if q.x >= 0 and q.y >= 0 and q.x < n and q.y < n and base.get_pixel(q.x, q.y).a > 0.0:
						out.set_pixel(x, y, outline)
						break
	out.resize(n * scale, n * scale, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(out)


## A chunky bevelled frame: dark outline with clipped corners, light top-left edge,
## dark bottom-right edge. inset=true flips the bevel (pressed buttons, item slots).
static func frame(fill: Color, light: Color, dark: Color, scale := 3, inset := false,
		content := Vector4(12, 10, 12, 10), outline := Color("120e0b")) -> StyleBoxTexture:
	var n := 7
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var hi := dark if inset else light
	var lo := light if inset else dark
	for y in n:
		for x in n:
			var c := fill
			var edge_x := x == 0 or x == n - 1
			var edge_y := y == 0 or y == n - 1
			if edge_x and edge_y:
				c = Color(0, 0, 0, 0)          # clipped corner
			elif edge_x or edge_y:
				c = outline
			elif y == 1 or x == 1:
				c = hi
			elif y == n - 2 or x == n - 2:
				c = lo
			img.set_pixel(x, y, c)
	# fix the two mixed bevel corners
	img.set_pixel(n - 2, 1, fill)
	img.set_pixel(1, n - 2, fill)
	img.resize(n * scale, n * scale, Image.INTERPOLATE_NEAREST)
	var sb := StyleBoxTexture.new()
	sb.texture = ImageTexture.create_from_image(img)
	var m := 3 * scale
	sb.texture_margin_left = m
	sb.texture_margin_top = m
	sb.texture_margin_right = m
	sb.texture_margin_bottom = m
	sb.content_margin_left = content.x
	sb.content_margin_top = content.y
	sb.content_margin_right = content.z
	sb.content_margin_bottom = content.w
	return sb
