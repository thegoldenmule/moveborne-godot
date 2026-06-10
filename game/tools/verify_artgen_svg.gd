extends SceneTree

## Headless ThorVG + background-strip verifier for ArtGen (M0 exit evidence):
##   godot --headless --path . --script res://tools/verify_artgen_svg.gd
## Runs against the committed Recraft outputs in ../art/generated/2026-06 —
## fixed vectors, same idea as the golden parity files.

const GEN_DIR := "res://../art/generated/2026-06"
const BLACK_BG_SVG := "g_1781100497_05ce-iconstyle-settings-0.svg"
const VIOLET_BG_SVG := "g_1781100332_8a75-vec-custom-bare-glyph-0.svg"


func _initialize() -> void:
	var ok := true
	var base := ProjectSettings.globalize_path(GEN_DIR)
	var svg_tools := load("res://addons/artgen/svg_tools.gd")

	# 1) Black-background icon strips clean.
	var text := FileAccess.get_file_as_string(base.path_join(BLACK_BG_SVG))
	var res: Dictionary = svg_tools.strip_background(text, Color.BLACK)
	if res["status"] != svg_tools.STATUS_STRIPPED:
		print("FAIL strip: expected stripped, got %s" % res["status"])
		ok = false

	# 2) ThorVG rasterizes the stripped SVG with real transparency.
	var img := Image.new()
	if img.load_svg_from_string(res["text"]) != OK:
		print("FAIL thorvg: stripped SVG did not rasterize")
		ok = false
	else:
		if img.get_width() <= 0 or img.get_height() <= 0:
			print("FAIL thorvg: empty image")
			ok = false
		var corner := img.get_pixel(0, 0)
		if corner.a > 0.001:
			print("FAIL transparency: corner alpha %f after strip" % corner.a)
			ok = false
		if not _has_violet(img):
			print("FAIL palette: no violet pixels in rasterized icon")
			ok = false

	# 3) Unstripped original rasterizes opaque black at the corner.
	var img_orig := Image.new()
	if img_orig.load_svg_from_string(text) != OK:
		print("FAIL thorvg: original SVG did not rasterize")
		ok = false
	elif img_orig.get_pixel(0, 0).a < 0.999:
		print("FAIL baseline: original corner should be opaque")
		ok = false

	# 4) Non-black canvas polygon is refused, not stripped.
	var violet := FileAccess.get_file_as_string(base.path_join(VIOLET_BG_SVG))
	var res_v: Dictionary = svg_tools.strip_background(violet, Color.BLACK)
	if res_v["status"] != svg_tools.STATUS_FILL_MISMATCH:
		print("FAIL mismatch guard: expected fill mismatch, got %s" % res_v["status"])
		ok = false

	# 5) Every committed generation parses under ThorVG.
	var dir := DirAccess.open(base)
	var parsed := 0
	if dir == null:
		print("FAIL: cannot open %s" % base)
		ok = false
	else:
		for f in dir.get_files():
			if not f.ends_with(".svg"):
				continue
			var i := Image.new()
			if i.load_svg_from_string(FileAccess.get_file_as_string(base.path_join(f))) != OK:
				print("FAIL thorvg: %s did not parse" % f)
				ok = false
			else:
				parsed += 1

	print("VERIFY artgen_svg: %s (%d SVGs parsed)" % ["PASS" if ok else "FAIL", parsed])
	quit(0 if ok else 1)


func _has_violet(img: Image) -> bool:
	for y in range(0, img.get_height(), 32):
		for x in range(0, img.get_width(), 32):
			var c := img.get_pixel(x, y)
			if c.a > 0.5 and c.r > 0.4 and c.b > 0.8 and c.g < 0.3:
				return true
	return false
