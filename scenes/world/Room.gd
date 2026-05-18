## Room.gd
## Attach to the Node2D root of any Room scene.
##
## Each room knows its left and right neighbours (set in the Inspector),
## detects when a player walks into an exit, and tells that player to start
## exiting while notifying RoomManager. The manager fires all_players_exited
## once every player has gone off screen.

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
# READY
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Use .bind() so we can pass the direction string into a shared handler
	# without needing four separate callback methods.
	exit_right.body_entered.connect( _on_body_entered_exit.bind("right"))
	exit_left.body_entered.connect(  _on_body_entered_exit.bind("left"))
	exit_top.body_entered.connect(   _on_body_entered_exit.bind("top"))
	exit_bottom.body_entered.connect(_on_body_entered_exit.bind("bottom"))

# ---------------------------------------------------------------------------
# EXIT DETECTION
# ---------------------------------------------------------------------------

func _on_body_entered_exit(body: Node2D, direction: String) -> void:
	if not (body is Player):
		return
	var player := body as Player

	# Map direction string to Vector2 and next room scene.
	var dir_vec: Vector2
	var next: PackedScene
	match direction:
		"right":
			dir_vec = Vector2.RIGHT
			next    = next_room
		"left":
			dir_vec = Vector2.LEFT
			next    = prev_room
		"top":
			dir_vec = Vector2.UP
			next    = next_room_top
		"bottom":
			dir_vec = Vector2.DOWN
			next    = next_room_bottom

	if next == null:
		return  # No room connected to this exit — dead end, ignore.

	player.start_exit(dir_vec)
	RoomManager.player_entered_exit(player, direction, next)

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
