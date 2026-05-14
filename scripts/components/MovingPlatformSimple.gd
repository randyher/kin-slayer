## MovingPlatformSimple.gd
## A minimal, easy-to-understand moving platform script.
## Attach this to an AnimatableBody2D node in your scene.
## The platform smoothly oscillates back and forth using a sin wave.

# AnimatableBody2D is the correct Godot 4 node type for scripted moving
# platforms. It interacts with CharacterBody2D (the player) properly.
extends AnimatableBody2D

# @export makes this variable visible and editable in the Godot Inspector.
# oscillation_speed controls how FAST the platform moves back and forth.
# Higher = faster. 2.0 means roughly one full trip per second.
@export var oscillation_speed: float = 2.0

# oscillation_distance controls how FAR the platform travels from its start.
# 80.0 means it moves 80 pixels in each direction from the placed position.
@export var oscillation_distance: float = 80.0

# @export_enum shows a dropdown in the Inspector with exactly these two choices.
# "vertical" moves the platform up and down.
# "horizontal" moves it left and right.
@export_enum("vertical", "horizontal") var direction: String = "vertical"

# _origin stores where the platform was placed in the editor.
# We oscillate around this point so the platform stays centered
# on where you placed it, regardless of the direction.
var _origin: Vector2

# _time is a running counter that increases every frame.
# Feeding it into sin() is what creates the smooth back-and-forth motion.
var _time: float = 0.0

func _ready() -> void:
	# global_position is where this node sits in the world right now.
	# We save it as _origin BEFORE any movement runs so we always know
	# the center point to oscillate around.
	# IMPORTANT: if you forget this line, _origin stays Vector2.ZERO
	# and the platform will oscillate around the top-left corner of the
	# world instead of where you placed it in the editor.
	_origin = global_position

func _physics_process(delta: float) -> void:
	# delta is the time in seconds since the last frame (usually ~0.016 at 60fps).
	# Adding it to _time makes the animation frame-rate independent —
	# the platform moves at the same real-world speed on fast and slow machines.
	_time += delta

	# sin() takes an angle (in radians) and returns a value between -1 and +1.
	# As _time grows, sin(_time * speed) smoothly cycles between -1 and +1,
	# which creates the back-and-forth oscillation effect.
	# Multiplying by oscillation_distance scales that -1..+1 range to
	# -oscillation_distance..+oscillation_distance in pixels.
	var offset: float = sin(_time * oscillation_speed) * oscillation_distance

	# Calculate where the platform should be THIS frame.
	# We start from _origin (the placed position) and add the offset
	# in whichever axis the designer chose in the Inspector.
	var target: Vector2
	if direction == "vertical":
		# Vector2(0, offset) means: don't move horizontally, move vertically.
		# Positive offset = down, negative offset = up (Godot Y axis is flipped).
		target = _origin + Vector2(0, offset)
	else:
		# Vector2(offset, 0) means: move horizontally, don't move vertically.
		target = _origin + Vector2(offset, 0)

	# Set the platform's world position directly to the target each frame.
	#
	# WHY NOT move_and_collide():
	#   move_and_collide() stops the platform the moment it touches anything —
	#   including a player standing on top.  When the platform tries to move UP
	#   it immediately collides with the player and freezes.  Moving DOWN works
	#   because gravity pulls the player away, so there is no collision.
	#
	# WHY global_position = target works instead:
	#   Setting global_position moves the platform to exactly the right place
	#   every frame regardless of what is in the way.  If the platform moves
	#   into the player, Godot's physics resolves the overlap by pushing the
	#   player out — which is exactly the "carrying" effect we want.
	#   AnimatableBody2D with sync_to_physics = true (the default, left unchanged)
	#   tells the physics server about the position change so it can compute the
	#   platform's effective velocity.  That velocity is what get_collider_velocity()
	#   returns in Player.gd, allowing the player to be carried horizontally too.
	global_position = target
