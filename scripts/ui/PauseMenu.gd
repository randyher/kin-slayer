## PauseMenu.gd
## Handles pausing and the pause overlay menu.
##
## process_mode = PROCESS_MODE_ALWAYS (set in the .tscn) lets this node
## receive _input even while get_tree().paused = true — without that,
## the Escape key would never fire and you'd be stuck in the pause screen.
##
## Controls:
##   Escape          → toggle pause
##   p1_up / p2_up   → highlight Return
##   p1_down / p2_down → highlight Debug Mode
##   p1_cross / p2_cross → confirm highlighted item

extends CanvasLayer

# ---------------------------------------------------------------------------
# MENU STATE
# ---------------------------------------------------------------------------

enum MenuItem { RETURN, DEBUG_MODE }

# Which item is currently highlighted.  Always defaults to RETURN on open.
var _selected     : MenuItem = MenuItem.RETURN
var _debug_active : bool     = false

# Highlighted = white, idle = dim gray.
const COLOR_SELECTED   := Color(1.0, 1.0, 1.0, 1.0)
const COLOR_UNSELECTED := Color(0.45, 0.45, 0.45, 1.0)

# ---------------------------------------------------------------------------
# NODE REFERENCES
# ---------------------------------------------------------------------------
@onready var _label_return : Label = $Menu/LabelReturn
@onready var _label_debug  : Label = $Menu/LabelDebug

# ---------------------------------------------------------------------------
# READY
# ---------------------------------------------------------------------------
func _ready() -> void:
	visible = false   # menu is hidden until Escape is pressed

# ---------------------------------------------------------------------------
# INPUT
# _input fires for this node even while paused because process_mode = ALWAYS.
# get_viewport().set_input_as_handled() stops the event reaching the game.
# ---------------------------------------------------------------------------
func _input(event: InputEvent) -> void:
	# is_action_pressed() + not is_echo() is the correct "just pressed" check
	# inside _input() in Godot 4.  is_action_just_pressed() only exists on
	# the Input singleton, not on an InputEvent object.

	# ---- Pause / resume toggle ----
	if (event.is_action_pressed("p1_pause") or event.is_action_pressed("p2_pause")) \
			and not event.is_echo():
		if get_tree().paused:
			_unpause()
		else:
			_pause()
		get_viewport().set_input_as_handled()
		return

	# Ignore all other input while the menu is closed.
	if not visible:
		return

	# ---- Navigate up → Return ----
	if (event.is_action_pressed("p1_up") or event.is_action_pressed("p2_up")) \
			and not event.is_echo():
		_selected = MenuItem.RETURN
		_update_highlights()
		get_viewport().set_input_as_handled()

	# ---- Navigate down → Debug Mode ----
	elif (event.is_action_pressed("p1_down") or event.is_action_pressed("p2_down")) \
			and not event.is_echo():
		_selected = MenuItem.DEBUG_MODE
		_update_highlights()
		get_viewport().set_input_as_handled()

	# ---- Confirm with jump ----
	elif (event.is_action_pressed("p1_cross") or event.is_action_pressed("p2_cross")) \
			and not event.is_echo():
		_confirm()
		get_viewport().set_input_as_handled()

# ---------------------------------------------------------------------------
# PAUSE / UNPAUSE
# ---------------------------------------------------------------------------
func _pause() -> void:
	get_tree().paused = true
	visible = true
	_selected = MenuItem.RETURN   # always land on Return so Escape→Space = fast resume
	_update_highlights()

func _unpause() -> void:
	get_tree().paused = false
	visible = false

# ---------------------------------------------------------------------------
# CONFIRM SELECTION
# ---------------------------------------------------------------------------
func _confirm() -> void:
	match _selected:
		MenuItem.RETURN:
			_unpause()

		MenuItem.DEBUG_MODE:
			_debug_active = not _debug_active
			_apply_debug_collisions(_debug_active)
			_update_highlights()

# ---------------------------------------------------------------------------
# DEBUG COLLISION DISPLAY
# ---------------------------------------------------------------------------
# get_tree().debug_collisions_hint is the Godot-native toggle but does not
# work in GL Compatibility mode (the project's current renderer).
# Instead we walk the full scene tree and flip the visible flag on every
# CollisionShape2D and CollisionPolygon2D node, which forces them to draw
# their outlines via their own _draw() implementations.
# Tile-map physics shapes are handled separately by debug_collisions_hint
# (it still works for TileMapLayer in some builds).
func _apply_debug_collisions(enabled: bool) -> void:
	get_tree().debug_collisions_hint = enabled
	_toggle_shape_nodes(get_tree().get_root(), enabled)

func _toggle_shape_nodes(node: Node, enabled: bool) -> void:
	if node is CollisionShape2D:
		var cs := node as CollisionShape2D
		# Only show shapes that are active — disabled shapes aren't used for
		# physics so showing them in debug mode would be misleading.
		cs.visible = enabled and not cs.disabled
		cs.queue_redraw()
	elif node is CollisionPolygon2D:
		var cp := node as CollisionPolygon2D
		cp.visible = enabled and not cp.disabled
		cp.queue_redraw()
	for child in node.get_children():
		_toggle_shape_nodes(child, enabled)

# ---------------------------------------------------------------------------
# HIGHLIGHT LABELS
# ---------------------------------------------------------------------------
func _update_highlights() -> void:
	_label_return.add_theme_color_override("font_color",
		COLOR_SELECTED if _selected == MenuItem.RETURN else COLOR_UNSELECTED)

	_label_debug.add_theme_color_override("font_color",
		COLOR_SELECTED if _selected == MenuItem.DEBUG_MODE else COLOR_UNSELECTED)

	# Append ON / OFF so the player can see debug state at a glance.
	_label_debug.text = "Debug Mode  [ON]" if _debug_active else "Debug Mode"
