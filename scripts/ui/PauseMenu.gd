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
##   p1_jump / p2_jump → confirm highlighted item

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
	# ---- Pause / resume toggle (Escape) ----
	if event.is_action_just_pressed("pause"):
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
	if event.is_action_just_pressed("p1_up") or event.is_action_just_pressed("p2_up"):
		_selected = MenuItem.RETURN
		_update_highlights()
		get_viewport().set_input_as_handled()

	# ---- Navigate down → Debug Mode ----
	elif event.is_action_just_pressed("p1_down") or event.is_action_just_pressed("p2_down"):
		_selected = MenuItem.DEBUG_MODE
		_update_highlights()
		get_viewport().set_input_as_handled()

	# ---- Confirm with jump ----
	elif event.is_action_just_pressed("p1_jump") or event.is_action_just_pressed("p2_jump"):
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
			# Toggle physics collision shape outlines.
			# get_tree().debug_collisions_hint draws the shapes Godot uses for
			# physics — useful for tuning hitboxes and tile collision.
			_debug_active = not _debug_active
			get_tree().debug_collisions_hint = _debug_active
			_update_highlights()   # refresh label text to show ON / OFF

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
