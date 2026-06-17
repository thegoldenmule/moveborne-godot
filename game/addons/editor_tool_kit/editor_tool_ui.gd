@tool
class_name EditorToolUi
extends RefCounted

## Static layout builders for the small set of UI idioms the authoring docks both
## rebuild by hand: the split root, label-over-control and label-beside-control
## rows, a one-line wrapping status label, and the violet/green selection
## restyle. Pure construction — no state, no signals. Docks adopt these
## incrementally; the output is visually identical to the inline code.


## A full-rect HSplitContainer (canvas/content on the left, controls on the
## right). When min_left / min_right are > 0, two VBoxContainer panes are created
## with those width floors and added (so the divider can't collapse a pane past
## its content) — grab them with get_child(0) / get_child(1). Pass 0 for a pane
## to add a custom child (e.g. a ScrollContainer) yourself.
static func split_root(min_left: float = 0.0, min_right: float = 0.0) -> HSplitContainer:
	var root := HSplitContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	if min_left > 0.0:
		var left := VBoxContainer.new()
		left.custom_minimum_size = Vector2(min_left, 0)
		left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		left.size_flags_vertical = Control.SIZE_EXPAND_FILL
		root.add_child(left)
	if min_right > 0.0:
		var right := VBoxContainer.new()
		right.custom_minimum_size = Vector2(min_right, 0)
		right.size_flags_vertical = Control.SIZE_EXPAND_FILL
		root.add_child(right)
	return root


## The enforced tool header: the tool title on the left, then a dimmed version
## tag and a reload button pinned to the right — framed by a violet bottom rule
## so it reads as a header band, not a loose button row. `on_reload` is wired to
## the button (the plugin's disable→enable self-reload). Pure construction —
## EditorToolPlugin mounts this above every dock, so no tool builds its own.
static func tool_header(title: String, version := "", on_reload := Callable()) -> PanelContainer:
	var frame := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)        # no fill — just the rule beneath the row
	sb.border_color = Color("b400ff")      # violet, matching the occult-arcade direction
	sb.border_width_bottom = 2
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 2
	sb.content_margin_bottom = 6
	frame.add_theme_stylebox_override("panel", sb)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	frame.add_child(bar)

	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 20)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(t)
	if version != "":
		var v := Label.new()
		v.text = "v" + version
		v.add_theme_color_override("font_color", Color(0.55, 0.5, 0.6))
		v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.add_child(v)
	bar.add_child(button("⟳ Reload", on_reload,
		"Disable and re-enable this plugin to reload its scripts"))
	return frame


## A VBox of a caption label above a control. The control always fills
## horizontally; pass fill_v := true to also let it expand vertically (a
## TextEdit/canvas that should consume the leftover height) — leave it false for
## the common single-line labeled field, so a column of them doesn't stretch.
static func label_wrap(text: String, control: Control, fill_v := false) -> VBoxContainer:
	var box := VBoxContainer.new()
	var lbl := Label.new()
	lbl.text = text
	box.add_child(lbl)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if fill_v:
		control.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(control)
	return box


## An HBox row: a fixed-width label beside an expanding control (the catalog
## form's row idiom).
static func form_row(label_text: String, control: Control, label_w: float = 78.0) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size = Vector2(label_w, 0)
	row.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


## A Button with text, an optional pressed handler, and an optional tooltip — the
## make → set text → connect idiom both docks repeat. Pass an invalid Callable
## (the default) to skip wiring a handler.
static func button(text: String, on_press := Callable(), tooltip := "") -> Button:
	var b := Button.new()
	b.text = text
	if tooltip != "":
		b.tooltip_text = tooltip
	if on_press.is_valid():
		b.pressed.connect(on_press)
	return b


## An HBox packing the given controls (typically a row of buttons) left-to-right.
## Non-Control entries are skipped.
static func button_bar(items: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	for item in items:
		if item is Control:
			row.add_child(item)
	return row


## A step-1 (by default) SpinBox preset with its range and value — the spin
## factory both the catalog form and the goal/reward grids repeat. `fill` makes
## it expand to fill its row (the grids); leave it false for a fixed-width spin
## beside a form_row label.
static func spin(minv: float, maxv: float, value: float, step := 1.0, fill := false) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = minv
	s.max_value = maxv
	s.step = step
	s.value = value
	if fill:
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return s


## A word-wrapping status Label with a minimum width (so long messages wrap
## instead of stretching the panel).
static func status_label(min_w: float = 360.0) -> Label:
	var lbl := Label.new()
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size = Vector2(min_w, 0)
	return lbl


## Apply the shared selection restyle to a Panel: a dark fill with a violet
## border (unselected) or a thicker green border (selected), matching Story Map's
## dot styling. `radius` rounds the corners (default suits a 32px dot).
static func restyle_selected(panel: Panel, selected: bool, radius: int = 16) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.07, 0.1, 0.92)
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(3 if selected else 2)
	sb.border_color = Color("44ff88") if selected else Color("b400ff")
	panel.add_theme_stylebox_override("panel", sb)
