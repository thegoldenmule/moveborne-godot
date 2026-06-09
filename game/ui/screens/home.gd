extends Control
## The Home tab: a central hero + three play-mode launchers (Story / Infinite / PvP).
## Emits play_mode_selected(cfg) for the shell to start a match. PvP is gated.

signal play_mode_selected(cfg: Dictionary)

## Horizontal breathing room from the screen edges; buttons shrink to honor it on
## narrow screens rather than running to the edge.
const SCREEN_MARGIN := 24.0
const MAX_BUTTON_WIDTH := 360.0

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

	# Buttons fill the screen width minus an edge margin (capped on wide displays), so
	# there's always horizontal padding and they never run to the edge on narrow phones.
	var btn_w: float = minf(MAX_BUTTON_WIDTH, get_viewport_rect().size.x - 2.0 * SCREEN_MARGIN)
	_hero.custom_minimum_size = Vector2(btn_w, 180)

	_style_play(_story, "Story", btn_w)
	_style_play(_infinite, "Infinite", btn_w)
	_style_play(_pvp, "PvP  ·  Coming Soon", btn_w)
	# The PvP caption is long; shrink it so it fits inside the button width (the others
	# stay at the larger size) rather than forcing the button past the edge margin.
	_pvp.add_theme_font_size_override("font_size", 20)
	_pvp.disabled = true
	_pvp.modulate = Color(1.0, 1.0, 1.0, 0.5)

	_story.pressed.connect(_launch.bind({"mode": "story", "scenario_id": 0}))
	_infinite.pressed.connect(_launch.bind({"mode": "infinite"}))


func _style_play(b: Button, label: String, width: float) -> void:
	b.text = label
	b.custom_minimum_size = Vector2(width, 64)
	b.focus_mode = Control.FOCUS_NONE
	b.clip_text = true  # never let a long label push the button past the edge margin
	b.add_theme_font_size_override("font_size", 26)


func _launch(cfg: Dictionary) -> void:
	play_mode_selected.emit(cfg)
