extends CanvasLayer

## Persistent top currency bar for the app shell: coins / souls / gems, the
## typical F2P layout. Lives on its own CanvasLayer (mirroring the NavBar
## pattern — Controls under a CanvasLayer don't resolve wide anchors to the
## viewport reliably, so the band is sized explicitly), inset below the device
## safe area. Hidden with the shell while a match covers it (AppShell
## set_active hides this layer explicitly, like the nav layer).
##
## Balances render from GameState.currencies (cache + signal); refresh() does
## the authoritative GET via MbInventory. Icons are styled glyph placeholders
## pending generated occult-arcade icons (artgen).

const MbSnapserAuthS := preload("res://net/snapser_auth.gd")
const MbInventoryS := preload("res://net/inventory_client.gd")

const BAR_HEIGHT := 44.0
## glyph + accent color per currency, in display order.
const SLOTS := [
	{"name": "coins", "glyph": "✦", "color": Color("f5c542")},
	{"name": "souls", "glyph": "☾", "color": Color("b400ff")},
	{"name": "gems", "glyph": "◆", "color": Color("42d8f5")},
]

var _auth: Node
var _inventory: Node
var _bar: PanelContainer
var _labels := {}   # currency name -> value Label
var _refreshing := false


## Pass the shell's shared MbSnapserAuth so the bar reuses its session; a
## standalone bar (tests) creates its own.
func _init(auth: Node = null) -> void:
	_auth = auth


func _ready() -> void:
	layer = 5
	if _auth == null:
		_auth = MbSnapserAuthS.new()
		add_child(_auth)
	name = "CurrencyLayer"
	_inventory = MbInventoryS.new()
	_inventory.name = "InventoryClient"
	add_child(_inventory)

	_bar = PanelContainer.new()
	_bar.name = "Bar"
	add_child(_bar)
	# A Control under a CanvasLayer has no Control parent, so the shell's theme
	# (and its brand font) doesn't propagate — set our own.
	var th := Theme.new()
	th.default_font = load(MbStyle.FONT_PATH)
	th.default_font_size = 16
	_bar.theme = th
	var sb := StyleBoxFlat.new()
	sb.bg_color = MbStyle.BOARD
	sb.border_color = MbStyle.PRIMARY
	sb.set_border_width(SIDE_BOTTOM, 2)
	sb.set_content_margin_all(0)
	_bar.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.name = "Row"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 36)
	_bar.add_child(row)

	for slot in SLOTS:
		row.add_child(_make_slot(slot))

	_apply_layout()
	get_viewport().size_changed.connect(_apply_layout)
	GameState.currencies_changed.connect(_on_currencies_changed)
	_on_currencies_changed(GameState.currencies)
	refresh()


## One icon+amount pair. The glyph Label stands in for a generated icon.
func _make_slot(slot: Dictionary) -> Control:
	var box := HBoxContainer.new()
	box.name = "Slot_%s" % slot["name"]
	box.add_theme_constant_override("separation", 6)
	var icon := Label.new()
	icon.name = "Icon"
	icon.text = slot["glyph"]
	icon.add_theme_font_size_override("font_size", 18)
	icon.add_theme_color_override("font_color", slot["color"])
	box.add_child(icon)
	var value := Label.new()
	value.name = "Value"
	value.text = "0"
	value.add_theme_font_size_override("font_size", 16)
	value.add_theme_color_override("font_color", MbStyle.TEXT)
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(value)
	_labels[slot["name"]] = value
	return box


## Authoritative refresh from the Inventory snap. Coroutine, fire-and-forget;
## keeps the last known balances on any failure (offline/desktop dev).
func refresh() -> void:
	if _refreshing:
		return
	_refreshing = true
	var balances: Dictionary = await _inventory.fetch_balances(_auth)
	_refreshing = false
	if not balances.is_empty():
		GameState.set_currencies(balances)


func _on_currencies_changed(balances: Dictionary) -> void:
	for name in _labels:
		_labels[name].text = str(int(balances.get(name, 0)))


## Total vertical space the band occupies from the top of the viewport (safe
## inset + bar height). The shell reads this to inset its content host so tab
## screens lay out *below* the band instead of under it.
func occupied_height() -> float:
	return _top_safe_inset() + BAR_HEIGHT


## Pin the band full-width below the top safe inset (notch/status bar).
func _apply_layout() -> void:
	var vp: Vector2 = _bar.get_viewport().get_visible_rect().size
	_bar.position = Vector2(0.0, _top_safe_inset())
	_bar.size = Vector2(vp.x, BAR_HEIGHT)


func _top_safe_inset() -> float:
	var win := DisplayServer.window_get_size()
	if win.y <= 0:
		return 0.0
	var safe := DisplayServer.get_display_safe_area()
	var phys_top := float(safe.position.y - DisplayServer.window_get_position().y)
	if phys_top <= 0.0:
		return 0.0
	var vp_y: float = _bar.get_viewport().get_visible_rect().size.y
	return minf(phys_top * vp_y / float(win.y), vp_y * 0.15)
