## ActionCommand.gd
## Floating timing indicator shown above the attacking player during combo hits.
## A white circle shrinks inward toward the ✕ button sprite.
## Press ✕ as the circle reaches the button edge for a successful hit.
## Success → gold flash + "NICE!" → next hit plays.
## Miss → red flash + "MISS" → combo ends.
##
## Attach to the ActionCommand Node2D in World.tscn.
## BattleManager._action_command references this node directly.
## FUTURE — different visual styles per weapon type:
##   shield = square indicator, chain = waving line, bare hands = current circle.

extends Node2D

# ---------------------------------------------------------------------------
# EXPORTS — all tunable live in the Inspector
# ---------------------------------------------------------------------------

@export_group("Timing")
## How long the circle takes to shrink to the button edge (seconds).
## Larger = easier (more time to react).
@export_range(0.1, 1.0, 0.05, "suffix:s") var timing_window: float = 0.5
## Slightly tighter window for the third hit — rewards players who learned hit 2.
@export_range(0.1, 1.0, 0.05, "suffix:s") var hit3_timing_window: float = 0.4
## Starting radius of the shrinking circle in pixels.
@export_range(0.0, 100.0, 1.0, "suffix:px") var circle_start_radius: float = 60.0
## Radius of the ✕ button sprite — success zone outer edge aligns here.
@export_range(0.0, 50.0, 1.0, "suffix:px") var button_radius: float = 24.0
## Width of the acceptable timing zone in pixels.
## Success fires when circle_radius is between button_radius and
## button_radius + sweet_spot_width.
## Larger = more forgiving.
@export_range(0.0, 20.0, 0.1, "suffix:px") var sweet_spot_width: float = 7.0

@export_group("Damage")
## Damage dealt by the first hit — always lands, no timing required.
@export_range(1, 20, 1) var hit1_damage: int = 1
## Damage dealt by the second hit on successful timing.
@export_range(1, 20, 1) var hit2_damage: int = 1
## Damage dealt by the third hit on successful timing — bonus damage.
@export_range(1, 20, 1) var hit3_damage: int = 2

@export_group("Visual")
## Circle color while shrinking (neutral state).
@export var circle_color_neutral: Color = Color(1.0, 1.0, 1.0, 0.8)
## Circle color on a successful press — gold.
@export var circle_color_success: Color = Color(1.0, 0.85, 0.0, 1.0)
## Circle color on a miss — red.
@export var circle_color_miss: Color = Color(0.8, 0.1, 0.1, 0.8)
## Thickness of the shrinking circle ring in pixels.
@export_range(1.0, 8.0, 0.5, "suffix:px") var ring_thickness: float = 3.0
## How long the gold/red flash lasts before emitting the result signal.
@export_range(0.0, 1.0, 0.05, "suffix:s") var result_flash_duration: float = 0.25
## Radius of the static outer target ring drawn around the button icon.
## The shrinking circle aims to land inside this ring — increase to widen the
## gap between the icon and the target boundary.
@export_range(0.0, 120.0, 0.5, "suffix:px") var outer_ring_radius: float = 22.0
## Color of the static outer target ring.
@export var outer_ring_color: Color = Color(1.0, 1.0, 1.0, 0.35)

# ---------------------------------------------------------------------------
# SIGNALS
# ---------------------------------------------------------------------------

## Emitted after the flash finishes with the result.
## success=true → hit landed; success=false → miss.
## Player._do_attack_sequence() awaits this directly:
##   var success = await action_cmd.timing_result
## Using one signal with a bool avoids lambda-capture issues with local variables.
signal timing_result(success: bool)

# ---------------------------------------------------------------------------
# INTERNAL STATE
# ---------------------------------------------------------------------------

var _current_radius: float = 0.0
var _is_active: bool = false
var _current_window: float = 0.5
var _elapsed: float = 0.0
var _result_shown: bool = false
var _current_color: Color
var _player_id: int = 1
## The attacking player node — ActionCommand follows them while active.
var _active_player: Node = null

@onready var _button_icon  : TextureRect = $ButtonIcon
@onready var _result_label : Label       = $ResultLabel

# ---------------------------------------------------------------------------
# READY
# ---------------------------------------------------------------------------

func _ready() -> void:
	add_to_group("action_command")
	# Load the dedicated cross_flat sprite (18×18 px).
	_button_icon.texture = preload("res://scenes/ui/buttons/cross_flat.png")
	_button_icon.scale = Vector2(3.0, 3.0)
	# Hardcode pivot at the texture center so the 3× scale expands outward
	# symmetrically. cross_flat.png is 18×18, so the pivot is at (9, 9).
	# Do NOT derive from _button_icon.size — Control layout may not be
	# resolved yet in _ready(), making size unreliable here.
	_button_icon.pivot_offset = Vector2(9.0, 9.0)
	visible = false

# ---------------------------------------------------------------------------
# ACTIVATE / DEACTIVATE
# ---------------------------------------------------------------------------

## Show the timing indicator for the given player and window duration.
## player_node: the attacking Player node so ActionCommand can follow them.
func activate(player_id: int, window: float, player_node: Node = null) -> void:
	_player_id    = player_id
	_active_player = player_node
	_current_window = window
	_current_radius = circle_start_radius
	_elapsed        = 0.0
	_is_active      = true
	_result_shown   = false
	_current_color  = circle_color_neutral
	visible = true
	_result_label.text = ""
	_result_label.modulate.a = 0.0
	queue_redraw()

func deactivate() -> void:
	_is_active = false
	visible = false
	_current_radius = 0.0
	_active_player = null
	queue_redraw()

# ---------------------------------------------------------------------------
# PROCESS
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	# Follow the attacking player every frame while active.
	if _active_player and _is_active:
		global_position = _active_player.global_position + Vector2(0.0, -80.0)

	if not _is_active:
		return
	if _result_shown:
		return

	# Shrink the circle toward the button over the timing window.
	_elapsed += delta
	var t: float = _elapsed / _current_window
	_current_radius = lerpf(circle_start_radius, 0.0, t)
	queue_redraw()

	# Check for player input — jump button maps to the ✕ action.
	var jump_action: String = "p%d_cross" % _player_id
	if Input.is_action_just_pressed(jump_action):
		_check_timing()
		return

	# Auto-miss once the shrinking circle passes well inside the outer ring.
	# outer_ring_radius is the source of truth — button_radius is unused.
	if _current_radius < outer_ring_radius - sweet_spot_width:
		_on_miss()

# ---------------------------------------------------------------------------
# TIMING CHECK
# ---------------------------------------------------------------------------

func _check_timing() -> void:
	# outer_ring_radius is the single source of truth for timing detection.
	# Success fires when the shrinking circle is within sweet_spot_width of
	# the outer ring — so pressing as the circle reaches the visual ring works.
	# FUTURE — perfect timing inner zone: tighter window for extra damage bonus.
	if abs(_current_radius - outer_ring_radius) <= sweet_spot_width:
		_on_success()
	else:
		_on_miss()

# ---------------------------------------------------------------------------
# RESULT HANDLERS
# ---------------------------------------------------------------------------

func _on_success() -> void:
	_result_shown = true
	_is_active    = false
	_current_color = circle_color_success
	queue_redraw()

	# Flash the button icon gold then back to white.
	var tween := create_tween()
	tween.tween_property(_button_icon, "modulate",
		Color(1.0, 0.85, 0.0, 1.0), result_flash_duration * 0.5)
	tween.tween_property(_button_icon, "modulate",
		Color(1.0, 1.0, 1.0, 1.0), result_flash_duration * 0.5)

	# "NICE!" label fades in then out below the button.
	_result_label.text = "NICE!"
	_result_label.modulate = Color(1.0, 0.85, 0.0, 1.0)
	var label_tween := create_tween()
	label_tween.tween_property(_result_label, "modulate:a", 1.0, 0.1)
	label_tween.tween_property(_result_label, "modulate:a", 0.0, result_flash_duration)

	await get_tree().create_timer(result_flash_duration).timeout
	deactivate()
	timing_result.emit(true)

func _on_miss() -> void:
	_result_shown = true
	_is_active    = false
	_current_color = circle_color_miss
	queue_redraw()

	# Flash the button icon red then back to white.
	var tween := create_tween()
	tween.tween_property(_button_icon, "modulate",
		Color(0.8, 0.1, 0.1, 1.0), result_flash_duration * 0.5)
	tween.tween_property(_button_icon, "modulate",
		Color(1.0, 1.0, 1.0, 1.0), result_flash_duration * 0.5)

	# "MISS" label fades in then out.
	_result_label.text = "MISS"
	_result_label.modulate = Color(0.8, 0.1, 0.1, 1.0)
	var label_tween := create_tween()
	label_tween.tween_property(_result_label, "modulate:a", 1.0, 0.1)
	label_tween.tween_property(_result_label, "modulate:a", 0.0, result_flash_duration)

	await get_tree().create_timer(result_flash_duration).timeout
	deactivate()
	timing_result.emit(false)

# ---------------------------------------------------------------------------
# DRAW — shrinking ring
# ---------------------------------------------------------------------------

func _draw() -> void:
	if not _is_active and not _result_shown:
		return
	# Static outer target ring — fixed boundary the shrinking circle aims for.
	# Tune outer_ring_radius in the Inspector to set how far from the icon edge
	# the target sits; the gap between icon and this ring is the timing zone.
	draw_arc(Vector2.ZERO, outer_ring_radius, 0.0, TAU, 64,
		outer_ring_color, ring_thickness, true)
	# Shrinking ring — closes inward toward the outer ring.
	if _current_radius > 0.0:
		draw_arc(Vector2.ZERO, _current_radius, 0.0, TAU, 64,
			_current_color, ring_thickness, true)
