extends Control
## The Home tab: a central hero + three play-mode launchers (Story / Infinite / PvP).
## Emits play_mode_selected(cfg) for the shell to start a match. PvP is gated.

signal play_mode_selected(cfg: Dictionary)

@onready var _center: CenterContainer = $Center
@onready var _vbox: VBoxContainer = $Center/VBox
@onready var _hero: Label = $Center/VBox/Hero
@onready var _story: Button = $Center/VBox/Story
@onready var _infinite: Button = $Center/VBox/Infinite
@onready var _pvp: Button = $Center/VBox/PvP


func _ready() -> void:
	# Root size comes from the shell (screen.size = viewport); the CenterContainer
	# fills the root via anchors and centers the content.
	_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vbox.add_theme_constant_override("separation", 18)
	_vbox.alignment = BoxContainer.ALIGNMENT_CENTER

	_hero.text = "MOVEBORNE"
	_hero.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hero.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hero.add_theme_font_size_override("font_size", 34)
	_hero.add_theme_color_override("font_color", MbStyle.PRIMARY)
	_hero.custom_minimum_size = Vector2(320, 180)

	_style_play(_story, "Story")
	_style_play(_infinite, "Infinite")
	_style_play(_pvp, "PvP  ·  Coming Soon")
	_pvp.disabled = true
	_pvp.modulate = Color(1.0, 1.0, 1.0, 0.5)

	_story.pressed.connect(_launch.bind({"mode": "story", "scenario_id": 0}))
	_infinite.pressed.connect(_launch.bind({"mode": "infinite"}))


func _style_play(b: Button, label: String) -> void:
	b.text = label
	b.custom_minimum_size = Vector2(300, 64)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 26)


func _launch(cfg: Dictionary) -> void:
	play_mode_selected.emit(cfg)
