class_name MbRewardCeremony
extends RefCounted

## Shared claim-reward ceremony, used by both the Daily Missions sigil and the
## Daily Login bonus screen: reveal WHAT was won (a popped reward card showing each
## currency's icon + amount), hold a beat, THEN burst coin "doobers" from the card
## into the matching currency-bar slots — the wallet counts up + pulses only when
## they land. Falls back to an instant credit when there's no currency bar
## (headless / standalone).
##
## run(host, currency_bar, granted) — host is a Node already in the tree that can
## parent a temporary CanvasLayer for the ~1.5s animation; currency_bar is optional
## (an MbCurrencyBar exposing slot_global_pos / pulse_slot); granted is the
## {coins/souls/gems} delta. Coroutine — await it. Pure presentation; the wallet
## credit goes through GameState.add_currencies exactly once, as the doobers land.

const CurrencyBarS := preload("res://ui/shell/currency_bar.gd")


static func run(host: Node, currency_bar: Node, granted: Dictionary) -> void:
	if not is_instance_valid(currency_bar) or not currency_bar.has_method("slot_global_pos"):
		GameState.add_currencies(granted)
		return

	var fx := CanvasLayer.new()
	fx.layer = 31   # above the modal panel (20)
	host.add_child(fx)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var th := Theme.new()
	th.default_font = load(MbStyle.FONT_PATH)
	root.theme = th
	fx.add_child(root)

	# Dim to focus the reveal + swallow taps during the beat.
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)
	dim.create_tween().tween_property(dim, "color", Color(0, 0, 0, 0.45), 0.2)

	# The reveal card: "REWARD" + a row per granted currency (icon + +N).
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = MbStyle.BOARD
	sb.border_color = MbStyle.PRIMARY
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(24)
	card.add_theme_stylebox_override("panel", sb)
	center.add_child(card)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 12)
	card.add_child(col)
	var title := Label.new()
	title.text = "REWARD"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", MbStyle.PRIMARY)
	col.add_child(title)
	for slot in CurrencyBarS.SLOTS:
		var nm := str(slot["name"])
		if int(granted.get(nm, 0)) == 0:
			continue
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 12)
		var glyph := Label.new()
		glyph.text = str(slot["glyph"])
		glyph.add_theme_font_size_override("font_size", 44)
		glyph.add_theme_color_override("font_color", slot["color"])
		row.add_child(glyph)
		var amt := Label.new()
		amt.text = "+%d" % int(granted[nm])
		amt.add_theme_font_size_override("font_size", 36)
		amt.add_theme_color_override("font_color", MbStyle.TEXT)
		amt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(amt)
		col.add_child(row)

	# Pop the card in.
	card.modulate.a = 0.0
	await host.get_tree().process_frame   # let the card lay out so pivot + center are real
	card.pivot_offset = card.size / 2.0
	card.scale = Vector2(0.6, 0.6)
	var tin := card.create_tween()
	tin.set_parallel(true)
	tin.tween_property(card, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tin.tween_property(card, "modulate:a", 1.0, 0.18)
	await tin.finished
	await host.get_tree().create_timer(0.7).timeout

	# Burst the doobers from the card into each currency slot.
	var origin := card.get_global_rect().get_center()
	var land := 0.0
	for slot in CurrencyBarS.SLOTS:
		var nm := str(slot["name"])
		var amount := int(granted.get(nm, 0))
		if amount == 0:
			continue
		var target: Vector2 = currency_bar.slot_global_pos(nm)
		var k := clampi(int(amount / 15.0), 6, 14)
		for i in range(k):
			var d := Label.new()
			d.text = str(slot["glyph"])
			d.add_theme_font_size_override("font_size", 22)
			d.add_theme_color_override("font_color", slot["color"])
			d.position = origin
			d.mouse_filter = Control.MOUSE_FILTER_IGNORE
			root.add_child(d)
			var burst := origin + Vector2(randf_range(-70.0, 70.0), randf_range(-60.0, 10.0))
			var delay := i * 0.04
			var tw := d.create_tween()
			tw.tween_interval(delay)
			tw.tween_property(d, "position", burst, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_property(d, "position", target, 0.36).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.tween_callback(d.queue_free)
			land = maxf(land, delay + 0.52)

	# Credit the wallet (count-up) + pulse as the doobers land.
	await host.get_tree().create_timer(maxf(land - 0.12, 0.1)).timeout
	GameState.add_currencies(granted)
	for slot in CurrencyBarS.SLOTS:
		if int(granted.get(str(slot["name"]), 0)) != 0 and currency_bar.has_method("pulse_slot"):
			currency_bar.pulse_slot(str(slot["name"]))

	# Fade the card + dim out, then free the ceremony layer.
	await host.get_tree().create_timer(0.2).timeout
	var tout := card.create_tween()
	tout.set_parallel(true)
	tout.tween_property(card, "modulate:a", 0.0, 0.22)
	tout.tween_property(card, "scale", Vector2(0.92, 0.92), 0.22)
	dim.create_tween().tween_property(dim, "color", Color(0, 0, 0, 0), 0.22)
	await tout.finished
	fx.queue_free()
