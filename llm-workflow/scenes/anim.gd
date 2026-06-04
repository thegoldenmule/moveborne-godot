extends Node

## Anim — central presentation animation helper (autoload). The home for shared
## tween-based juice (floating text now; combo pop, the ex-RAF countdown/banner/
## tooltip/selection-pulse loops later — see VFX_MAPPING.md §2.7 / §4 / §5.6).
## Presentation-only; never touches engine state. Durations are in SECONDS.

const Style := preload("res://scenes/style.gd")


## Spawn a rising, fading "+score"-style Label at `pos` (in `parent`'s space) and
## free it when done. Mirrors fx.ts createFloatingText: rise `distance` cubicOut
## over `duration`, fade linearly over the second half. `parent` is typically a
## screen-space CanvasLayer so floats are shake-immune.
func float_text(parent: Node, pos: Vector2, text: String, color: Color,
		font_size: int = 24, duration: float = 1.0, distance: float = 50.0) -> Label:
	var l := Label.new()
	l.text = text
	var ls := LabelSettings.new()
	ls.font_size = font_size
	ls.font_color = color
	ls.outline_size = 4          # Pixi stroke width 4
	ls.outline_color = Color.BLACK
	l.label_settings = ls
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)

	# Center on pos (Pixi anchor 0.5); Label reports its content size synchronously.
	var sz := l.get_minimum_size()
	l.size = sz
	l.pivot_offset = sz / 2.0
	l.position = pos - sz / 2.0

	var tw := l.create_tween().set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - distance, duration) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, duration / 2.0) \
		.set_delay(duration / 2.0).set_trans(Tween.TRANS_LINEAR)
	tw.chain().tween_callback(l.queue_free)
	return l


## Elastic scale punch then settle, scaling around the node's center. Used for the
## HUD combo pop (hud.ts triggerComboAnimation: 1->1.6 elasticOut, then ->1 cubicOut).
func pop(node: Control, peak := 1.6, up := 0.3, down := 0.5) -> void:
	if node == null or not is_instance_valid(node):
		return
	node.pivot_offset = node.size / 2.0
	node.scale = Vector2.ONE
	var tw := node.create_tween()
	tw.tween_property(node, "scale", Vector2(peak, peak), up) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "scale", Vector2.ONE, down) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Centered screen message that fades in, holds, then fades out (hud.ts showMessage):
## Grammara bold, brown fill / cream outline. `parent` is a screen-space CanvasLayer.
func banner(parent: Node, text: String, duration := 2.0, font_size := 48) -> Label:
	var vp := get_viewport().get_visible_rect().size
	var l := Label.new()
	l.text = text
	l.size = vp
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ls := LabelSettings.new()
	ls.font = load(Style.FONT_PATH)
	ls.font_size = font_size
	ls.font_color = Style.MSG_BROWN
	ls.outline_size = 4
	ls.outline_color = Style.MSG_CREAM
	l.label_settings = ls
	l.modulate.a = 0.0
	parent.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "modulate:a", 1.0, 0.3)
	tw.tween_interval(maxf(0.0, duration - 0.7))
	tw.tween_property(l, "modulate:a", 0.0, 0.4)
	tw.tween_callback(l.queue_free)
	return l
