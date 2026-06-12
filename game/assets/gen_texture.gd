@tool
class_name GenTexture
extends Texture2D

## An AI-generated art *reference*: a stable indirection layer between a scene
## slot and the raw pixels it currently resolves to.
##
## Saved as one `.tres` per logical art slot (e.g. icons/collections.tres). The
## resource has its own `uid://`, so consumers bind to *it* — renaming or moving
## the `.tres` keeps every reference alive, and Godot rewrites uid refs in
## .tscn/.tres automatically. Provenance (which generation produced it, the
## prompt, the post steps, the content hash) lives **inside** the resource, so a
## rename can never orphan it the way a path-keyed manifest does.
##
## `source` points at the baked pixels in the shared pool
## (res://assets/generated/_pool/<gen_id>.<ext>), referenced by uid. Swapping to
## a different permutation just re-points `source` + the provenance fields and
## re-saves the same `.tres` — the uid is unchanged, so every consumer follows
## the swap with zero edits. See addons/artgen/artgen_service.gd
## (save_generation / swap_permutation).
##
## GenTexture is itself a Texture2D: it proxies all canvas draws to `source`, so
## it drops straight into any `texture` slot (Sprite2D, TextureRect, Button
## icon, …). (Caveat: direct shader `sampler2D` binding samples via get_rid(),
## which a script texture can't supply — assign `source` for that rare case.)

## The baked pixels this ref currently resolves to (a pooled, post-processed
## PNG/SVG, referenced by uid).
@export var source: Texture2D:
	set(value):
		source = value
		emit_changed()

# -- Provenance (embedded — survives any rename/move) --------------------------
@export var gen_id: String          ## generation id (g_…) currently resolved
@export var batch_id: String        ## its batch — the set of sibling permutations
@export var prompt: String
@export var generator: String       ## e.g. "recraft/recraftv4_1"
@export var style_id: String
@export var sha256: String          ## content hash of the baked pool file
@export var saved_at: String        ## ISO-8601, last save/swap
@export var post: PackedStringArray ## post steps applied to the pool file


# -- Texture2D proxy ----------------------------------------------------------

func _get_width() -> int:
	return source.get_width() if source != null else 1


func _get_height() -> int:
	return source.get_height() if source != null else 1


func _has_alpha() -> bool:
	return source.has_alpha() if source != null else true


func _draw(to_canvas_item: RID, pos: Vector2, modulate: Color, transpose: bool) -> void:
	if source != null:
		source.draw(to_canvas_item, pos, modulate, transpose)


func _draw_rect(to_canvas_item: RID, rect: Rect2, tile: bool, modulate: Color, transpose: bool) -> void:
	if source != null:
		source.draw_rect(to_canvas_item, rect, tile, modulate, transpose)


func _draw_rect_region(to_canvas_item: RID, rect: Rect2, src_rect: Rect2,
		modulate: Color, transpose: bool, clip_uv: bool) -> void:
	if source != null:
		source.draw_rect_region(to_canvas_item, rect, src_rect, modulate, transpose, clip_uv)
