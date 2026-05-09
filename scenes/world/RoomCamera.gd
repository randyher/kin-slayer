## RoomCamera.gd
## Attach to a Camera2D node (see RoomCamera.tscn).
##
## Every physics frame this camera:
##   1. Finds all nodes in the "players" group.
##   2. Moves to the midpoint between them.
##   3. Clamps that position to the current room's bounds so the
##      camera never shows empty space outside the room.
##
## When both players reach an exit, this camera fades to black,
## asks RoomManager to swap the room, then fades back in.

class_name RoomCamera
extends Camera2D

# ---------------------------------------------------------------------------
# EXPORTS
# ---------------------------------------------------------------------------

## Seconds for the fade-to-black and fade-from-black each.
## 0.4 s feels snappy; raise it for a slower cinematic feel.
@export var transition_duration : float = 0.4

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

# The Room we are currently connected to — stored so we can disconnect
# its signal before connecting to the next room.
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

	# If RoomManager already has a room loaded (e.g. the starting room),
	# connect to it now — otherwise we wait for the room_loaded signal.
	if RoomManager.current_room:
		_on_room_loaded(RoomManager.current_room)

# ---------------------------------------------------------------------------
# PHYSICS PROCESS  —  player tracking
# ---------------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	# Do not move the camera while the screen is fading — snapping after the
	# fade is handled explicitly inside _transition_to().
	if _transitioning:
		return
	_track_players()

# ---------------------------------------------------------------------------
# PLAYER TRACKING
# ---------------------------------------------------------------------------

func _track_players() -> void:
	var players : Array = get_tree().get_nodes_in_group("players")
	if players.is_empty():
		return

	# --- Calculate midpoint between all players ---
	# Works for 1-player (just centres on the single player) and
	# 2-player (centres between both).
	var mid := Vector2.ZERO
	for p : Node2D in players:
		mid += p.global_position
	mid /= float(players.size())

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

	global_position = mid

# ---------------------------------------------------------------------------
# ROOM SIGNAL WIRING
# Called by RoomManager.room_loaded every time a new room becomes active.
# ---------------------------------------------------------------------------

func _on_room_loaded(room: Node) -> void:
	var r := room as Room
	if r == null:
		return

	# Disconnect from the old room so its signal doesn't fire after it's freed.
	if _connected_room != null and _connected_room.exit_triggered.is_connected(_on_exit_triggered):
		_connected_room.exit_triggered.disconnect(_on_exit_triggered)

	_connected_room = r
	r.exit_triggered.connect(_on_exit_triggered)

	# Keep next_room / prev_room in sync with the newly loaded room's exports
	# so the camera always knows where to go from here.
	next_room        = r.next_room
	prev_room        = r.prev_room
	next_room_top    = r.next_room_top
	next_room_bottom = r.next_room_bottom

# ---------------------------------------------------------------------------
# EXIT RESPONSE
# ---------------------------------------------------------------------------

func _on_exit_triggered(direction: String) -> void:
	if _transitioning:
		return   # already mid-transition, ignore duplicate signals

	var target : PackedScene
	match direction:
		"right":  target = next_room
		"left":   target = prev_room
		"top":    target = next_room_top
		"bottom": target = next_room_bottom
	if target == null:
		return   # no room connected to this exit — dead end, do nothing

	_transition_to(target, direction)

# ---------------------------------------------------------------------------
# FADE TRANSITION
# ---------------------------------------------------------------------------

func _transition_to(room_scene: PackedScene, direction: String) -> void:
	_transitioning = true

	# ---- Step 1: fade to black ----
	var tween := create_tween()
	tween.tween_property(_fade_rect, "color", Color(0, 0, 0, 1), transition_duration)
	await tween.finished

	# ---- Step 2: swap the room ----
	# RoomManager.load_room() will:
	#   • free the old room
	#   • instantiate the new one
	#   • teleport players to the correct spawn marker
	#   • emit room_loaded  →  our _on_room_loaded fires automatically,
	#     which rewires exit signals and updates next_room / prev_room.
	RoomManager.load_room(room_scene, direction)

	# ---- Step 3: snap camera to players' new position ----
	# The players were teleported to a spawn marker, so we move the camera
	# there instantly while the screen is still black — no pan across the map.
	_track_players()

	# ---- Step 4: fade back in ----
	tween = create_tween()
	tween.tween_property(_fade_rect, "color", Color(0, 0, 0, 0), transition_duration)
	await tween.finished

	_transitioning = false
