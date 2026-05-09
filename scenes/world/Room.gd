## Room.gd
## Attach to the Node2D root of any Room scene.
##
## Each room knows its left and right neighbours (set in the Inspector),
## detects when all players walk into an exit, and tells the camera to
## start a transition.  The camera and RoomManager do the heavy lifting —
## this script only counts bodies and fires a signal.

class_name Room
extends Node2D

# ---------------------------------------------------------------------------
# EXPORTS  (set these in the Inspector for every room scene you create)
# ---------------------------------------------------------------------------

## The room that loads when players exit through the RIGHT side.
@export var next_room: PackedScene
## The room that loads when players exit through the LEFT side.
@export var prev_room: PackedScene
## The room that loads when players exit through the TOP.
@export var next_room_top: PackedScene
## The room that loads when players exit through the BOTTOM.
@export var next_room_bottom: PackedScene

# ---------------------------------------------------------------------------
# SIGNAL
# ---------------------------------------------------------------------------

## Emitted once ALL players are standing inside the same exit zone.
## direction will be "right" or "left".
signal exit_triggered(direction: String)

# ---------------------------------------------------------------------------
# NODE REFERENCES  (resolved automatically when the scene loads)
# ---------------------------------------------------------------------------

@onready var room_bounds  : Area2D   = $RoomBounds
@onready var exit_right   : Area2D   = $ExitRight
@onready var exit_left    : Area2D   = $ExitLeft
@onready var exit_top     : Area2D   = $ExitTop
@onready var exit_bottom  : Area2D   = $ExitBottom
@onready var spawn_left   : Marker2D = $SpawnLeft
@onready var spawn_right  : Marker2D = $SpawnRight
@onready var spawn_top    : Marker2D = $SpawnTop
@onready var spawn_bottom : Marker2D = $SpawnBottom

# ---------------------------------------------------------------------------
# INTERNAL STATE
# ---------------------------------------------------------------------------

# How many player bodies are currently inside each exit zone.
# We need ALL of them to be inside before we fire the signal.
var _in_right  : int = 0
var _in_left   : int = 0
var _in_top    : int = 0
var _in_bottom : int = 0

# ---------------------------------------------------------------------------
# READY
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Use .bind() so we can pass the direction string into a shared handler
	# without needing four separate callback methods.
	exit_right.body_entered.connect( _on_body_entered_exit.bind("right"))
	exit_right.body_exited.connect(  _on_body_exited_exit.bind( "right"))
	exit_left.body_entered.connect(  _on_body_entered_exit.bind("left"))
	exit_left.body_exited.connect(   _on_body_exited_exit.bind( "left"))
	exit_top.body_entered.connect(   _on_body_entered_exit.bind("top"))
	exit_top.body_exited.connect(    _on_body_exited_exit.bind( "top"))
	exit_bottom.body_entered.connect(_on_body_entered_exit.bind("bottom"))
	exit_bottom.body_exited.connect( _on_body_exited_exit.bind( "bottom"))

# ---------------------------------------------------------------------------
# EXIT DETECTION
# ---------------------------------------------------------------------------

func _on_body_entered_exit(body: Node2D, direction: String) -> void:
	# Only count bodies that belong to the "players" group.
	if not body.is_in_group("players"):
		return
	match direction:
		"right":  _in_right  += 1
		"left":   _in_left   += 1
		"top":    _in_top    += 1
		"bottom": _in_bottom += 1
	_check_trigger(direction)

func _on_body_exited_exit(body: Node2D, direction: String) -> void:
	if not body.is_in_group("players"):
		return
	match direction:
		"right":  _in_right  = maxi(_in_right  - 1, 0)
		"left":   _in_left   = maxi(_in_left   - 1, 0)
		"top":    _in_top    = maxi(_in_top    - 1, 0)
		"bottom": _in_bottom = maxi(_in_bottom - 1, 0)

func _check_trigger(direction: String) -> void:
	var total : int = get_tree().get_nodes_in_group("players").size()
	if total == 0:
		return

	var in_zone : int
	match direction:
		"right":  in_zone = _in_right
		"left":   in_zone = _in_left
		"top":    in_zone = _in_top
		"bottom": in_zone = _in_bottom
		_:        in_zone = 0

	# All players must be in the zone — if only one of two has entered,
	# we wait for the second.
	if in_zone >= total:
		exit_triggered.emit(direction)

# ---------------------------------------------------------------------------
# CAMERA BOUNDS HELPER
# ---------------------------------------------------------------------------

## Returns a Rect2 in world space that represents this room's camera lock area.
## The camera uses this every frame to clamp its position so it never
## shows anything outside the room.
func get_bounds_rect() -> Rect2:
	var col := room_bounds.get_node("CollisionShape2D") as CollisionShape2D
	if col == null or not col.shape is RectangleShape2D:
		# Fallback so the camera doesn't freeze if the shape is misconfigured.
		push_warning("Room: RoomBounds CollisionShape2D is missing or not a RectangleShape2D.")
		return Rect2(global_position, Vector2(320.0, 180.0))

	var rect_shape := col.shape as RectangleShape2D
	# The shape's centre in world space = Area2D position + shape offset.
	var center : Vector2 = room_bounds.global_position + col.position
	return Rect2(center - rect_shape.size * 0.5, rect_shape.size)
