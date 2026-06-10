class_name ArtgenSvg
extends RefCounted

## Pure static SVG helpers for ArtGen (no editor/scene deps).
##
## Recraft vector outputs carry a full-canvas background polygon as their first
## <path> (sometimes with extra collinear vertices along the edges). Stripping
## it yields a transparent asset. The polygon is only removed when its fill
## matches the requested background color — a non-matching fill means the
## composition uses the "background" as ink (e.g. black glyph on violet), so
## stripping would destroy the artwork; callers get a status to surface instead.

const STATUS_STRIPPED := "stripped"
const STATUS_NO_PATH := "no_path"
const STATUS_NOT_BACKGROUND := "no_background"
const STATUS_FILL_MISMATCH := "background_fill_mismatch"


## Returns {"text": String, "status": String, "fill": Color (only on mismatch)}.
static func strip_background(svg_text: String, bg: Color = Color.BLACK) -> Dictionary:
	var vb := RegEx.create_from_string("viewBox=\"0 0 ([\\d.]+) ([\\d.]+)\"").search(svg_text)
	if vb == null:
		return {"text": svg_text, "status": STATUS_NO_PATH}
	var w := vb.get_string(1).to_float()
	var h := vb.get_string(2).to_float()

	var path_re := RegEx.create_from_string(
		"<path d=\"([^\"]+)\" fill=\"rgb\\((\\d+),(\\d+),(\\d+)\\)\"([^>]*)></path>")
	var m := path_re.search(svg_text)
	if m == null:
		return {"text": svg_text, "status": STATUS_NO_PATH}

	var tail := m.get_string(5)
	if tail.contains("transform=") and not tail.contains("translate(0,0)"):
		return {"text": svg_text, "status": STATUS_NOT_BACKGROUND}
	if not _is_canvas_polygon(m.get_string(1), w, h):
		return {"text": svg_text, "status": STATUS_NOT_BACKGROUND}

	var fill := Color8(
		int(m.get_string(2)), int(m.get_string(3)), int(m.get_string(4)))
	if fill.to_rgba32() != bg.to_rgba32():
		return {"text": svg_text, "status": STATUS_FILL_MISMATCH, "fill": fill}

	var stripped := svg_text.substr(0, m.get_start()) + svg_text.substr(m.get_end())
	return {"text": stripped, "status": STATUS_STRIPPED}


## A canvas background is a closed polygon of straight segments whose vertices
## all lie on the viewBox border and that touches all four corners.
static func _is_canvas_polygon(d: String, w: float, h: float) -> bool:
	if RegEx.create_from_string("^M[ \\d.,Lz]+$").search(d) == null:
		return false
	var corners := {
		Vector2(0, 0): false, Vector2(w, 0): false,
		Vector2(w, h): false, Vector2(0, h): false,
	}
	for pm in RegEx.create_from_string("([\\d.]+)[ ,]([\\d.]+)").search_all(d):
		var p := Vector2(pm.get_string(1).to_float(), pm.get_string(2).to_float())
		var on_border := (
			is_zero_approx(p.x) or is_equal_approx(p.x, w)
			or is_zero_approx(p.y) or is_equal_approx(p.y, h))
		if not on_border:
			return false
		if corners.has(p):
			corners[p] = true
	for c in corners:
		if not corners[c]:
			return false
	return true
