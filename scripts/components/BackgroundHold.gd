## BackgroundHold.gd
## Attach to the BackgroundHold Node2D root (see scenes/entities/BackgroundHold.tscn).
##
## A BackgroundHold is a surface the player can grab and hang from in
## the background plane — like a bar, pipe, or handhold painted into the
## stage.  The player overlaps it with their HoldDetector Area2D, then
## grabs it via the grip button.
##
## Signals let external systems (e.g. BattleManager, scripted events)
## react to players grabbing or releasing holds.

class_name BackgroundHold
extends Node2D

# ---------------------------------------------------------------------------
# HOLD TYPE
# Controls which animation set the player uses while hanging.
# BACKGROUND: back-view Climb animations — ACTIVE in this build.
# ROPE:       side-view MonkeyBar animations — RESERVED for future use.
#
# ROPE hold_type is reserved for future monkey bar /
# rope implementation.  Only BACKGROUND is active now.
# ---------------------------------------------------------------------------
enum HoldType {
	BACKGROUND,   # back-view bar / handhold — uses ClimbGrab/ClimbIdle/ClimbLeft/ClimbRight
	ROPE          # side-view rope — will use MonkeyBarIdle / MonkeyBarsClimb (not yet implemented)
}

# ---------------------------------------------------------------------------
# EXPORTS
# All designer-tunable values — adjust in the Inspector per hold instance.
# ---------------------------------------------------------------------------

## Displayed in the editor scene tree to identify this hold at a glance.
@export var hold_label: String = "Hold"

## Width of the grabbable zone in pixels.
## The collision shape is resized to this value in _ready().
## Players are clamped within ± hold_width/2 of this node's centre while hanging.
@export var hold_width: float = 64.0

## Height of the grabbable detection zone in pixels.
## Keep close to the visual bar height for a tight "pipe grab" feel.
## Note: the player's HoldDetector (56 px tall) adds ~28 px of extra range on
## each side, so total grab range = hold_height / 2 + 28 px from centre.
@export_range(4.0, 128.0, 4.0, "suffix:px") var hold_height: float = 16.0

## Determines which player animation set is used while hanging here.
## Only BACKGROUND is implemented; ROPE is reserved for a future update.
@export var hold_type: HoldType = HoldType.BACKGROUND

# ---------------------------------------------------------------------------
# SIGNALS
# ---------------------------------------------------------------------------

## Emitted when a physics body (typically a Player) enters the hold zone.
signal player_grabbed(player: Node)

## Emitted when a physics body leaves the hold zone.
signal player_released(player: Node)

# ---------------------------------------------------------------------------
# NODE REFERENCES
# ---------------------------------------------------------------------------

@onready var _hold_zone   : Area2D            = $HoldZone
@onready var _col_shape   : CollisionShape2D  = $HoldZone/CollisionShape2D

# ---------------------------------------------------------------------------
# READY
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Render behind the game world so holds appear in the background plane.
	z_index = -5
	z_as_relative = false

	# Add the HoldZone Area2D — not the root Node2D — to the group.
	# Player.HoldDetector fires area_entered with the Area2D as the argument,
	# so the group must be on the Area2D for Player.gd's group check to work.
	_hold_zone.add_to_group("background_holds")

	# Resize the collision rectangle to match the exported dimensions.
	if _col_shape.shape is RectangleShape2D:
		var rect := _col_shape.shape as RectangleShape2D
		rect.size.x = hold_width
		rect.size.y = hold_height

	# Connect zone signals to this script's signals so callers can subscribe
	# to player_grabbed / player_released on the BackgroundHold node directly.
	_hold_zone.body_entered.connect(func(body: Node2D) -> void:
		player_grabbed.emit(body))
	_hold_zone.body_exited.connect(func(body: Node2D) -> void:
		player_released.emit(body))

	# Draw the debug visual so the hold is visible while testing.
	queue_redraw()

func _draw() -> void:
	# Solid white bar — the visual pipe / handhold the player sees.
	draw_rect(Rect2(-hold_width * 0.5, -8.0, hold_width, 16.0), Color.WHITE)
	# Outline showing the actual detection zone (hold_height).
	# The player's HoldDetector adds ~28 px on each side beyond this outline.
	var dh := hold_height
	draw_rect(Rect2(-hold_width * 0.5, -dh * 0.5, hold_width, dh),
			Color(1.0, 1.0, 0.0, 0.35), false, 1.0)
