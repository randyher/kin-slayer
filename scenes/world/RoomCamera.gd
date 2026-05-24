## RoomCamera.gd
## Attach to a Camera2D node (see RoomCamera.tscn).
##
## Every physics frame this camera:
##   1. Finds all nodes in the "players" group.
##   2. Moves to the midpoint between them.
##   3. Clamps that position to the current room's bounds so the
##      camera never shows empty space outside the room.
##
## When all players have exited (gone off screen), RoomManager emits
## all_players_exited. This camera then fades to black, asks RoomManager
## to swap the room, then fades back in.

class_name RoomCamera
extends Camera2D

# ---------------------------------------------------------------------------
# EXPORTS
# ---------------------------------------------------------------------------

## Controls how the screen transition looks between rooms.
## Use INSTANT for fast testing; FADE_BLACK for the full cinematic effect.
## SLIDE is reserved for a future camera-pan effect.
enum TransitionStyle {
	FADE_BLACK,  # fade out to black → load → fade back in
	INSTANT,     # hard cut, no fade — best for testing
	# FUTURE — SLIDE: camera pans to the adjacent room without a fade.
	# Good for rooms that form a continuous space. Not yet implemented.
}
@export var transition_style: TransitionStyle = TransitionStyle.FADE_BLACK

## Seconds for the fade-to-black and fade-from-black each.
## 0.4 s feels snappy; raise it for a slower cinematic feel.
@export var transition_duration : float = 0.4

## How quickly the camera catches up to its target position each second.
## Higher = snappier; lower = floatier. 8 is a good starting point.
@export_range(1.0, 30.0, 0.5) var follow_speed: float = 8.0

## These are set automatically by _on_room_loaded() whenever the room changes.
## You do NOT need to set them manually — they mirror the current Room's exports.
@export var next_room        : PackedScene   ## right exit
@export var prev_room        : PackedScene   ## left  exit
@export var next_room_top    : PackedScene   ## top   exit
@export var next_room_bottom : PackedScene   ## bottom exit

# ---------------------------------------------------------------------------
# NODE REFERENCES
# ---------------------------------------------------------------------------

@onready var _fade_layer : CanvasLayer = $FadeLayer
@onready var _fade_rect  : ColorRect   = $FadeLayer/FadeRect

# ---------------------------------------------------------------------------
# INTERNAL STATE
# ---------------------------------------------------------------------------

# Guards against starting a second transition while one is still running.
var _transitioning : bool = false

# The Room we are currently connected to — stored so we can update our
# local next/prev references when a new room loads.
var _connected_room : Room = null   # safe — used only inside this script after casting

# ---------------------------------------------------------------------------
# READY
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Make the black overlay fill the entire screen regardless of resolution.
	_fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade_rect.color = Color(0.0, 0.0, 0.0, 0.0)   # start fully transparent

	# Listen for room changes from the autoload.
	RoomManager.room_loaded.connect(_on_room_loaded)

	# Listen for all-players-exited from RoomManager.
	RoomManager.all_players_exited.connect(_on_all_players_exited)

	# If RoomManager already has a room loaded (e.g. the starting room),
	# connect to it now — otherwise we wait for the room_loaded signal.
	if RoomManager.current_room:
		_on_room_loaded(RoomManager.current_room)

# ---------------------------------------------------------------------------
# PHYSICS PROCESS  —  player tracking
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	# Do not move the camera while the screen is fading — snapping after the
	# fade is handled explicitly inside _transition_to().
	if _transitioning:
		return
	_track_players(delta)

# ---------------------------------------------------------------------------
# PLAYER TRACKING
# ---------------------------------------------------------------------------

## delta > 0  → smooth lerp (normal per-frame tracking).
## delta = 0  → instant snap (called after a room load while screen is black).
func _track_players(delta: float = 0.0) -> void:
	var players : Array = get_tree().get_nodes_in_group("players")
	if players.is_empty():
		return

	# Exclude any player currently leaving the room — the camera should only
	# follow whoever is still inside. arrive_in_room() resets state to IDLE,
	# so tracking automatically widens back to both players on the next room.
	var tracked : Array = players.filter(func(p: Node) -> bool:
		return not (p is Player and (p as Player).state == Player.State.EXITING))
	if tracked.is_empty():
		tracked = players   # both exiting simultaneously — fall back to everyone

	# --- Calculate midpoint between tracked players ---
	var mid := Vector2.ZERO
	for p : Node2D in tracked:
		mid += p.global_position
	mid /= float(tracked.size())

	# --- Clamp to room bounds so the camera never pans outside ---
	var room := RoomManager.current_room as Room
	if room:
		var bounds  : Rect2   = room.get_bounds_rect()
		var half_vp : Vector2 = get_viewport_rect().size * 0.5 / zoom
		# Guard: if the viewport is wider/taller than the room on an axis,
		# clamping would invert (min > max) and lock the camera in the wrong
		# place. Centre on the room instead for any axis that doesn't fit.
		if half_vp.x * 2.0 < bounds.size.x:
			mid.x = clampf(mid.x, bounds.position.x + half_vp.x, bounds.end.x - half_vp.x)
		else:
			mid.x = bounds.get_center().x
		if half_vp.y * 2.0 < bounds.size.y:
			mid.y = clampf(mid.y, bounds.position.y + half_vp.y, bounds.end.y - half_vp.y)
		else:
			mid.y = bounds.get_center().y

	if delta > 0.0:
		global_position = global_position.lerp(mid, follow_speed * delta)
	else:
		global_position = mid

# ---------------------------------------------------------------------------
# ROOM SIGNAL WIRING
# Called by RoomManager.room_loaded every time a new room becomes active.
# ---------------------------------------------------------------------------

func _on_room_loaded(room: Node) -> void:
	var r := room as Room
	if r == null:
		return

	_connected_room = r

	# Keep next_room / prev_room in sync with the newly loaded room's exports
	# so the camera always knows where to go from here.
	next_room        = r.next_room
	prev_room        = r.prev_room
	next_room_top    = r.next_room_top
	next_room_bottom = r.next_room_bottom

# ---------------------------------------------------------------------------
# EXIT RESPONSE
# Called by RoomManager.all_players_exited once every player is off screen.
# ---------------------------------------------------------------------------

func _on_all_players_exited(direction: String, next_room: PackedScene) -> void:
	if _transitioning:
		return
	if next_room == null:
		return
	_transition_to(next_room, direction)

# ---------------------------------------------------------------------------
# FADE TRANSITION
# ---------------------------------------------------------------------------

func _transition_to(room_scene: PackedScene, direction: String) -> void:
	_transitioning = true

	match transition_style:
		TransitionStyle.FADE_BLACK:
			# ---- Step 1: fade to black ----
			var tween := create_tween()
			tween.tween_property(_fade_rect, "color", Color(0, 0, 0, 1), transition_duration)
			await tween.finished

			# ---- Step 2: swap the room ----
			# RoomManager.load_room() will:
			#   • free the old room
			#   • instantiate the new one
			#   • call arrive_in_room() on each Player (sets position + re-enables physics)
			#   • emit room_loaded  →  our _on_room_loaded fires automatically
			RoomManager.load_room(room_scene, direction)

			# ---- Step 3: snap camera to players' new position ----
			_track_players()

			# ---- Step 4: fade back in ----
			tween = create_tween()
			tween.tween_property(_fade_rect, "color", Color(0, 0, 0, 0), transition_duration)
			await tween.finished

		TransitionStyle.INSTANT:
			# Hard cut — no fade. Useful for testing without waiting.
			RoomManager.load_room(room_scene, direction)
			_track_players()

		_:  # SLIDE and anything else — fall back to INSTANT for now.
			RoomManager.load_room(room_scene, direction)
			_track_players()

	_transitioning = false
