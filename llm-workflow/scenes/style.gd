@tool
class_name MbStyle
extends RefCounted

## The Moveborne visual theme, transcribed from the PixiJS client
## (engine/global.ts + engine/render/tile-display.ts). Dark neon: near-black
## background, a vivid purple accent, black/purple/white tiles with outlined +
## glowing numerals, and the Grammara font throughout.

const FONT_PATH := "res://fonts/Grammara-Normal.woff2"

static var PRIMARY := Color("b400ff")    # GlobalStyle.primary 0xb400ff
static var BG := Color("050507")         # app background #050507
static var BOARD := Color("0c0c12")      # board frame
static var CELL := Color("14141c")       # empty cell
static var GRID := Color("b400ff")       # grid line (drawn faint)
static var HIGHLIGHT := Color("44ff88")  # valid-target highlight 0x44ff88
static var TEXT := Color("ececf4")        # light text on dark
static var DIM := Color("8a7fb0")         # dimmed label
static var MSG_BROWN := Color("776e65")   # hud.ts showMessage fill / countdown stroke
static var MSG_CREAM := Color("faf8ef")   # hud.ts showMessage stroke / countdown fill


## Per-tile-value style (TileValueStyles in tile-display.ts):
## bg / text fill / text outline color / outline width / font size.
static func tile_style(v: int) -> Dictionary:
	match v:
		2:   return {bg = Color.BLACK, fill = Color.BLACK, outline = PRIMARY, ow = 4, fs = 40}
		4:   return {bg = Color.BLACK, fill = PRIMARY, outline = PRIMARY, ow = 0, fs = 40}
		8:   return {bg = Color.BLACK, fill = Color.BLACK, outline = Color.WHITE, ow = 4, fs = 40}
		16:  return {bg = Color.BLACK, fill = Color.WHITE, outline = Color.WHITE, ow = 0, fs = 34}
		32:  return {bg = PRIMARY, fill = Color.BLACK, outline = Color.BLACK, ow = 0, fs = 36}
		64:  return {bg = PRIMARY, fill = Color.BLACK, outline = Color.WHITE, ow = 4, fs = 36}
		128: return {bg = PRIMARY, fill = Color.WHITE, outline = Color.WHITE, ow = 0, fs = 26}
		_:   return {bg = Color.WHITE, fill = Color.BLACK, outline = PRIMARY, ow = 4, fs = 26}  # 256+


## Glow halo color + outline size for a tile value (TileValueStyles glow): none
## below 8, white for mid values, brand purple for 256+. null = no glow.
static func tile_glow(v: int):
	if v < 8:
		return null
	if v < 128:
		return {color = Color.WHITE, size = 8}
	if v < 256:
		return {color = Color.WHITE, size = 12}
	return {color = PRIMARY, size = 16}


## Card art for the hand (engine card type -> hand/images/<type>.png).
static func card_texture(card_type: String) -> Texture2D:
	var path := "res://assets/hand/images/%s.png" % card_type
	if ResourceLoader.exists(path):
		return load(path)
	return null


## Totem icon (totem type uses underscores; files use hyphens).
static func totem_texture(totem_type: String) -> Texture2D:
	var path := "res://assets/totems/%s.png" % totem_type.replace("_", "-")
	if ResourceLoader.exists(path):
		return load(path)
	return null


## Tile-effect overlay sprite, where one exists.
static func effect_texture(effect_type: String) -> Texture2D:
	var path := ""
	match effect_type:
		"black_hole": path = "res://assets/tile-effects/black-hole/overlay.png"
		"freeze": path = "res://assets/tile-effects/freeze/overlay.png"
		"lock": path = "res://assets/tile-effects/lock/overlay.png"
		"stone": path = "res://assets/tile-effects/stone/overlay.png"
		"amplify", "amplify_static": path = "res://assets/tile-effects/amplify/background.png"
	if path != "" and ResourceLoader.exists(path):
		return load(path)
	return null
