extends Control
## A stub tab screen: a single centered label. Used for Collection / Leaderboard /
## Guilds / Settings until they get real content.

@onready var _label: Label = $Label
var _pending_title := "Coming Soon"


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 30)
	_label.add_theme_color_override("font_color", MbStyle.DIM)
	_label.text = _pending_title


func set_title(t: String) -> void:
	_pending_title = "%s\n(coming soon)" % t
	if _label != null:
		_label.text = _pending_title
