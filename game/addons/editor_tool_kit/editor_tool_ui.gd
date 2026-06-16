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


## A VBox of a caption label above an expanding control.
static func label_wrap(text: String, control: Control) -> VBoxContainer:
	var box := VBoxContainer.new()
	var lbl := Label.new()
	lbl.text = text
	box.add_child(lbl)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
