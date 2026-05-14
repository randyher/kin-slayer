## MovingPlatform.gd
## Attach to an AnimatableBody2D.
##
## Oscillates back and forth (horizontal or vertical) using a smooth sin wave.
## All parameters are @export so you can tune them per-platform in the Inspector.
##
## Player carrying: Player.gd reads the public `velocity` var before its own
## move_and_slide() call so the player moves with the floor instead of sliding.

@tool
class_name MovingPlatform
extends AnimatableBody2D

enum Axis { HORIZONTAL, VERTICAL }

## Which direction the platform travels.
@export var axis: Axis = Axis.HORIZONTAL:
	set(v): axis = v; queue_redraw()

## Full cycles per second — 0.5 = one back-and-forth every 2 seconds.
@export_range(0.05, 5.0, 0.05, "suffix:cycles/s") var speed: float = 0.5

## Pixels from the start position to each end of the travel range.
## The platform moves this far in each direction from where it is placed.
@export_range(0.0, 1000.0, 8.0, "suffix:px") var distance: float = 128.0:
	set(v): distance = v; queue_redraw()

## Collision rectangle width — resize to match your tile visual.
@export_range(8.0, 512.0, 8.0, "suffix:px") var platform_width: float = 64.0:
	set(v): platform_width = v; _update_shape(); queue_redraw()

## Collision rectangle height — keep close to your tile height.
@export_range(4.0, 64.0, 4.0, "suffix:px") var platform_height: float = 16.0:
	set(v): platform_height = v; _update_shape(); queue_redraw()

## Exposed so Player.gd can add this to its velocity before move_and_slide().
var velocity: Vector2 = Vector2.ZERO

var _origin: Vector2
var _time: float = 0.0

@onready var _col_shape: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	# sync_to_physics = true (the default — we do NOT override it here).
	#
	# AnimatableBody2D has two movement modes:
	#
	#   sync_to_physics = true  (what we use here)
	#     Set global_position directly each frame.
	#     The physics server watches the node's transform change between frames
	#     and computes an effective velocity from the delta.
	#     That velocity is what get_collider_velocity() returns in Player.gd,
	#     which is how the player gets carried by the platform.
	#
	#   sync_to_physics = false
	#     Use move_and_collide() each frame instead.
	#     PROBLEM: move_and_collide() on AnimatableBody2D moves the physics
	#     server body but does NOT update the Node2D's global_position.
	#     Child nodes (like the TileMapLayer visual) follow the Node2D, not the
	#     physics body — so the visual stays put while only the invisible
	#     collision shape moves.  This is why the child "only moved down":
	#     the node transform never changed, but accumulated physics-body motion
	#     created a one-way drift in the collision box.
	#
	# Capture the placed world position as the centre of oscillation.
	# Must be in _ready() so global_position reflects the final scene-tree
	# position after all parent transforms are applied.
	_origin = global_position

	_update_shape()
	queue_redraw()

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_time += delta

	# sin() produces a smooth wave between -1 and +1.
	# Multiplying by distance scales it to ±distance pixels.
	# Multiplying time by speed * TAU (full circle in radians) sets the rate:
	#   speed = 0.5  → half a cycle per second  (one full trip takes 2 s)
	#   speed = 1.0  → one full cycle per second (one full trip takes 1 s)
	#
	# Example with distance = 100, vertical axis:
	#   t=0.00 s  sin = 0   platform is at _origin          (centre)
	#   t=0.25 s  sin = 1   platform is at _origin + 100 px (bottom)
	#   t=0.50 s  sin = 0   platform is back at _origin     (centre)
	#   t=0.75 s  sin = -1  platform is at _origin - 100 px (top)
	#   t=1.00 s  sin = 0   full cycle complete
	var offset := sin(_time * speed * TAU) * distance
	var target := _origin + (Vector2(offset, 0.0) if axis == Axis.HORIZONTAL
							 else Vector2(0.0, offset))

	# Record velocity so external code can read it if needed.
	velocity = (target - global_position) / delta

	# Set position directly — this is the correct way to drive AnimatableBody2D
	# when sync_to_physics = true.  The physics server compares this frame's
	# transform to last frame's and computes an effective velocity automatically.
	# That velocity is what Player.gd reads via get_collider_velocity() to carry
	# the player.  Child nodes (TileMapLayer visual, etc.) follow automatically
	# because they are children of this Node2D.
	#
	# Do NOT use move_and_collide() here.  On AnimatableBody2D it updates the
	# physics-server body but not global_position, so child visuals don't move.
	global_position = target

func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var hw := platform_width  * 0.5
	var hh := platform_height * 0.5
	draw_rect(Rect2(-hw, -hh, platform_width, platform_height), Color(0.3, 0.7, 1.0, 0.5))
	draw_rect(Rect2(-hw, -hh, platform_width, platform_height), Color(0.6, 0.9, 1.0), false, 1.5)
	if Engine.is_editor_hint() and distance > 0.0:
		var end := Vector2(
			distance if axis == Axis.HORIZONTAL else 0.0,
			distance if axis == Axis.VERTICAL   else 0.0)
		draw_line(Vector2.ZERO,  end, Color(1.0, 1.0, 0.0, 0.5), 1.0)
		draw_line(Vector2.ZERO, -end, Color(1.0, 1.0, 0.0, 0.5), 1.0)

func _update_shape() -> void:
	if not is_node_ready():
		return
	if _col_shape and _col_shape.shape is RectangleShape2D:
		(_col_shape.shape as RectangleShape2D).size = Vector2(platform_width, platform_height)
