class_name MbSafeArea
extends RefCounted

## Device safe-area insets (the notch / status bar at the top, the home indicator /
## gesture bar at the bottom) converted from physical screen px to logical (canvas)
## px. On desktop / in the editor the reported safe area equals the window, so both
## insets resolve to 0 and these are no-ops.
##
## This is the single source for that math. It was previously duplicated three ways
## — app_shell.gd (bottom), currency_bar.gd (top), and main.gd (top) — with subtle
## drift (only some clamped). Callers pass the logical viewport height
## (get_viewport_rect().size.y) and stay free of DisplayServer plumbing.
##
## Preload it (const SafeArea := preload("res://ui/safe_area.gd")) rather than lean
## on the class_name global: class_name registration needs a full editor scan, which
## the headless scene-instancing verifiers must not depend on.

## get_display_safe_area() is reported in GLOBAL screen coordinates; BOTH edges are
## made window-relative (against the window's position/size) so a windowed /
## multi-monitor desktop doesn't yield a bogus inset.
##
## Every inset is clamped to this fraction of the viewport height, so a surprising
## reading can never wreck the layout (push chrome off-screen).
const MAX_FRACTION := 0.15


## Top inset (notch / status bar) in logical px for the given viewport height.
static func top_inset(viewport_h: float) -> float:
	if viewport_h <= 0.0:
		return 0.0
	var win := DisplayServer.window_get_size()
	if win.y <= 0:
		return 0.0
	var safe := DisplayServer.get_display_safe_area()
	var phys_top := float(safe.position.y - DisplayServer.window_get_position().y)
	if phys_top <= 0.0:
		return 0.0
	# Physical px -> logical (canvas) px via the viewport/window height ratio.
	return minf(phys_top * viewport_h / float(win.y), viewport_h * MAX_FRACTION)


## Bottom inset (home indicator / gesture bar) in logical px for the given viewport
## height. The bottom edge is the gap between the safe area's bottom and the window's.
static func bottom_inset(viewport_h: float) -> float:
	if viewport_h <= 0.0:
		return 0.0
	var win := DisplayServer.window_get_size()
	if win.y <= 0:
		return 0.0
	var safe := DisplayServer.get_display_safe_area()
	# Window bottom in global screen coords minus the safe area's bottom — window-relative,
	# mirroring top_inset, so a non-origin desktop window doesn't yield a bogus inset.
	var win_bottom := float(DisplayServer.window_get_position().y + win.y)
	var phys_bottom := win_bottom - float(safe.position.y + safe.size.y)
	if phys_bottom <= 0.0:
		return 0.0
	return minf(phys_bottom * viewport_h / float(win.y), viewport_h * MAX_FRACTION)
