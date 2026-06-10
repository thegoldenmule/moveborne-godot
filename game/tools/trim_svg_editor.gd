@tool
extends EditorScript

## Photoshop-style "Trim" for SVG assets, run in-editor:
##   1. Select .svg files (or folders of them) in the FileSystem dock.
##   2. Open this script and run it (File > Run, Cmd/Ctrl+Shift+X).
## Each SVG's viewBox is cropped to the smallest rect containing visible
## content via ArtgenSvg.trim_to_content, written back in place, and
## reimported. Already-trimmed files report a near-identical rect and are
## rewritten harmlessly (idempotent).

const SvgTools := preload("res://addons/artgen/svg_tools.gd")

## Padding around the content, as a fraction of the cropped long edge.
const MARGIN_FRAC := 0.0


func _run() -> void:
	var svgs: Array[String] = []
	for p in EditorInterface.get_selected_paths():
		if p.ends_with(".svg"):
			svgs.append(p)
		elif DirAccess.dir_exists_absolute(p):
			_collect_svgs(p.trim_suffix("/"), svgs)
	if svgs.is_empty():
		print("trim_svg: select .svg files or folders in the FileSystem dock first")
		return

	var fs := EditorInterface.get_resource_filesystem()
	for p in svgs:
		var res: Dictionary = SvgTools.trim_to_content(
			FileAccess.get_file_as_string(p), MARGIN_FRAC)
		if res["status"] != SvgTools.STATUS_TRIMMED:
			print("trim_svg: SKIP %s (%s)" % [p, res["status"]])
			continue
		var f := FileAccess.open(p, FileAccess.WRITE)
		f.store_string(res["text"])
		f.close()
		fs.update_file(p)
		print("trim_svg: %s -> viewBox %s" % [p, res["rect"]])


func _collect_svgs(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for f in dir.get_files():
		if f.ends_with(".svg"):
			out.append(dir_path.path_join(f))
	for d in dir.get_directories():
		_collect_svgs(dir_path.path_join(d), out)
