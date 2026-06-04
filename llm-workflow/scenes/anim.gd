extends Node

## Anim — central presentation animation helper (autoload). The home for shared
## tween-based juice (floating text now; combo pop, the ex-RAF countdown/banner/
## tooltip/selection-pulse loops later — see VFX_MAPPING.md §2.7 / §4 / §5.6).
## Presentation-only; never touches engine state. Durations are in SECONDS.


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
