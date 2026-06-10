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

const STATUS_TRIMMED := "trimmed"
const STATUS_EMPTY := "empty"
const STATUS_NO_VIEWBOX := "no_viewbox"
const STATUS_RASTER_FAILED := "raster_failed"


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


## Photoshop-style "Trim": crop the viewBox to the smallest rect containing
## visible content. Rasterizes through ThorVG and takes the opaque bounding rect
## (Image.get_used_rect), so it handles any path data without parsing it; the
## rect maps back to viewBox units with one raster pixel of slack per side for
## anti-aliased edges. ``margin_frac`` adds that fraction of the cropped long
## edge as padding on every side (clamped to the original viewBox). The
## width/height attributes are rescaled so imported pixel density is unchanged.
## Returns {"text": String, "status": String, "rect": Rect2 (trimmed viewBox)}.
static func trim_to_content(svg_text: String, margin_frac := 0.0, raster_px := 512) -> Dictionary:
	var vb_re := RegEx.create_from_string(
		"viewBox=\"([-\\d.]+)[ ,]+([-\\d.]+)[ ,]+([\\d.]+)[ ,]+([\\d.]+)\"")
	var vb_m := vb_re.search(svg_text)
	if vb_m == null:
		return {"text": svg_text, "status": STATUS_NO_VIEWBOX}
	var vb := Rect2(
		vb_m.get_string(1).to_float(), vb_m.get_string(2).to_float(),
		vb_m.get_string(3).to_float(), vb_m.get_string(4).to_float())
	if vb.size.x <= 0.0 or vb.size.y <= 0.0:
		return {"text": svg_text, "status": STATUS_NO_VIEWBOX}

	# ThorVG sizes the raster from the width/height attributes (falling back to
	# the viewBox); scale so the long edge lands near raster_px.
	var w_re := RegEx.create_from_string("\\swidth=\"([\\d.]+)\"")
	var h_re := RegEx.create_from_string("\\sheight=\"([\\d.]+)\"")
	var w_m := w_re.search(svg_text)
	var h_m := h_re.search(svg_text)
	var w_attr := w_m.get_string(1).to_float() if w_m != null else vb.size.x
	var h_attr := h_m.get_string(1).to_float() if h_m != null else vb.size.y
	var img := Image.new()
	if img.load_svg_from_string(svg_text, raster_px / maxf(w_attr, h_attr)) != OK:
		return {"text": svg_text, "status": STATUS_RASTER_FAILED}

	var used := img.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return {"text": svg_text, "status": STATUS_EMPTY}
	used = used.grow(1)  # cover anti-aliased edges cut at raster resolution

	var unit := Vector2(vb.size.x / img.get_width(), vb.size.y / img.get_height())
	var content := Rect2(
		vb.position + Vector2(used.position) * unit, Vector2(used.size) * unit)
	content = content.grow(margin_frac * maxf(content.size.x, content.size.y))
	content = content.intersection(vb)

	var out := svg_text.replace(vb_m.get_string(0), "viewBox=\"%s %s %s %s\"" % [
		String.num(content.position.x, 2), String.num(content.position.y, 2),
		String.num(content.size.x, 2), String.num(content.size.y, 2)])
	if w_m != null:
		out = out.replace(w_m.get_string(0), " width=\"%s\"" % String.num(
			w_attr * content.size.x / vb.size.x, 2))
	if h_m != null:
		out = out.replace(h_m.get_string(0), " height=\"%s\"" % String.num(
			h_attr * content.size.y / vb.size.y, 2))
	return {"text": out, "status": STATUS_TRIMMED, "rect": content}


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
