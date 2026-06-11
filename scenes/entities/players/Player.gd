## Player.gd
## Attach to a CharacterBody2D node.
## Handles movement, jumping, and dashing for up to 2 local co-op players.
## All "feel" variables are @export so you can tune them live in the Inspector
## without touching code.

class_name Player
extends CharacterBody2D

## Fired whenever stamina changes — connect this to the HUD when it's built.
## current = new stamina value,  maximum = stamina_max export.
signal stamina_changed(current: float, maximum: float)

## Fired whenever HP changes (damage or heal).
## Connect to the HUD to update the heart display.
signal hp_changed(current: int, maximum: int)

## Fired when current_hp reaches 0.
## Death behaviour is not yet implemented — this signal is the hook for it.
signal player_died

# ---------------------------------------------------------------------------
# PLAYER IDENTITY
# ---------------------------------------------------------------------------
## Which local player controls this character (1 or 2).
## Player 1 uses WASD / Space / Left Shift.
## Player 2 uses Arrow Keys / Enter / Right Shift.
@export var player_id: int = 1
## Tint applied to the sprite — lets co-op players use the same base sheet
## with different color reads. Player 1 stays white (no tint); set Player 2
## to a blue-grey (or any color) in the Inspector or TestWorld override.
@export var player_color: Color = Color.WHITE

# ---------------------------------------------------------------------------
# EXPORTED FEEL VARIABLES
# ---------------------------------------------------------------------------
# These drive how the character feels to control. Tweak them in the Inspector
# at runtime — Godot will apply changes instantly so you can dial in the feel
# without restarting the scene.

@export_group("Movement Abilities")
## Master switch for all dashing — ground and air. When off, no dash can fire.
@export var dash_enabled: bool = true
## Master switch for wall climbing and ledge grabbing. When off, the player
## cannot grip walls or auto-grab ledges.
@export var climbing_enabled: bool = true

@export_group("Movement")
## Top horizontal speed in pixels per second.
@export_range(50.0, 600.0, 10.0, "suffix:px/s") var move_speed: float = 200.0
## How quickly the player reaches move_speed when pressing a direction.
## Higher = snappier start; lower = more "slidey" acceleration.
@export_range(100.0, 2000.0, 50.0) var acceleration: float = 800.0
## How quickly the player stops when no direction key is held.
## Higher = instant stop; lower = the character slides to a halt.
@export_range(100.0, 2000.0, 50.0) var friction: float = 1000.0

@export_group("Jump")
## Initial vertical velocity applied when the player jumps.
## Negative because Godot's Y-axis points downward (up = negative).
@export_range(-800.0, -50.0, 10.0, "suffix:px/s") var jump_force: float = -250.0
## Gravity multiplier while the player is rising AND holding the jump key.
## Values below 1.0 make the ascent hang longer for a floatier feel.
@export_range(0.1, 1.0, 0.05) var variable_jump_gravity_multiplier: float = 0.5
## Gravity multiplier once the player is falling (velocity.y > 0).
## Values above 1.0 make the player drop faster, reducing floatiness on descent.
@export_range(1.0, 4.0, 0.1) var fall_gravity_multiplier: float = 1.8
## Seconds after walking off a ledge during which the player can still jump.
## This "coyote time" forgives slightly-late jump inputs at ledge edges.
@export_range(0.0, 0.3, 0.01, "suffix:s") var coyote_time: float = 0.12
## Seconds before landing that a jump input is remembered and auto-triggered.
## This "jump buffer" forgives slightly-early jump inputs just before touching ground.
@export_range(0.0, 0.3, 0.01, "suffix:s") var jump_buffer_time: float = 0.10
## Gravity multiplier applied when the player holds Down while airborne.
## Higher values make fast-fall drop faster. 1.0 disables the effect entirely.
@export_range(1.0, 8.0, 0.1) var fast_fall_gravity_multiplier: float = 3.5
## Allow a second jump while airborne. Off by default — flip to true per-character to enable.
@export var double_jump_enabled: bool = false

## Horizontal speed while crawling. Slower than run — player is prone.
@export_range(20.0, 200.0, 5.0, "suffix:px/s") var crawl_speed: float = 80.0

@export_group("Health")
## Maximum number of hit points. Also sets how many hearts the HUD shows.
@export_range(1, 10, 1) var max_hp: int = 3
## Starting HP. Clamped to max_hp in _ready() so it can never exceed it.
@export_range(0, 10, 1) var current_hp: int = 3

@export_group("Wall")
## Maximum fall speed while sliding down a wall. Lower = stickier.
@export_range(10.0, 300.0, 5.0, "suffix:px/s") var wall_slide_speed: float = 60.0
## Fall speed when holding Down while wall-sliding — the fast-drop override.
@export_range(50.0, 600.0, 10.0, "suffix:px/s") var wall_slide_fast_speed: float = 230.0
## Horizontal push-off speed as a multiplier of move_speed when wall jumping.
@export_range(0.5, 2.0, 0.1) var wall_jump_x_multiplier: float = 1.5
## Seconds after leaving a wall slide during which jump still triggers a wall jump.
## Mirrors floor coyote time — forgives slightly-late inputs after releasing the wall.
@export_range(0.0, 0.3, 0.01, "suffix:s") var wall_coyote_time: float = 0.12
## Whether wall jumping resets the air dash counter.
@export var wall_jump_refreshes_dash: bool = false

@export_group("Ledge")
## Seconds after the ledge raycasts stop detecting a grabbable ledge during which
## the grab can still fire.  Mirrors floor coyote time — forgives the player drifting
## a frame or two past the ledge edge before the grab registers.
@export_range(0.0, 0.3, 0.01, "suffix:s") var ledge_coyote_time: float = 0.20
## Seconds after the ledge raycasts first detect a grabbable ledge during which
## the grab will fire the moment can_grip becomes true.  Forgives briefly exhausted
## stamina or an active cooldown at the exact frame the ledge is passed.
@export_range(0.0, 0.3, 0.01, "suffix:s") var ledge_grab_buffer_time: float = 0.15

@export_group("Stamina")
## Total stamina pool. Drains while climbing or hanging; refills when resting.
@export_range(0.0, 200.0, 5.0) var stamina_max: float = 90.0
## Stamina drained per second while actively climbing a wall.
@export_range(0.0, 50.0, 0.5, "suffix:units/s") var stamina_drain_wall_climb: float = 20.0
## Stamina drained per second during the LedgeHang entry animation.
@export_range(0.0, 50.0, 0.5, "suffix:units/s") var stamina_drain_ledge_hang: float = 8.0
## Stamina drained per second while idle-hanging on a ledge (LedgeHangIdle loop).
## Only applies when ledge_hang_idle_drains_stamina is true.
@export_range(0.0, 50.0, 0.5, "suffix:units/s") var stamina_drain_ledge_hang_idle: float = 4.0
## Stamina drained per second while hanging on a background hold (HANG_IDLE or HANG_MOVE).
@export_range(0.0, 50.0, 0.5, "suffix:units/s") var stamina_drain_hang: float = 6.0
## Stamina recovered per second while not gripping.
@export_range(0.0, 50.0, 0.5, "suffix:units/s") var stamina_regen_rate: float = 15.0
## Seconds of rest before stamina starts recovering after the last drain.
@export_range(0.0, 3.0, 0.1, "suffix:s") var stamina_regen_delay: float = 1.0
## Max upward speed when pressing jump while gripping a wall.
@export_range(0.0, 300.0, 5.0, "suffix:px/s") var wall_climb_speed: float = 120.0
## If false, LedgeHangIdle does not drain stamina — player can hang indefinitely.
@export var ledge_hang_idle_drains_stamina: bool = true
## Pixels to nudge the player upward the moment they grab a ledge.
## Increase to make the hands appear higher on the ledge edge.
@export_range(0.0, 32.0, 1.0, "suffix:px") var ledge_hang_snap_up: float = 0.0
## Extra pixels to drop the player down when grabbing a ledge while falling
## (velocity.y > 0).  Grabs from below are unaffected — this only shifts the
## snap point for the "dropped past a ledge" case so the hang reads lower.
@export_range(0.0, 20.0, 1.0, "suffix:px") var ledge_hang_fall_snap: float = 6.0
## Extra pixels to raise the player up when grabbing a ledge while rising
## (velocity.y < 0).  Grabs from above are unaffected — mirrors ledge_hang_fall_snap
## for the approach-from-below case so the hang reads higher on the ledge edge.
@export_range(0.0, 20.0, 1.0, "suffix:px") var ledge_hang_rise_snap: float = 0.0

# HoldGrabMode must be declared before the @export below uses it as a type.
# GDScript resolves @export type annotations at parse time — forward references fail.
enum HoldGrabMode {
	OVERLAP_THEN_PRESS,   # hold grip while overlapping a zone → grab
	PRESS_THEN_OVERLAP    # press grip first, then enter the zone → grab
}

@export_group("Background Holds")
## Set to false to disable the entire background-hold system with one toggle.
@export var background_holds_enabled: bool = true
## Determines when grabbing triggers — see HoldGrabMode enum for details.
@export var hold_grab_mode: HoldGrabMode = HoldGrabMode.OVERLAP_THEN_PRESS
## Horizontal speed while moving along a background hold.
@export_range(0.0, 300.0, 5.0, "suffix:px/s") var hang_move_speed: float = 80.0

@export_group("Exit")
## Speed applied in exit direction for top/bottom exits (px/s).
@export_range(0.0, 500.0, 10.0, "suffix:px/s") var exit_boost_speed: float = 200.0
## Speed applied for left/right exits (px/s).
@export_range(0.0, 500.0, 10.0, "suffix:px/s") var exit_horizontal_speed: float = 300.0

@export_group("Battle")
## When true, all player input is ignored. BattleManager controls movement.
## Set automatically by BattleManager.start_battle() — do not set manually.
@export var battle_locked: bool = false
## Pause between landing Punch01 and turning away to dash back.
## Tune for dramatic effect — longer = more weight, shorter = snappier.
@export_range(0.0, 2.0, 0.05, "suffix:s") var attack_pause_duration: float = 0.2

@export_group("Room Entry")
@export_range(0.0, 2.0, 0.1, "suffix:s") var entry_control_delay: float = 0.5
@export_range(10.0, 600.0, 5.0, "suffix:px/s") var entry_rise_speed: float = 30.0
## Speed of the north-entry "drag" tween from PlayerOneEmerge/TwoEmerge down to the
## spawn marker. Distance varies per room, so duration scales with this speed
## rather than being a fixed time.
@export_range(10.0, 800.0, 5.0, "suffix:px/s") var entry_descend_speed: float = 30.0
@export_range(0.0, 1.0, 0.05, "suffix:s") var p2_stagger_delay: float = 0.3

@export_group("Combat")
## Position of HitBox relative to player center. Positive x = forward (right-facing).
## Tune in Inspector to align with fist extension in Punch01 animation.
@export var hitbox_offset: Vector2 = Vector2(18, -5)
## Size of HitBox rectangle. Tune to match fist reach in Punch01.
@export var hitbox_size: Vector2 = Vector2(12, 10)
## Size of HurtBox rectangle. Should cover the player body.
@export var hurtbox_size: Vector2 = Vector2(16, 32)

@export_group("Respawn")
## Name of the Marker2D node in the room scene that marks this player's spawn point.
## P1 uses "PlayerOneSpawn", P2 uses "PlayerTwoSpawn".
## Set this in the Inspector per player instance in each room scene.
@export var spawn_marker_name: String = "PlayerOneSpawn"
## Seconds between the Hit animation finishing and teleporting to the spawn point.
@export_range(0.0, 2.0, 0.1, "suffix:s") var respawn_delay: float = 0.6
## If true, the player flickers briefly after teleporting to signal the respawn.
@export var flash_on_respawn: bool = true
## Pixels to pop upward the moment a spike is hit, before the Hit animation plays.
## Set to 0 to disable the bounce.
@export_range(0.0, 80.0, 1.0, "suffix:px") var respawn_bounce: float = 15.0

@export_group("Dash")
## Horizontal speed (px/s) during a dash — overrides normal movement entirely.
@export_range(100.0, 1200.0, 10.0, "suffix:px/s") var dash_speed: float = 380.0
## How long (in seconds) a single dash lasts before normal movement resumes.
@export_range(0.05, 0.5, 0.01, "suffix:s") var dash_duration: float = 0.12
## Cooldown (in seconds) between dashes so the player can't spam them.
@export_range(0.1, 2.0, 0.05, "suffix:s") var dash_cooldown: float = 0.6
## Allow dashing while airborne. Disable for a more grounded feel.
@export var air_dash_allowed: bool = true
## How many air dashes are available before landing is required to reset them.
@export_range(0, 5, 1) var air_dashes_allowed: int = 1

# ---------------------------------------------------------------------------
# STATE MACHINE
# ---------------------------------------------------------------------------
# An enum cleanly names each state so the rest of the code reads like English
# instead of magic numbers.
enum State { IDLE, RUN, JUMP, FALL, DASH, DUCK, CRAWL, WALL_SLIDE, WALL_CLIMB, LEDGE_HANG, LEDGE_CLIMB, HANG_IDLE, HANG_MOVE, HANG_EDGE, EXITING, BATTLE_ATTACK }

## The player's current state. Read-only from outside; set via _set_state().
var state: State = State.IDLE

# ---------------------------------------------------------------------------
# INTERNAL RUNTIME VARIABLES
# ---------------------------------------------------------------------------
# These are not exported because they change every frame — they are not
# designer-tunable constants.

## Cached base gravity from the Godot project settings (pixels/s²).
var _base_gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")

## Reference to the AnimatedSprite2D child — resolved automatically at scene ready.
@onready var _sprite             : AnimatedSprite2D = $AnimatedSprite2D
## Raycasts for automatic ledge detection — see PART 4 implementation notes.
@onready var _ledge_check_upper  : RayCast2D        = $LedgeCheckUpper
@onready var _ledge_check_lower  : RayCast2D        = $LedgeCheckLower
## Standing and crouching collision capsules.
## To tune crouch depth: adjust CapsuleShape2D_duck.height and
## CollisionShapeDuck.position.y in Player.tscn.
@onready var _collision_stand    : CollisionShape2D = $CollisionShape2D
@onready var _collision_duck     : CollisionShape2D = $CollisionShapeDuck
## Area2D that detects overlapping BackgroundHold zones.
## Collision mask = 2 matches BackgroundHold.HoldZone's collision_layer = 2.
@onready var _hold_detector      : Area2D           = $HoldDetector
@onready var _hit_box            : Area2D           = $HitBox
@onready var _hit_box_shape      : CollisionShape2D = $HitBox/HitBoxShape
@onready var _hurt_box           : Area2D           = $HurtBox

## Which horizontal direction the player is facing: +1 = right, -1 = left.
## Used when dashing with no directional input (dash "forward").
var _facing_direction: int = 1

# Coyote time — counts down from coyote_time after the player leaves the ground.
# While > 0 a jump is still permitted even though is_on_floor() is false.
var _coyote_timer: float = 0.0

# Jump buffer — counts down from jump_buffer_time when the jump key is pressed.
# If the player lands before it reaches zero, a jump fires automatically.
var _jump_buffer_timer: float = 0.0

# Dash state tracking.
var _dash_timer: float = 0.0       # counts down while a dash is active
var _dash_cooldown_timer: float = 0.0  # counts down between dashes
var _air_dashes_used: int = 0      # resets to 0 each time the player lands
var _dash_direction: float = 0.0   # horizontal direction of the current dash

# Tracks whether the player was on the floor last frame.
# Used to detect the exact frame of landing so we can reset air abilities.
var _was_on_floor: bool = false

# Double jump — consumed the frame it fires, restored when the player lands.
var _has_double_jumped: bool = false

# ---------------------------------------------------------------------------
# STAMINA
# ---------------------------------------------------------------------------
# Current stamina. Initialised to stamina_max in _ready().
var _stamina: float = 0.0

# Countdown before stamina starts regenerating after the last drain event.
var _stamina_regen_timer: float = 0.0

# Set true when stamina reaches 0. Blocks all gripping until stamina
# recovers to at least 25 % of stamina_max, preventing instant re-grab loops.
var _stamina_exhausted: bool = false

# World position recorded when LEDGE_HANG is entered.
# The player is locked here (velocity = 0) during the hang, and it is used
# to calculate the nudge-up offset when LedgeClimb finishes.
var _ledge_hang_position: Vector2 = Vector2.ZERO

# Counts down after leaving a ledge hang so the ledge raycasts can't
# immediately re-grab the same ledge on the very next frame.
var _ledge_grab_cooldown: float = 0.0

# Ledge coyote — mirrors _coyote_timer but for ledge detection.
# Fed fresh every frame the raycasts see a valid ledge; decays afterward.
# While > 0, a grab can fire even if the raycasts no longer hit.
var _ledge_coyote_timer: float = 0.0

# Ledge grab buffer — set whenever raycasts see a valid ledge.
# While > 0, the grab fires the moment can_grip becomes true, even if the
# raycasts have since lost sight of the ledge.
var _ledge_grab_buffer_timer: float = 0.0

# Player Y recorded every frame the ledge raycasts detect a valid ledge.
# Used to snap to the correct hang height even when the grab fires during
# the coyote or buffer window (when the player has drifted below detection).
var _ledge_detected_y: float = 0.0

# ---------------------------------------------------------------------------
# BACKGROUND HOLDS
# ---------------------------------------------------------------------------
# The BackgroundHold node the player is currently hanging from, or null.
var _current_hold      : Node  = null

# The HoldType of the current hold (cached from _current_hold.hold_type on grab).
# Stored as int so Player.gd doesn't depend on BackgroundHold's enum at runtime.
# -1 = no hold.
var _current_hold_type : int   = -1

# All BackgroundHold zones currently overlapping HoldDetector.
# Populated by _on_hold_area_entered / _on_hold_area_exited.
var _overlapping_holds : Array = []

# Used by PRESS_THEN_OVERLAP mode: set true when grip is pressed in open air,
# cleared when grip is released.  A zone entry while this is true grabs immediately.
var _grip_pressed_before_overlap : bool = false

# Which edge the player is hanging from in HANG_EDGE: +1 = right, -1 = left.
var _hang_edge_dir: int = 0

# Counts down after the player drops off the end of a hold.
# Blocks _try_grab_hold() so the player can't immediately re-grab the same
# hold before move_and_slide() has had a chance to move them out of the zone.
var _hold_grab_cooldown : float = 0.0

# Counts down after WALL_CLIMB drops to FALL (not via a wall jump).
# Prevents the rapid re-grab oscillation when the player overshoots a
# platform edge — the brief window also lets ledge detection fire so the
# player can pull themselves up with the up input instead.
var _wall_climb_cooldown : float = 0.0

# The platform velocity that was added to `velocity` last frame.
# Stripped out before state processing so friction only acts on the
# player-controlled portion of velocity, then re-added after.
var _platform_velocity: Vector2 = Vector2.ZERO

# Wall coyote time — counts down after the player leaves a wall slide.
# While > 0 a wall jump is still permitted even though is_on_wall() is false.
# Mirrors _coyote_timer exactly, but for walls instead of floors.
var _wall_coyote_timer: float = 0.0

# Last wall normal captured while wall-sliding.
# Preserved so _start_wall_jump() can use the correct push direction during
# the coyote window, when is_on_wall() is no longer true.
var _last_wall_normal: Vector2 = Vector2.ZERO

# Set true during the full respawn sequence (Hit animation → pause → teleport).
# Guards trigger_respawn() so multiple overlapping spike HitZones can't stack
# respawn calls on the same frame.
var _is_respawning: bool = false

# Set true when the player is defeated in battle (HP reaches 0).
# Guards receive_hit() against double-hits on a downed player.
# Cleared by battle_end_reset() when the battle ends.
var _is_downed: bool = false

# Set by BattleManager during the battle intro walk-in.
# -1 = walk left, 1 = walk right, 0 = stopped.
var _battle_walk_direction: int = 0
# Stored before teleporting so the player returns to the right spot after attacking.
var _pre_attack_position: Vector2 = Vector2.ZERO
# The enemy node being attacked this sequence.
var _attack_target: Node2D = null
# Damage value passed from BattleManager for the current attack.
# FUTURE — damage calculation: base + attack stat + weapon bonus +
# action command timing bonus - target defense. Minimum 1 always.
var _attack_damage: int = 1

var _exit_direction: Vector2 = Vector2.ZERO
var _is_exiting: bool = false
# While > 0, spikes cannot trigger respawn (grace period after room entry).
var _invincible_timer: float = 0.0
var _entry_direction: String = ""
# Path2D traced in the editor for the current room-entry cutscene (if any).
var _entry_path: Path2D = null
# Global-space polyline sampled from _entry_path for the current entry.
var _entry_path_points: Array[Vector2] = []


# ---------------------------------------------------------------------------
# READY
# ---------------------------------------------------------------------------
func _ready() -> void:
	# If this is Player 2 and single player mode is on, disable entirely.
	# P2 removes itself from "players" so all other systems work automatically
	# without any special-casing — they just see one fewer player in the group.
	# FUTURE — ghost/AI mode for P2: instead of disabling entirely,
	#   P2 could be AI controlled in single player mode.
	if player_id == 2 and GameManager.is_single_player():
		visible = false
		set_physics_process(false)
		set_process(false)
		$CollisionShape2D.disabled = true
		# Do not add to the players group — all group-based systems will
		# ignore this node automatically. If already added, remove now.
		remove_from_group("players")
		# FUTURE — could spawn P2 mid game if a second player joins later:
		#   re-enable visible, physics, collision, and add_to_group("players")
		return

	add_to_group("players")  # lets RoomManager, RoomCamera, and HUD find all players
	modulate = player_color  # apply co-op tint to the entire node (sprite + children)
	# Keep the player pressed against a downward-moving platform.
	# Without this, when a platform dips faster than gravity pulls the player
	# down, is_on_floor() goes false for one frame — triggering a FALL state
	# flicker and resetting coyote time even though the player is still riding.
	# 20 px gives a buffer of ~7 frames at 160 px/s (MovingPlatformSimple peak),
	# covering the case where the carry velocity is detected one or two frames
	# late.  Snap does not apply while jumping (velocity.y < 0) so it won't
	# prevent the player from leaving the floor normally.
	floor_snap_length = 20.0
	_sprite.play("Idle")
	_sprite.animation_finished.connect(_on_animation_finished)
	_stamina = stamina_max   # start every session with a full stamina bar
	# Clamp current_hp in case the Inspector value was set above max_hp,
	# then emit so the HUD initialises correctly the moment it connects.
	current_hp = clampi(current_hp, 0, max_hp)
	hp_changed.emit(current_hp, max_hp)
	# Connect HoldDetector so the player knows when it overlaps a hold zone.
	# area_entered / area_exited fire when a BackgroundHold.HoldZone (Area2D)
	# enters or leaves the player's detection area.
	_hold_detector.area_entered.connect(_on_hold_area_entered)
	_hold_detector.area_exited.connect(_on_hold_area_exited)
	# HitBox: only active during Punch01, never at rest.
	_hit_box.monitoring  = false
	_hit_box.monitorable = false
	_hit_box.collision_layer = 4
	_hit_box.collision_mask  = 4
	# HurtBox: disabled outside battle — BattleManager.start_battle() enables it.
	_hurt_box.monitoring  = false
	_hurt_box.monitorable = false
	_hurt_box.collision_layer = 4
	_hurt_box.collision_mask  = 4
	# _spawn_point is resolved lazily in trigger_respawn() so the room is
	# guaranteed to be loaded when we look up the marker.
	# Wait one frame so all players have added themselves to the "players" group,
	# then exclude them from ledge raycasts so players can't grab each other.
	await get_tree().process_frame
	for node in get_tree().get_nodes_in_group("players"):
		if node == self:
			continue
		_ledge_check_upper.add_exception(node as CollisionObject2D)
		_ledge_check_lower.add_exception(node as CollisionObject2D)

# ---------------------------------------------------------------------------
# PHYSICS PROCESS  (runs every physics tick, typically 60 Hz)
# ---------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	# --- Read this frame's input into a tidy local variable ---
	var input := _get_input()

	# Snapshot floor state from the END of last frame (after last move_and_slide).
	# We compare this against is_on_floor() AFTER this frame's move_and_slide to
	# detect the exact frame of landing. Checking before move_and_slide would give
	# the same value as _was_on_floor since is_on_floor() hasn't updated yet.
	var floor_last_frame := _was_on_floor

	# --- Tick all timers and stamina ---
	_tick_timers(delta)
	_tick_stamina(delta)

	# --- Background hold grab logic ---
	# OVERLAP_THEN_PRESS: grab whenever grip is held while inside a hold zone.
	if background_holds_enabled \
			and hold_grab_mode == HoldGrabMode.OVERLAP_THEN_PRESS \
			and _grip_held \
			and not _overlapping_holds.is_empty() \
			and _hold_grab_cooldown <= 0.0 \
			and state != State.HANG_IDLE and state != State.HANG_MOVE \
			and state != State.HANG_EDGE:
		_try_grab_hold()

	# PRESS_THEN_OVERLAP: track whether grip was pressed before entering a zone.
	if hold_grab_mode == HoldGrabMode.PRESS_THEN_OVERLAP:
		if _grip_just_pressed:
			_grip_pressed_before_overlap = true
		elif not _grip_held:
			_grip_pressed_before_overlap = false

	# Strip last frame's HORIZONTAL platform contribution before state processing.
	# Friction slides velocity.x toward 0 each frame — if the platform's horizontal
	# speed is still baked in, friction fights it and the player slowly slides
	# backward on a horizontal platform.  Stripping only .x lets friction act on
	# the player-controlled portion without touching vertical velocity.
	#
	# WHY only .x and not .y:
	#   Vertical carry never accumulates — move_and_slide() zeroes velocity.y the
	#   moment the player touches the floor each frame, so there is nothing to undo.
	#   Stripping .y was the source of the duck-on-descending-platform FALL bug:
	#   if get_collider_velocity() returned zero one frame (intermittent detection),
	#   the strip removed last frame's large downward value with nothing re-added,
	#   producing a large upward velocity spike.  Godot disables floor_snap_length
	#   when velocity.y < 0, so the snap never fired and is_on_floor() went false.
	velocity.x -= _platform_velocity.x

	# --- Run the logic for whichever state is currently active ---
	match state:
		State.IDLE, State.RUN:
			_process_ground(input, delta)
		State.DUCK:
			_process_duck(input, delta)
		State.CRAWL:
			_process_crawl(input, delta)
		State.JUMP, State.FALL:
			_process_air(input, delta)
		State.WALL_SLIDE:
			_process_wall_slide(input, delta)
		State.WALL_CLIMB:
			_process_wall_climb(input, delta)
		State.LEDGE_HANG:
			_process_ledge_hang(input, delta)
		State.LEDGE_CLIMB:
			_process_ledge_climb(input, delta)
		State.HANG_IDLE:
			_process_hang_idle(input, delta)
		State.HANG_MOVE:
			_process_hang_move(input, delta)
		State.HANG_EDGE:
			_process_hang_edge(input, delta)
		State.DASH:
			_process_dash(input, delta)
		State.EXITING:
			_process_exiting(delta)
		State.BATTLE_ATTACK:
			# All physics and input suspended during the attack sequence.
			# BattleManager drives everything — _do_attack_sequence() controls
			# the full choreography via await.
			velocity = Vector2.ZERO

	# Carry the player when attached to a moving platform surface.
	#
	# WHY this is needed:
	#   Godot 4 does NOT automatically move CharacterBody2D with a moving body.
	#   We must read the colliding body's velocity and add it ourselves.
	#   get_collider_velocity() reads the velocity the physics server computed
	#   from the AnimatableBody2D's position delta (sync_to_physics = true).
	#
	# WHY limited to surface-attached states:
	#   During JUMP / FALL the player may briefly graze a moving platform.
	#   Applying that body's velocity mid-air would feel like a random kick.
	#   We only carry in states where the player is intentionally gripping or
	#   standing on a surface.
	#
	# WHY here (after state processing, before move_and_slide):
	#   State functions set the player's own velocity (friction, gravity, climb
	#   speed, etc.).  Adding platform velocity AFTER that preserves it fully —
	#   friction only ever acts on the player-controlled portion.
	_platform_velocity = Vector2.ZERO

	var _is_surface_attached := (
		_was_on_floor          or   # IDLE / RUN / DUCK / CRAWL / DASH on ground
		state == State.WALL_CLIMB  or
		state == State.WALL_SLIDE  or
		state == State.LEDGE_HANG  or
		state == State.LEDGE_CLIMB
	)

	if _is_surface_attached:
		# --- Slide-collision path (floor + wall states) ---
		# get_slide_collision() returns hits from the PREVIOUS frame's
		# move_and_slide().  Wall states press into the wall each frame
		# (velocity.x = facing * 20) so there is always a fresh wall hit here.
		# We take the first collision whose collider has a non-zero velocity.
		for i in get_slide_collision_count():
			var col_vel := get_slide_collision(i).get_collider_velocity()
			if col_vel != Vector2.ZERO:
				_platform_velocity = col_vel
				break

		# --- Raycast fallback (LEDGE_HANG and LEDGE_CLIMB) ---
		# These states hold velocity at Vector2.ZERO, so move_and_slide()
		# produces no collisions and the loop above finds nothing.
		# LedgeCheckLower already points at the exact wall the player grabbed;
		# if that body is a MovingPlatform we read its public velocity directly.
		if _platform_velocity == Vector2.ZERO \
				and (state == State.LEDGE_HANG or state == State.LEDGE_CLIMB):
			var ledge_body := _ledge_check_lower.get_collider()
			if ledge_body is MovingPlatform:
				_platform_velocity = (ledge_body as MovingPlatform).velocity

	# When standing on a floor, the platform moving UP is already handled by
	# physics overlap resolution — the platform rises into the player's feet
	# and Godot pushes the player up automatically.  If we ALSO add upward
	# velocity here, the player lifts off the floor before physics resolves
	# the overlap, is_on_floor() goes false, and FALL / DUCK-glitch triggers.
	# Clamp to zero-or-down so we only carry the player when the floor drops
	# away (downward platform movement that gravity alone can't track).
	# Wall and ledge states keep the full velocity — they need both axes.
	if _was_on_floor:
		_platform_velocity.y = maxf(_platform_velocity.y, 0.0)

	velocity += _platform_velocity

	# --- Apply the final velocity to the CharacterBody2D ---
	move_and_slide()

	if state == State.EXITING:
		_check_exit_offscreen()

	# --- Detect landing now that is_on_floor() reflects this frame's collisions ---
	if is_on_floor() and not floor_last_frame:
		_on_landed()

	# --- Update facing direction and flip sprite to match ---
	# Locked during ledge hang/climb AND background hang states.
	# Back-view Climb animations look correct regardless of direction,
	# so we freeze flip_h to prevent a jarring mirror on direction change.
	var ledge_locked := (state == State.LEDGE_HANG or state == State.LEDGE_CLIMB
						 or state == State.HANG_IDLE or state == State.HANG_MOVE
						 or state == State.HANG_EDGE or state == State.EXITING
						 or state == State.BATTLE_ATTACK)
	if state == State.HANG_EDGE:
		# ClimbJumpPrepare is a single animation — flip it for the right edge.
		_sprite.flip_h = (_hang_edge_dir == -1)
	else:
		if input.x != 0 and not ledge_locked:
			_facing_direction = int(sign(input.x))
		# Only auto-update flip when not in a locked state. Locked states
		# (BATTLE_ATTACK, EXITING, ledge/hang) manage flip_h themselves.
		if not ledge_locked:
			_sprite.flip_h = _facing_direction == -1

	# --- Update ledge detection raycasts ---
	# Always cast toward the direction the player is currently facing.
	# force_raycast_update() re-evaluates the ray immediately so that
	# _update_state() reads fresh results on this same frame.
	var cast_x := float(_facing_direction) * 12.0
	_ledge_check_upper.target_position.x = cast_x
	_ledge_check_lower.target_position.x = cast_x
	_ledge_check_upper.force_raycast_update()
	_ledge_check_lower.force_raycast_update()

	# --- Determine what state we should be in next frame ---
	_update_state()

	# --- Remember floor status for next frame's landing detection ---
	_was_on_floor = is_on_floor()

# ---------------------------------------------------------------------------
# INPUT HELPER
# Returns a Vector2 where:
#   x = horizontal axis (-1 left, 0 none, +1 right)
#   y is unused for movement but kept as Vector2 for future extension
# Also stores jump / dash pressed flags read from the correct player's keys.
# ---------------------------------------------------------------------------
## Cached this-frame input flags — set inside _get_input(), read elsewhere.
var _input_x: float = 0.0
var _jump_pressed: bool = false
var _jump_held: bool = false
var _dash_pressed: bool = false
var _down_held: bool = false
## Grip button — universal "maintain contact" action (p1_r1 / p2_r1).
## Used for wall climbing, ledge hanging, background holds, and future interactions.
var _grip_held: bool = false
## True only on the frame grip is first pressed — used by PRESS_THEN_OVERLAP mode.
var _grip_just_pressed: bool = false
## Dedicated up input (p1_up / p2_up).
## Used to climb up a wall and to pull up from a ledge hang.
## Kept separate from jump so up and jump can be used interchangeably
## in normal movement without accidentally triggering climb/pull-up.
var _up_pressed: bool = false
var _up_held: bool    = false

func _get_input() -> Vector2:
	# When battle_locked, ignore all player input.
	# BattleManager drives movement via battle_walk() / battle_stop() instead.
	if battle_locked:
		_jump_pressed      = false
		_jump_held         = false
		_dash_pressed      = false
		_down_held         = false
		_grip_held         = false
		_grip_just_pressed = false
		_up_pressed        = false
		_up_held           = false
		_input_x           = float(_battle_walk_direction)
		return Vector2(float(_battle_walk_direction), 0.0)

	var dir := Vector2.ZERO

	if player_id == 1:
		if Input.is_action_pressed("p1_right"):      dir.x += 1
		if Input.is_action_pressed("p1_left"):       dir.x -= 1
		_jump_pressed = Input.is_action_just_pressed("p1_cross")
		_jump_held    = Input.is_action_pressed("p1_cross")
		_dash_pressed = Input.is_action_just_pressed("p1_circle")
		_down_held    = Input.is_action_pressed("p1_down")
		_grip_held         = Input.is_action_pressed("p1_r1")
		_grip_just_pressed = Input.is_action_just_pressed("p1_r1")
		_up_pressed        = Input.is_action_just_pressed("p1_up")
		_up_held           = Input.is_action_pressed("p1_up")
	else:
		if Input.is_action_pressed("p2_right"):      dir.x += 1
		if Input.is_action_pressed("p2_left"):       dir.x -= 1
		_jump_pressed      = Input.is_action_just_pressed("p2_cross")
		_jump_held         = Input.is_action_pressed("p2_cross")
		_dash_pressed      = Input.is_action_just_pressed("p2_circle")
		_down_held         = Input.is_action_pressed("p2_down")
		_grip_held         = Input.is_action_pressed("p2_r1")
		_grip_just_pressed = Input.is_action_just_pressed("p2_r1")
		_up_pressed        = Input.is_action_just_pressed("p2_up")
		_up_held           = Input.is_action_pressed("p2_up")

	_input_x = dir.x
	return dir

# ---------------------------------------------------------------------------
# GROUND MOVEMENT
# Handles horizontal acceleration / friction and jump initiation while grounded.
# ---------------------------------------------------------------------------
func _process_ground(input: Vector2, delta: float) -> void:
	# --- Horizontal movement with acceleration and friction ---
	if input.x != 0:
		# Accelerate toward the target speed using move_toward so we never
		# overshoot. multiply by delta to keep movement framerate-independent.
		velocity.x = move_toward(velocity.x, input.x * move_speed, acceleration * delta)
	else:
		# No input — apply friction to slow to a stop.
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)

	# Gravity still applies on the ground to keep the player pressed to slopes.
	velocity.y += _base_gravity * delta

	# --- Jump (normal press OR jump buffer firing on landing) ---
	if _jump_pressed or _jump_buffer_timer > 0.0:
		_start_jump()

	# --- Dash ---
	if dash_enabled and _dash_pressed and _dash_cooldown_timer <= 0.0:
		_start_dash(input.x)

	# --- Look Up ---
	# Only while idle on the ground with no horizontal input.
	# The animation is non-looping so it plays through and freezes on the last
	# frame while up is held — releasing up returns to the Idle loop.
	if _up_held and input.x == 0:
		if _sprite.animation != &"LookUp":
			_sprite.play("LookUp")
	elif _sprite.animation == &"LookUp":
		_sprite.play("Idle")

# ---------------------------------------------------------------------------
# DUCK
# Player is crouched on the ground. Horizontal movement is suppressed.
# Jump input still fires a jump. Exiting back to IDLE is handled entirely
# by _update_state() after move_and_slide() — NOT here.
#
# WHY the exit is not done here:
#   Calling _set_state(IDLE) mid-frame swaps the collision capsule from the
#   short duck shape to the taller standing shape BEFORE move_and_slide()
#   runs.  On a downward-moving platform the standing capsule's bottom sits
#   above the platform surface (the floor drifted a few pixels this frame),
#   so move_and_slide() sees no floor contact, is_on_floor() returns false,
#   and _update_state() triggers a one-frame FALL.
#   Leaving the capsule swap to _update_state() (which runs after
#   move_and_slide()) means the duck capsule is always active when the player
#   touches the floor, so contact is never lost during the transition.
# ---------------------------------------------------------------------------
func _process_duck(input: Vector2, _delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, friction * _delta)
	velocity.y += _base_gravity * _delta

	# Only allow jumping if there is ceiling clearance to stand up.
	# Mirrors the _update_state() stand-up guard: if the player can't stand,
	# they can't jump either — you can't launch into a ceiling you're pinned under.
	if (_jump_pressed or _jump_buffer_timer > 0.0) and _can_stand():
		_start_jump()

# ---------------------------------------------------------------------------
# CRAWL MOVEMENT
# Player is prone and moving horizontally while holding down + a direction.
# Slower than running. Releasing down or direction exits back to duck/idle.
# ---------------------------------------------------------------------------
func _process_crawl(input: Vector2, delta: float) -> void:
	velocity.x = move_toward(velocity.x, input.x * crawl_speed, acceleration * delta)
	velocity.y += _base_gravity * delta
	if _jump_pressed or _jump_buffer_timer > 0.0:
		_start_jump()

# ---------------------------------------------------------------------------
# WALL SLIDE
# Player is falling against a wall. Gravity is heavily reduced so the player
# drifts down slowly. Jump input while sliding fires a wall jump.
# ---------------------------------------------------------------------------
func _process_wall_slide(_input: Vector2, delta: float) -> void:
	# Gentle press into the wall so contact is maintained each frame.
	velocity.x = float(_facing_direction) * 20.0
	# Cache the wall normal every frame so _start_wall_jump() can use it
	# during the coyote window after the player has left the wall.
	if is_on_wall():
		_last_wall_normal = get_wall_normal()
	# Holding Down fast-drops; otherwise drift slowly.
	if _down_held:
		velocity.y = move_toward(velocity.y, wall_slide_fast_speed, _base_gravity * 0.4 * delta)
	else:
		velocity.y = move_toward(velocity.y, wall_slide_speed, _base_gravity * 0.15 * delta)

	if _jump_pressed:
		_start_wall_jump()

# ---------------------------------------------------------------------------
# WALL CLIMB
# Player grips the wall (grip button held) and can move up or down.
# Hold jump to climb up, hold down to descend, neither to cling still.
# Stamina drains per second; hitting 0 forces an immediate drop with knockback.
# ---------------------------------------------------------------------------
func _process_wall_climb(input: Vector2, delta: float) -> void:
	# Press into the wall. Boost the press if the platform is moving opposite
	# to the facing direction so the platform carry can't overcome the grip.
	# After carry: net = facing*(|pv|+20) + pv = facing*20 regardless of pv.
	var wall_press := float(_facing_direction) * 20.0
	if _platform_velocity.x * float(_facing_direction) < 0.0:
		wall_press = float(_facing_direction) * (abs(_platform_velocity.x) + 20.0)
	velocity.x = wall_press

	# Cache the wall normal every frame — same pattern as _process_wall_slide.
	# This ensures _start_wall_jump() has a valid normal even if contact is lost
	# on the exact frame the jump fires.
	if is_on_wall():
		_last_wall_normal = get_wall_normal()

	# Jump while gripping the wall — delegates entirely to _start_wall_jump(),
	# the same function used by wall slide.  It handles the launch velocity,
	# WallJump animation, double-jump refresh, and coyote timer reset.
	# Stamina drain stops naturally because _tick_stamina() checks state, and
	# _start_wall_jump() sets state = JUMP before the next tick runs.
	if _jump_pressed:
		_start_wall_jump()
		return

	# Move up while up is held, down while down is held, or stay put.
	# Use test_move to detect ceiling rather than is_on_ceiling() — the latter
	# flip-flops every other frame because it requires upward velocity to register,
	# causing the player to keep pushing through the ceiling in alternating frames.
	if _up_held:
		velocity.y = 0.0 if test_move(global_transform, Vector2(0.0, -8.0)) else -wall_climb_speed
	elif _down_held:
		velocity.y = wall_slide_speed   # descend at the normal slide speed
	else:
		velocity.y = 0.0

	# Switch between moving and idle animations without restarting every frame.
	# This mirrors the _facing_direction flip pattern: only play when changed.
	if velocity.y != 0.0:
		if _sprite.animation != &"WallClimb":
			_sprite.play("WallClimb")
	else:
		if _sprite.animation != &"WallClimbIdle":
			_sprite.play("WallClimbIdle")

	# Grip released voluntarily — drop away from the wall.
	if not _grip_held:
		_set_state(State.FALL)
		return

	# Exhaustion: _stamina_exhausted is set by _tick_stamina() when _stamina hits 0.
	# Push the player away from the wall so they don't immediately re-grab.
	if _stamina_exhausted:
		velocity.x = _last_wall_normal.x * 80.0
		velocity.y = 50.0
		_set_state(State.FALL)

# ---------------------------------------------------------------------------
# LEDGE HANG
# Automatic ledge grab — no grip button needed.
# The player freezes in place (zero velocity, zero gravity) and plays the
# LedgeHang entry animation.  _on_animation_finished then loops LedgeHangIdle.
# Jump → LEDGE_CLIMB.  Down or stamina empty → FALL.
# ---------------------------------------------------------------------------
func _process_ledge_hang(_input: Vector2, _delta: float) -> void:
	# Press very slightly toward the wall so move_and_slide() generates
	# a wall collision every frame.  Without this, velocity is zero and
	# no collision is recorded — the carry code's get_collider_velocity()
	# loop finds nothing and the player doesn't move with the platform.
	# 4 px/s is imperceptible; the wall collision cancels it immediately.
	velocity = Vector2(float(_facing_direction) * 4.0, 0.0)

	if _jump_pressed:
		# Wall jump away from the ledge. _last_wall_normal is cached from the
		# wall contact that preceded the hang; fall back to facing direction if
		# somehow zero (e.g. player jumped directly onto the ledge).
		if _last_wall_normal == Vector2.ZERO:
			_last_wall_normal = Vector2(-float(_facing_direction), 0.0)
		_ledge_grab_cooldown = 0.25
		_start_wall_jump()
		return

	elif _up_pressed or _up_held:
		# Check for a real ceiling by sweeping the standing capsule straight up 39px.
		# The original check tested a forward+upward destination position, which put
		# the capsule partially inside the wall the player is hanging on — any ledge
		# that is part of a continuous wall falsely reported "blocked" and silently
		# swallowed the input.  A straight-up sweep avoids the side wall entirely
		# (moving up does not intersect a vertical surface beside the player) and
		# correctly detects only horizontal ceilings directly overhead.
		# Moving platforms are bypassed: their surface shows up in the upward sweep
		# but is the thing the player is climbing onto, not a blocking ceiling.
		var hanging_body := _ledge_check_lower.get_collider()
		var on_moving_platform := hanging_body is AnimatableBody2D
		if on_moving_platform or not test_move(global_transform, Vector2(0.0, -39.0)):
			_ledge_hang_position = global_position   # save for climb-up offset
			# Block re-grab for a moment after the climb finishes.
			# Without this, _update_state() runs the frame LEDGE_CLIMB ends,
			# the ledge raycasts may still see the edge, and the coyote/buffer
			# timers haven't expired — so the grab fires again immediately,
			# leaving the player hanging off thin air above the platform.
			_ledge_grab_cooldown = 0.5
			_set_state(State.LEDGE_CLIMB)

	elif _down_held and _grip_held and not _stamina_exhausted:
		# Down + grip while hanging → re-enter wall climb to descend.
		# A short cooldown prevents the ledge raycasts from immediately
		# re-grabbing the same ledge on the next frame.
		_ledge_grab_cooldown = 0.25
		_set_state(State.WALL_CLIMB)

	elif _down_held or _stamina_exhausted:
		# Down without grip, or stamina exhausted → drop off the ledge.
		velocity.y = 80.0
		_ledge_grab_cooldown = 0.25   # still block re-grab while falling past
		_set_state(State.FALL)

# ---------------------------------------------------------------------------
# LEDGE CLIMB
# Player is pulling themselves up over the ledge.
# The animation runs to completion; _on_animation_finished handles the state
# transition and positions the player on top of the surface.
# ---------------------------------------------------------------------------
func _process_ledge_climb(_input: Vector2, _delta: float) -> void:
	velocity = Vector2.ZERO   # stay frozen while the climb animation plays

# ---------------------------------------------------------------------------
# HANG IDLE  (gripping a background hold, not moving laterally)
# Player floats in place at the hold position.  Stamina drains via _tick_stamina.
# Grip release → FALL.  Jump → launch straight up.  Horizontal input → HANG_MOVE.
# Stamina exhaustion → FALL with a downward boost.
# ---------------------------------------------------------------------------
func _process_hang_idle(_input: Vector2, _delta: float) -> void:
	velocity = Vector2.ZERO   # freeze in place — no gravity on a hold

	if _stamina_exhausted:
		# Grip gave out — drop the player off the hold.
		_release_hold()
		velocity.y = 80.0
		_set_state(State.FALL)
		return

	if _down_held:
		_release_hold()
		_hold_grab_cooldown = 0.15
		_set_state(State.FALL)
		return

	if not _grip_held:
		# Player let go of the grip button voluntarily.
		_release_hold()
		_set_state(State.FALL)
		return

	if _jump_pressed:
		# Bar jump — directional kick based on held input, straight up if neutral.
		# Mirrors wall jump: _last_wall_normal.x drives the horizontal launch via
		# _start_wall_jump(), so ±1 gives the same kick as leaving a wall.
		_release_hold()
		_hold_grab_cooldown = 0.25   # prevent re-grab before player clears the zone
		_last_wall_normal = Vector2(_input_x, 0.0)
		_start_wall_jump()
		return

	if _input_x != 0.0:
		_set_state(State.HANG_MOVE)

# ---------------------------------------------------------------------------
# HANG MOVE  (gripping a background hold, moving laterally)
# Moves along the hold width, clamped to ± hold_width/2 from the hold centre.
# Uses ClimbLeft / ClimbRight animations based on direction.
# Same release conditions as HANG_IDLE.
# ---------------------------------------------------------------------------
func _process_hang_move(input: Vector2, _delta: float) -> void:
	if _current_hold == null:
		# Hold disappeared — fall cleanly.
		_set_state(State.FALL)
		return

	# If the player is pressing past either end of the hold, drop them.
	var bh := _current_hold as BackgroundHold
	if bh:
		var half := bh.hold_width * 0.5
		var cx   := bh.global_position.x
		var at_edge := (global_position.x <= cx - half and input.x < 0.0) \
					or (global_position.x >= cx + half and input.x > 0.0)
		if at_edge:
			_hang_edge_dir = int(sign(input.x))
			_set_state(State.HANG_EDGE)
			return
		global_position.x = clampf(global_position.x, cx - half, cx + half)

	velocity.x = input.x * hang_move_speed
	velocity.y = 0.0   # no gravity while hanging

	# Play the correct back-view animation — no sprite flip in HANG states.
	# FUTURE — when HoldType.ROPE is active, use MonkeyBarsClimb here instead.
	# See BackgroundHold.HoldType.ROPE for context.
	if input.x < 0.0:
		if _sprite.animation != &"ClimbLeft":
			_sprite.play("ClimbLeft")
	elif input.x > 0.0:
		if _sprite.animation != &"ClimbRight":
			_sprite.play("ClimbRight")

	if _stamina_exhausted:
		_release_hold()
		velocity.y = 80.0
		_set_state(State.FALL)
		return

	if _down_held:
		_release_hold()
		_hold_grab_cooldown = 0.15
		_set_state(State.FALL)
		return

	if not _grip_held:
		_release_hold()
		_set_state(State.FALL)
		return

	if _jump_pressed:
		_release_hold()
		_hold_grab_cooldown = 0.25
		_last_wall_normal = Vector2(_input_x, 0.0)
		_start_wall_jump()
		return

	if _input_x == 0.0:
		_set_state(State.HANG_IDLE)

# ---------------------------------------------------------------------------
# HANG EDGE  (player has reached the end of a background hold)
# Freezes at the edge and plays ClimbJumpPrepare while the player keeps
# pressing into the edge.  Jump fires a directional bar jump.
# Releasing the direction returns to HANG_MOVE / HANG_IDLE.
# Releasing grip or stamina exhaustion drops the player.
# ---------------------------------------------------------------------------
func _process_hang_edge(_input: Vector2, _delta: float) -> void:
	velocity = Vector2.ZERO   # stay frozen at the edge

	if _stamina_exhausted:
		_release_hold()
		velocity.y = 80.0
		_set_state(State.FALL)
		return

	if _down_held:
		_release_hold()
		_hold_grab_cooldown = 0.15
		_set_state(State.FALL)
		return

	if not _grip_held:
		_release_hold()
		_set_state(State.FALL)
		return

	if _jump_pressed:
		# Launch in the edge direction — same kick as a wall jump.
		_release_hold()
		_hold_grab_cooldown = 0.25
		_last_wall_normal = Vector2(float(_hang_edge_dir), 0.0)
		_start_wall_jump()
		return

	# Player released or reversed direction — leave edge state.
	if _input_x == 0.0:
		_set_state(State.HANG_IDLE)
	elif int(sign(_input_x)) != _hang_edge_dir:
		_set_state(State.HANG_MOVE)

# ---------------------------------------------------------------------------
# TRY GRAB HOLD
# Called when grab conditions are met (overlap + correct input mode).
# Snaps the player 20 px below the hold centre and enters HANG_IDLE.
# ---------------------------------------------------------------------------
func _try_grab_hold() -> void:
	if not background_holds_enabled:
		return
	if _overlapping_holds.is_empty():
		return
	if _stamina_exhausted or _stamina <= 0.0:
		return

	# Grab the first overlapping hold zone and get the BackgroundHold parent.
	var hold_area := _overlapping_holds[0] as Area2D
	_current_hold      = hold_area.get_parent()   # BackgroundHold Node2D
	var bh := _current_hold as BackgroundHold
	if bh:
		_current_hold_type = bh.hold_type         # cache for future ROPE logic

	# No position snap — the player freezes at their current Y.
	# Setting global_position inside _physics_process can confuse Area2D overlap
	# detection, causing a spurious area_exited → release → re-grab loop.
	velocity = Vector2.ZERO
	_set_state(State.HANG_IDLE)

# ---------------------------------------------------------------------------
# RELEASE HOLD
# Clears hold tracking and starts the stamina regen delay.
# The caller is responsible for setting the new state (FALL, JUMP, etc.).
# ---------------------------------------------------------------------------
func _release_hold() -> void:
	_current_hold      = null
	_current_hold_type = -1
	# Start regen delay so stamina doesn't recover instantly after dropping.
	_stamina_regen_timer = stamina_regen_delay

# ---------------------------------------------------------------------------
# HOLD DETECTOR CALLBACKS
# Fired by HoldDetector (Area2D) when it overlaps a BackgroundHold.HoldZone.
# ---------------------------------------------------------------------------

func _on_hold_area_entered(area: Area2D) -> void:
	# Only care about areas that belong to background holds.
	if not area.is_in_group("background_holds"):
		return

	_overlapping_holds.append(area)

	# PRESS_THEN_OVERLAP: if grip was pressed before entering this zone, grab now.
	if background_holds_enabled \
			and hold_grab_mode == HoldGrabMode.PRESS_THEN_OVERLAP \
			and _grip_pressed_before_overlap \
			and state != State.HANG_IDLE and state != State.HANG_MOVE \
			and state != State.HANG_EDGE:
		_try_grab_hold()

func _on_hold_area_exited(area: Area2D) -> void:
	_overlapping_holds.erase(area)

	# If we were hanging on this hold and it moved away or was deleted, drop.
	if _current_hold != null and _current_hold == area.get_parent():
		_release_hold()
		_set_state(State.FALL)

# ---------------------------------------------------------------------------
# STAMINA TICKER
# Called every physics frame from _physics_process (after _tick_timers).
# Drains stamina while gripping, starts a regen delay when resting, then
# regenerates.  Emits stamina_changed so the HUD can react when built.
# ---------------------------------------------------------------------------
func _tick_stamina(delta: float) -> void:
	var prev_stamina := _stamina
	var is_gripping  := (state == State.WALL_CLIMB
						 or state == State.LEDGE_HANG
						 or state == State.LEDGE_CLIMB
						 or state == State.HANG_IDLE
						 or state == State.HANG_MOVE
						 or state == State.HANG_EDGE)

	if is_gripping:
		# Choose the drain rate for the current activity.
		var drain : float
		if state == State.WALL_CLIMB:
			drain = stamina_drain_wall_climb
		elif state == State.LEDGE_HANG and _sprite.animation == &"LedgeHangIdle":
			# Idle hang uses the lower drain rate — only if the toggle is on.
			drain = stamina_drain_ledge_hang_idle if ledge_hang_idle_drains_stamina else 0.0
		elif state == State.HANG_IDLE or state == State.HANG_MOVE \
				or state == State.HANG_EDGE:
			# Background hold hanging — uses its own stamina_drain_hang rate.
			drain = stamina_drain_hang
		else:
			# LedgeHang entry animation and LedgeClimb both use the active rate.
			drain = stamina_drain_ledge_hang

		_stamina = maxf(_stamina - drain * delta, 0.0)
		_stamina_regen_timer = stamina_regen_delay   # reset regen delay every draining frame

		if _stamina <= 0.0:
			_stamina_exhausted = true

	else:
		# Not gripping — wait out the regen delay, then start recovering.
		if _stamina_regen_timer > 0.0:
			_stamina_regen_timer = maxf(_stamina_regen_timer - delta, 0.0)
		elif _stamina < stamina_max:
			_stamina = minf(_stamina + stamina_regen_rate * delta, stamina_max)

	# Clear exhaustion once the player has recovered enough to grip again (25 % threshold).
	# The 25 % buffer prevents the flicker of rapidly entering and exiting exhaustion.
	if _stamina_exhausted and _stamina >= stamina_max * 0.25:
		_stamina_exhausted = false

	# Only emit the signal when the value actually changed — avoids redundant HUD updates.
	if _stamina != prev_stamina:
		stamina_changed.emit(_stamina, stamina_max)

# ---------------------------------------------------------------------------
# WALL JUMP
# Launches the player away from the wall. State is set directly (same pattern
# as _double_jump) so WallJump animation is never immediately stomped.
# ---------------------------------------------------------------------------
func _start_wall_jump() -> void:
	# Use the cached wall normal so this works both when directly on the wall
	# and during the coyote window after leaving it (when is_on_wall() is false).
	var normal_x := get_wall_normal().x if is_on_wall() else _last_wall_normal.x
	velocity.y = jump_force
	velocity.x = normal_x * move_speed * wall_jump_x_multiplier
	_coyote_timer = 0.0
	_wall_coyote_timer = 0.0   # consume the wall coyote window
	_jump_buffer_timer = 0.0
	_has_double_jumped = false  # wall jump always refreshes the double jump
	if wall_jump_refreshes_dash:
		_air_dashes_used = 0
	state = State.JUMP
	_sprite.play("WallJump")

# ---------------------------------------------------------------------------
# AIR MOVEMENT
# Handles horizontal air control, variable-jump gravity, and fast fall.
# ---------------------------------------------------------------------------
func _process_air(input: Vector2, delta: float) -> void:
	# --- Horizontal air control ---
	# We still allow direction changes mid-air, just using the same accel/friction.
	if input.x != 0:
		velocity.x = move_toward(velocity.x, input.x * move_speed, acceleration * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)

	# --- Gravity scaling ---
	# Four cases (evaluated top-to-bottom; fast fall wins over all):
	#   1. Holding Down (any vertical velocity) → fast fall, slam to floor
	#   2. Rising AND holding jump              → lighter gravity (hang time)
	#   3. Falling normally                     → heavier gravity (snappy drop)
	#   4. Rising but released jump             → normal gravity (short-hop)
	var gravity_scale: float
	if _down_held:
		gravity_scale = fast_fall_gravity_multiplier       # case 1 — fast fall
	elif velocity.y < 0.0 and _jump_held:
		gravity_scale = variable_jump_gravity_multiplier   # case 2 — float up
	elif velocity.y > 0.0:
		gravity_scale = fall_gravity_multiplier            # case 3 — drop fast
	else:
		gravity_scale = 1.0                                # case 4 — neutral

	velocity.y += _base_gravity * gravity_scale * delta

	# --- Wall coyote-time jump ---
	# Allow a wall jump if the wall coyote timer is still running (recently
	# left a wall slide). Uses _last_wall_normal since is_on_wall() may be
	# false at this point. Mirrors the floor coyote check below.
	if _jump_pressed and _wall_coyote_timer > 0.0:
		_start_wall_jump()
	# --- Floor coyote-time jump ---
	# Allow a normal jump if the coyote timer is still running (recently left
	# a ledge) OR if a normal jump was pressed.
	elif _jump_pressed and _coyote_timer > 0.0:
		_start_jump()
	# --- Double jump ---
	# Only fires when: coyote window is gone (true air), haven't double-jumped
	# yet this airtime, and the feature is enabled in the Inspector.
	elif _jump_pressed and double_jump_enabled and not _has_double_jumped:
		_double_jump()

	# --- Jump buffer: record the press so it can fire the moment we land ---
	if _jump_pressed:
		_jump_buffer_timer = jump_buffer_time

	# --- Air dash ---
	if dash_enabled and _dash_pressed and air_dash_allowed:
		if _dash_cooldown_timer <= 0.0 and _air_dashes_used < air_dashes_allowed:
			_air_dashes_used += 1
			_start_dash(input.x)

# ---------------------------------------------------------------------------
# DASH MOVEMENT
# Locks the player into a horizontal dash, ignoring normal gravity/friction.
# Also checks for a queued air dash pressed during this dash so the input
# is never silently dropped (a dash is only 0.18s — easy to overlap presses).
# ---------------------------------------------------------------------------
func _process_dash(input: Vector2, delta: float) -> void:
	# Override velocity completely while dashing — the player moves at a fixed
	# horizontal speed and gravity is suspended for the dash duration.
	velocity.x = _dash_direction * dash_speed
	velocity.y = 0.0  # neutralise gravity during the dash for a clean feel

	# --- Chain air dash: allow a new dash press to fire before this one ends ---
	# Without this, pressing dash during the 0.18s window would lose the input
	# entirely because _process_air never runs while state == DASH.
	if dash_enabled and not is_on_floor() and _dash_pressed and air_dash_allowed:
		if _dash_cooldown_timer <= 0.0 and _air_dashes_used < air_dashes_allowed:
			_air_dashes_used += 1
			_start_dash(input.x)
			return  # _start_dash reset _dash_timer; let the new dash run next frame

	_dash_timer -= delta
	if _dash_timer <= 0.0:
		# Dash ended naturally — return to the appropriate air/ground state.
		_update_state()

# ---------------------------------------------------------------------------
# JUMP INITIATOR
# Called whenever a jump should fire (normal press, coyote, or buffer).
# ---------------------------------------------------------------------------
func _start_jump() -> void:
	velocity.y = jump_force
	_coyote_timer = 0.0      # consume the coyote window
	_jump_buffer_timer = 0.0 # consume the buffered input
	_set_state(State.JUMP)

# ---------------------------------------------------------------------------
# DOUBLE JUMP
# Fires a second jump from mid-air. Sets state directly (bypassing _set_state)
# so "JumpRise" is never played over the top of "DoubleJump" on the same frame.
# ---------------------------------------------------------------------------
func _double_jump() -> void:
	velocity.y = jump_force
	_has_double_jumped = true
	_coyote_timer = 0.0
	_jump_buffer_timer = 0.0
	# Write state directly — _set_state would play "JumpRise" and stomp the
	# animation we're about to set. State.JUMP is still correct for physics.
	state = State.JUMP
	_sprite.play("DoubleJump")

# ---------------------------------------------------------------------------
# DASH INITIATOR
# Determines direction and activates dash state.
# ---------------------------------------------------------------------------
func _start_dash(input_x: float) -> void:
	# Dash toward the held direction, or "forward" (last facing direction)
	# if no horizontal input is held at the moment of pressing dash.
	_dash_direction = input_x if input_x != 0.0 else float(_facing_direction)
	_dash_timer = dash_duration
	_dash_cooldown_timer = dash_cooldown
	_set_state(State.DASH)

# ---------------------------------------------------------------------------
# LANDING CALLBACK
# Called on the exact frame the player touches the ground.
# Resets air abilities so they're available again next time the player jumps.
# ---------------------------------------------------------------------------
func _on_landed() -> void:
	# Play the landing animation when arriving from a jump or fall.
	# _set_state() skips re-triggering Idle/Run/Crouch/Crawl while it plays,
	# and _on_animation_finished hands off to the right ground animation.
	if state == State.JUMP or state == State.FALL:
		_sprite.play("Land")
	_air_dashes_used = 0
	_has_double_jumped = false
	_coyote_timer = 0.0
	_wall_coyote_timer = 0.0
	# Fully restore stamina on landing — touching the ground is the natural
	# recovery moment (mirrors how most platformers handle grip/stamina).
	_stamina               = stamina_max
	_stamina_exhausted     = false
	_stamina_regen_timer   = 0.0
	stamina_changed.emit(_stamina, stamina_max)
	# The jump buffer is intentionally NOT reset here — _process_ground() will
	# consume it on the same frame so the jump fires immediately on landing.

# ---------------------------------------------------------------------------
# TIMER TICKER
# Decrements all countdown timers each frame.  Clamped to 0 so they never
# go negative, which would cause confusing "super-long" timer states.
# ---------------------------------------------------------------------------
func _tick_timers(delta: float) -> void:
	# Coyote timer: start counting when the player leaves the floor.
	# We feed it a fresh value each frame we ARE on the floor, so it only
	# begins depleting the first frame after the player steps off.
	if is_on_floor():
		_coyote_timer = coyote_time
	else:
		_coyote_timer = maxf(_coyote_timer - delta, 0.0)

	# Wall coyote timer: same pattern as above but for wall slides.
	# Fed a fresh value every frame the player IS wall-sliding; begins
	# depleting the first frame after they leave the slide. While > 0,
	# jump input still fires a wall jump even without wall contact.
	if state == State.WALL_SLIDE:
		_wall_coyote_timer = wall_coyote_time
	else:
		_wall_coyote_timer = maxf(_wall_coyote_timer - delta, 0.0)

	_jump_buffer_timer      = maxf(_jump_buffer_timer      - delta, 0.0)
	_ledge_grab_cooldown    = maxf(_ledge_grab_cooldown    - delta, 0.0)
	_hold_grab_cooldown     = maxf(_hold_grab_cooldown     - delta, 0.0)
	_wall_climb_cooldown    = maxf(_wall_climb_cooldown    - delta, 0.0)

	# Ledge coyote and grab buffer — both fed from the same raycast snapshot.
	# Coyote: mirrors floor coyote — stays fresh while ledge is visible, then
	#         decays, giving a short window to grab after drifting past the edge.
	# Buffer: also set while ledge is visible so the grab fires the moment
	#         can_grip becomes true, even if raycasts have since lost the ledge.
	# Never feed the ledge timers while on a ceiling — the horizontal raycasts
	# can't see a horizontal ceiling, so they'd falsely detect a "ledge" at
	# every right-angle corner where a wall meets an overhead surface.
	# Also zero both timers immediately on any ceiling contact so a previously
	# set timer can't fire in the coyote window after the player leaves.
	# Ceiling check is scoped to WALL_CLIMB only.  In JUMP/FALL the surface
	# 8 px above the player is the ledge being approached from below — treating
	# it as a ceiling would kill the timers and prevent the grab entirely.
	var _ceiling_above    := state == State.WALL_CLIMB \
							 and test_move(global_transform, Vector2(0.0, -8.0))
	var _ledge_in_range   := (_ledge_check_lower.is_colliding()
							and not _ledge_check_upper.is_colliding()
							and not _ceiling_above)
	if _ledge_in_range:
		_ledge_coyote_timer      = ledge_coyote_time
		_ledge_grab_buffer_timer = ledge_grab_buffer_time
		_ledge_detected_y        = global_position.y   # freeze the ideal hang height
	elif _ceiling_above:
		# Hard-clear timers — only fires during WALL_CLIMB at a corner.
		_ledge_coyote_timer      = 0.0
		_ledge_grab_buffer_timer = 0.0
	else:
		_ledge_coyote_timer      = maxf(_ledge_coyote_timer      - delta, 0.0)
		_ledge_grab_buffer_timer = maxf(_ledge_grab_buffer_timer - delta, 0.0)

	# Cooldown only prevents rapid re-dashing — it no longer restores air dashes.
	# Air dashes restore exclusively on landing (see _on_landed).
	_dash_cooldown_timer = maxf(_dash_cooldown_timer - delta, 0.0)
	# _dash_timer is ticked inside _process_dash() so it only runs while dashing.

	if _invincible_timer > 0.0:
		_invincible_timer = maxf(_invincible_timer - delta, 0.0)

# ---------------------------------------------------------------------------
# WALL HELPER
# Returns true only if the player is touching a non-player wall surface.
# is_on_wall() alone returns true when leaning on another CharacterBody2D
# (i.e. another player), which would let players climb each other.
# get_slide_collision() lets us inspect the actual collider and skip Players.
# ---------------------------------------------------------------------------
func _is_on_climbable_wall() -> bool:
	# When already gripping a wall, skip the is_on_wall() requirement.
	# A moving platform can push the player off the surface for one frame;
	# the raycasts still detect the wall within 20 px so grip is maintained.
	# In all other states, is_on_wall() is the cheaper first gate.
	if state != State.WALL_CLIMB and not is_on_wall():
		return false

	# Require wall geometry at BOTH an upper and a lower body sample point.
	# Upper at y+2, lower at y+32 — both must hit for the wall to span
	# most of the body and count as climbable.
	var space := get_world_2d().direct_space_state
	var fx    := float(_facing_direction) * 20.0
	var upper := PhysicsRayQueryParameters2D.create(
		global_position + Vector2(0.0, 2.0),
		global_position + Vector2(fx, 2.0)
	)
	upper.exclude = [get_rid()]; upper.collision_mask = collision_mask
	if space.intersect_ray(upper).is_empty():
		return false
	var lower := PhysicsRayQueryParameters2D.create(
		global_position + Vector2(0.0, 32.0),
		global_position + Vector2(fx, 32.0)
	)
	lower.exclude = [get_rid()]; lower.collision_mask = collision_mask
	if space.intersect_ray(lower).is_empty():
		return false

	# If we're not physically touching the wall (WALL_CLIMB on a moving platform
	# that briefly pushed us off), trust the raycasts alone.
	if not is_on_wall():
		return true

	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		if col.get_collider() is Player:
			continue
		if abs(col.get_normal().x) > abs(col.get_normal().y):
			return true
	return false

# ---------------------------------------------------------------------------
# STAND SHAPE TEST
# Tests whether the standing collision shape would overlap geometry at the
# given world-space transform.  Saves and restores the ORIGINAL disabled flags
# so this is safe to call from any state without corrupting the active shape.
# ---------------------------------------------------------------------------
func _test_stand_shape_at(target: Transform2D) -> bool:
	var stand_was := _collision_stand.disabled
	var duck_was  := _collision_duck.disabled
	_collision_stand.disabled = false
	_collision_duck.disabled  = true
	var hit := test_move(target, Vector2.ZERO)
	_collision_stand.disabled = stand_was
	_collision_duck.disabled  = duck_was
	return hit

# Returns true if there is vertical clearance to stand at the current position.
func _can_stand() -> bool:
	return not _test_stand_shape_at(global_transform)

# ---------------------------------------------------------------------------
# STATE UPDATER
# Figures out which state the player should be in based on current conditions.
# Only called after movement so velocity is already updated for this frame.
# ---------------------------------------------------------------------------
func _update_state() -> void:
	if state == State.EXITING or state == State.BATTLE_ATTACK:
		return

	# Never interrupt an active dash from outside _process_dash().
	if state == State.DASH and _dash_timer > 0.0:
		return

	# When wall climbing against a ceiling, move_and_slide() may report only the
	# ceiling normal that frame, making _is_on_climbable_wall() briefly return
	# false and causing a one-frame drop to FALL/WALL_SLIDE → animation flicker.
	# The _is_on_climbable_wall() condition ensures this guard only holds while
	# the player is still in contact with the wall — pressing the opposite
	# direction moves them off the wall, clearing the guard and allowing the
	# normal fall transition to run.
	if state == State.WALL_CLIMB \
			and test_move(global_transform, Vector2(0.0, -8.0)) \
			and _is_on_climbable_wall():
		return

	# Ledge and background-hold states are managed entirely by their own
	# process functions — don't let _update_state override them mid-hang.
	if state == State.LEDGE_HANG or state == State.LEDGE_CLIMB \
			or state == State.HANG_IDLE or state == State.HANG_MOVE \
			or state == State.HANG_EDGE:
		return

	# Evaluated in both branches below, so defined once here.
	var can_grip := climbing_enabled and not _stamina_exhausted and _stamina > 0.0

	if is_on_floor():
		# Wall climb takes priority even from the ground — if the player is
		# standing against a wall, holding grip, and has stamina, let them
		# transition directly into the climb without needing to jump first.
		if _is_on_climbable_wall() and _grip_held and can_grip and not _down_held:
			_set_state(State.WALL_CLIMB)
		elif _down_held and _input_x != 0.0:
			_set_state(State.CRAWL)
		elif _down_held:
			_set_state(State.DUCK)
		else:
			# Released down — only stand if there is ceiling clearance.
			# If a ceiling blocks standing, hold the crouched state until the
			# player moves out from under it (classic game behaviour).
			var crouched := (state == State.DUCK or state == State.CRAWL)
			if crouched and not _can_stand():
				_set_state(State.DUCK if _input_x == 0.0 else State.CRAWL)
			elif abs(velocity.x) > 1.0 and not is_on_wall():
				_set_state(State.RUN)
			else:
				_set_state(State.IDLE)
	else:
		# 1. LEDGE HANG — highest priority, checked before wall climb.
		#    If the lower ray hits a wall but the upper ray is clear, a grabbable
		#    ledge is present. This must beat wall climb so the player can't
		#    climb straight past a ledge with grip held.
		if can_grip and _ledge_grab_cooldown <= 0.0 \
				and not (state == State.WALL_CLIMB and test_move(global_transform, Vector2(0.0, -8.0))) \
				and (_ledge_coyote_timer > 0.0 or _ledge_grab_buffer_timer > 0.0):
			# Test the ledge-climb landing spot before committing to a hang.
			# Uses _ledge_detected_y (the actual snap base) for accuracy, and the
			# safe helper so the active collision shape is never corrupted.
			var dest_pos := Vector2(
				global_position.x + float(_facing_direction) * 14.5,
				_ledge_detected_y - ledge_hang_snap_up - 39.0)
			if not _test_stand_shape_at(Transform2D(0.0, dest_pos)):
				_set_state(State.LEDGE_HANG)

		# 2. WALL CLIMB — grip held + on climbable wall, no ledge in the way.
		elif _is_on_climbable_wall() and _grip_held and can_grip \
				and _wall_climb_cooldown <= 0.0:
			_set_state(State.WALL_CLIMB)

		# 3. WALL SLIDE — falling + pressing toward a climbable wall (no grip needed).
		else:
			var pressing_into_wall := _input_x * float(_facing_direction) > 0.0
			if _is_on_climbable_wall() and velocity.y > 0.0 and pressing_into_wall:
				_set_state(State.WALL_SLIDE)
			elif velocity.y < 0.0:
				_set_state(State.JUMP)
			else:
				_set_state(State.FALL)

# ---------------------------------------------------------------------------
# STATE SETTER
# Central place to change state so we can add enter/exit hooks later
# (e.g. play animations, emit signals) without touching every call site.
# ---------------------------------------------------------------------------
func _set_state(new_state: State) -> void:
	if state == new_state:
		return  # already in this state — nothing to do
	# When wall climb drops involuntarily to FALL (not a deliberate wall jump,
	# which exits to JUMP), apply a brief cooldown so the player can't
	# immediately re-grab the same wall section.
	if state == State.WALL_CLIMB and new_state == State.FALL:
		_wall_climb_cooldown = 0.25
		# Cancel any upward wall-climb velocity so the player falls immediately
		# toward the ledge detection zone rather than arcing further above it.
		velocity.y = maxf(velocity.y, 0.0)
	# While the double jump flip is mid-play, allow physics state to update
	# (so gravity, collision, and air-dash logic stay correct) but don't touch
	# the animation. Only natural air transitions are guarded — deliberate inputs
	# like DASH or landing (→ IDLE/RUN) still cut through immediately.
	# While a one-shot air animation plays, let physics state update but
	# don't change the animation — same guard covers both DoubleJump and WallJump.
	# While a one-shot air animation plays, allow physics state to update
	# (so gravity and collision stay correct) but don't stomp the animation.
	# LedgeClimb is included so the climb-up clip can never be interrupted.
	var one_shot := (_sprite.animation == &"DoubleJump"
					 or _sprite.animation == &"WallJump"
					 or _sprite.animation == &"LedgeClimb"
					 or _sprite.animation == &"ClimbGrab")
	if one_shot and _sprite.is_playing():
		if new_state in [State.JUMP, State.FALL, State.WALL_CLIMB]:
			state = new_state
			return
	state = new_state
	# Swap collision capsules whenever state changes.
	# Both DUCK and CRAWL use the short capsule so the player fits in low passages.
	var is_crouched := (state == State.DUCK or state == State.CRAWL)
	_collision_stand.disabled = is_crouched
	_collision_duck.disabled  = not is_crouched
	# If debug mode has made either shape visible, keep visibility in sync with
	# the active/inactive state so only the physics-active capsule is shown.
	var debug_on := _collision_stand.visible or _collision_duck.visible
	if debug_on:
		_collision_stand.visible = not _collision_stand.disabled
		_collision_duck.visible  = not _collision_duck.disabled
		_collision_stand.queue_redraw()
		_collision_duck.queue_redraw()
	# Skip these while the one-shot Land animation is still playing —
	# _on_animation_finished hands off to the right ground animation once it ends.
	var landing := _sprite.animation == &"Land" and _sprite.is_playing()
	match state:
		State.IDLE:        if not landing: _sprite.play("Idle")
		State.RUN:         if not landing: _sprite.play("Run")
		State.DUCK:        if not landing: _sprite.play("Crouch")
		State.CRAWL:       if not landing: _sprite.play("Crawl")
		State.JUMP:        _sprite.play("JumpRise")
		State.FALL:        _sprite.play("JumpFall")
		State.DASH:        _sprite.play("DashLoop")
		State.WALL_SLIDE:
			velocity.y = maxf(velocity.y, 0.0)  # cancel upward momentum on grab
			_sprite.play("WallSlide")
		State.WALL_CLIMB:  _sprite.play("WallClimb")   # _process_wall_climb updates this each frame
		State.LEDGE_HANG:
			# Snap to the Y recorded when the raycasts first saw the ledge, then
			# apply the visual nudge.  This keeps the hang height consistent whether
			# the grab fired immediately or via the coyote / buffer window.
			# Directional snap: fall nudges down, rise nudges up, neutral uses snap_up only.
			var _fall_offset := ledge_hang_fall_snap if velocity.y > 0.0 else 0.0
			var _rise_offset := ledge_hang_rise_snap if velocity.y < 0.0 else 0.0
			global_position.y = _ledge_detected_y - ledge_hang_snap_up + _fall_offset - _rise_offset
			_sprite.play("LedgeHang")   # _on_animation_finished transitions to LedgeHangIdle
		State.LEDGE_CLIMB: _sprite.play("LedgeClimb")  # _on_animation_finished transitions to IDLE
		State.HANG_IDLE:
			# ClimbGrab plays once on initial grab; _on_animation_finished hands off to ClimbIdle.
			# Back-view animation — sprite is NOT flipped during any HANG state.
			# FUTURE — when HoldType.ROPE is active, use MonkeyBarIdle here instead.
			# See BackgroundHold.HoldType.ROPE for context.
			_sprite.play("ClimbGrab")
		State.HANG_MOVE:
			# Direction-specific animation is set each frame inside _process_hang_move.
			# Default to ClimbLeft; it will be corrected within one physics tick.
			_sprite.play("ClimbLeft")
		State.HANG_EDGE:
			_sprite.play("ClimbJumpPrepare")
		State.EXITING:
			# Don't change animation on exit — let whatever was playing continue.
			# Exception: IDLE and LookUp are stationary; play Run in exit direction.
			if _sprite.animation == &"Idle" or _sprite.animation == &"LookUp":
				if _exit_direction == Vector2.LEFT:
					_facing_direction = -1
				elif _exit_direction == Vector2.RIGHT:
					_facing_direction = 1
				_sprite.play("Run")
			# For UP/DOWN exits the jump/fall animation already plays naturally.
	# TODO: emit a signal (state_changed) for BattleManager / UI to react to.

# ---------------------------------------------------------------------------
# ANIMATION FINISHED CALLBACK
# Fires when any non-looping animation reaches its last frame.
# Used to hand off from committed one-shot animations back to the live state.
# ---------------------------------------------------------------------------
func _on_animation_finished() -> void:
	# ---- DoubleJump ----
	# Resume whichever air animation matches velocity at the moment the flip ends.
	if _sprite.animation == &"DoubleJump":
		_sprite.play("JumpFall" if velocity.y >= 0.0 else "JumpRise")

	# ---- WallJump ----
	# Wall jump always launches upward; hand off to JumpRise (or JumpFall if
	# the player somehow peaks and starts falling before the clip finishes).
	elif _sprite.animation == &"WallJump":
		_sprite.play("JumpFall" if velocity.y >= 0.0 else "JumpRise")

	# ---- Land → Idle/Run/Crouch/Crawl ----
	# The landing animation plays once; hand off to whatever ground animation
	# matches the state _update_state() has already settled into.
	elif _sprite.animation == &"Land":
		match state:
			State.RUN:   _sprite.play("Run")
			State.DUCK:  _sprite.play("Crouch")
			State.CRAWL: _sprite.play("Crawl")
			_:           _sprite.play("Idle")

	# ---- LedgeHang (entry) → LedgeHangIdle (loop) ----
	# The grab animation plays once; afterwards the player idles on the ledge.
	elif _sprite.animation == &"LedgeHang":
		_sprite.play("LedgeHangIdle")

	# ---- ClimbGrab (background hold entry) → ClimbIdle ----
	# Mirrors the LedgeHang → LedgeHangIdle pattern exactly.
	# ClimbGrab plays once when first grabbing a hold; ClimbIdle loops after.
	# FUTURE — when HoldType.ROPE is active, transition to MonkeyBarIdle here.
	# See BackgroundHold.HoldType.ROPE for context.
	elif _sprite.animation == &"ClimbGrab":
		_sprite.play("ClimbIdle")

	# ---- LedgeClimb → IDLE ----
	# The climb-up animation finishes; nudge the player onto the surface.
	# The offsets below are approximate — tune them to match the art.
	elif _sprite.animation == &"LedgeClimb":
		# Move the player up by roughly the capsule half-height so they land
		# on top of the ledge, and forward by a small step so they clear the edge.
		global_position.y -= 39.0
		global_position.x += float(_facing_direction) * 14.5
		# Force raycasts to reflect the new position before the next physics frame.
		# _on_animation_finished fires during _process() (between physics frames).
		# Without this, _tick_timers() in the next _physics_process() reads the stale
		# raycast state from the hang position (lower ray still touching the wall),
		# sees _ledge_in_range = true, and re-feeds the coyote/buffer timers —
		# overwriting the zeroes below and triggering a re-grab into nothing.
		_ledge_check_upper.force_raycast_update()
		_ledge_check_lower.force_raycast_update()
		_ledge_coyote_timer      = 0.0
		_ledge_grab_buffer_timer = 0.0
		# Clear any platform velocity that accumulated during the climb animation.
		# _process_ledge_climb() zeros velocity each frame, but the platform carry
		# block re-adds _platform_velocity afterward (LEDGE_CLIMB is surface-attached
		# and _was_on_floor is false, so the upward clamp doesn't apply).  That
		# leftover velocity.y < 0 carries into the first IDLE frame and makes
		# _update_state() see airborne + upward velocity → JUMP state flicker.
		velocity          = Vector2.ZERO
		_platform_velocity = Vector2.ZERO
		_set_state(State.IDLE)

# ---------------------------------------------------------------------------
# EXIT — called by Room.gd when the player enters an exit zone.
# Magnetizes the player out of the screen in the given direction.
# ---------------------------------------------------------------------------
func start_exit(direction: Vector2) -> void:
	if _is_exiting:
		return
	# Ignore exit triggers during the post-room-load grace period. arrive_in_room()
	# sets _invincible_timer = 0.5; any body_entered signal that fires before the
	# physics engine settles on the new spawn position would otherwise re-trigger
	# the exit immediately and send the player flying through the next room.
	if _invincible_timer > 0.0:
		return
	_is_exiting = true
	_exit_direction = direction
	# Set facing before _set_state so the animation case sees it.
	if direction == Vector2.LEFT:
		_facing_direction = -1
	elif direction == Vector2.RIGHT:
		_facing_direction = 1
	# _set_state first (it resets collision shapes internally), then override
	# to disabled so wall tiles don't block the slide off-screen.
	# Direct assignments are safe — Room.gd calls start_exit via call_deferred.
	# Re-enabled in arrive_in_room() after the transition.
	_set_state(State.EXITING)
	_collision_stand.disabled = true
	_collision_duck.disabled = true

func _process_exiting(delta: float) -> void:
	match _exit_direction:
		Vector2.LEFT:
			velocity.x = -exit_horizontal_speed
			velocity.y = 0.0
		Vector2.RIGHT:
			velocity.x = exit_horizontal_speed
			velocity.y = 0.0
		Vector2.UP:
			velocity.x = 0.0
			velocity.y = -exit_boost_speed
		Vector2.DOWN:
			# Fall naturally with a minimum downward speed.
			velocity.y = maxf(velocity.y + _base_gravity * delta, exit_boost_speed)
			velocity.x = 0.0

func _check_exit_offscreen() -> void:
	var room := RoomManager.current_room as Room
	if room == null:
		return
	var bounds := room.get_bounds_rect()
	var off_screen := false
	match _exit_direction:
		Vector2.LEFT:   off_screen = global_position.x < bounds.position.x - 40.0
		Vector2.RIGHT:  off_screen = global_position.x > bounds.end.x + 40.0
		Vector2.UP:     off_screen = global_position.y < bounds.position.y - 40.0
		Vector2.DOWN:   off_screen = global_position.y > bounds.end.y + 40.0
	if off_screen:
		set_physics_process(false)
		RoomManager.player_finished_exit(self)

# Called by RoomManager after loading a new room and placing the player.
# Resets all exit state and grants a brief invincibility window.
func arrive_in_room(spawn_position: Vector2) -> void:
	_is_exiting      = false
	_exit_direction  = Vector2.ZERO
	velocity         = Vector2.ZERO
	_platform_velocity = Vector2.ZERO
	global_position  = spawn_position
	# Re-enable collision shapes that were disabled in start_exit().
	_collision_stand.disabled = false
	_collision_duck.disabled  = true   # duck shape stays off by default (standing state)
	set_physics_process(true)
	_set_state(State.IDLE)
	_invincible_timer = 0.5   # 0.5 s grace period so player can't land on a spike instantly
	# FUTURE — could show a brief flash or shield indicator during invincibility.

# Called by RoomManager on subsequent (non-first) room loads to play a
# direction-specific entry animation before handing control back to the player.
func start_room_entry(entry_direction: String, emerge_position: Vector2, spawn_position: Vector2, entry_path: Path2D = null) -> void:
	_entry_direction = entry_direction
	_entry_path = entry_path
	_is_exiting = false
	_exit_direction = Vector2.ZERO
	velocity = Vector2.ZERO
	_platform_velocity = Vector2.ZERO
	global_position = emerge_position
	_collision_stand.disabled = false
	_collision_duck.disabled = true
	set_physics_process(true)
	_invincible_timer = 0.5
	battle_locked = true
	_battle_walk_direction = 0
	# A drawn PlayerOneEntryPath/PlayerTwoEntryPath overrides the default
	# direction-specific motion for ANY entry direction — it lets a room
	# author trace the exact drop-in route (e.g. rise then settle onto a
	# platform) regardless of which exit the player is arriving from.
	var curve : Curve2D = _entry_path.curve if _entry_path != null else null
	if curve != null and curve.get_baked_length() > 0.0:
		_entry_along_path(curve, spawn_position)
		return
	match entry_direction:
		"south":
			_entry_from_south(spawn_position)
		"north":
			_entry_from_north(spawn_position)
		"east":
			_entry_from_east(spawn_position)
		"west":
			_entry_from_west(spawn_position)
		_:
			arrive_in_room(spawn_position)

# Drags the player along a hand-drawn entry path (PlayerOneEntryPath /
# PlayerTwoEntryPath) from the emerge marker to the spawn marker.
# Duration scales with the path's length so the speed feels consistent
# regardless of how long the route is in a given room.
func _entry_along_path(curve: Curve2D, spawn_position: Vector2) -> void:
	_facing_direction = 1
	_sprite.flip_h = false
	_battle_walk_direction = 0
	_set_state(State.FALL)
	set_physics_process(false)
	velocity = Vector2.ZERO
	# curve.get_baked_length() measures the curve in the Path2D node's LOCAL
	# space, before its own position/scale is applied. Different rooms'
	# entry-path nodes can have wildly different (and non-uniform) scales from
	# editor authoring, so a local-space length doesn't correspond to a
	# consistent on-screen distance. Bake the points and transform each to
	# global space first, so entry_descend_speed always means global px/s.
	_entry_path_points.clear()
	for local_point in curve.get_baked_points():
		_entry_path_points.append(_entry_path.to_global(local_point))
	var total_length := 0.0
	for i in range(1, _entry_path_points.size()):
		total_length += _entry_path_points[i - 1].distance_to(_entry_path_points[i])
	if total_length > 0.0:
		var duration := total_length / entry_descend_speed
		var tween := create_tween()
		tween.tween_method(_sample_entry_path, 0.0, total_length, duration)
		await tween.finished
	# Snap to the exact spawn marker in case the drawn path doesn't end precisely on it.
	global_position = spawn_position
	set_physics_process(true)
	_set_state(State.IDLE)
	await get_tree().create_timer(entry_control_delay).timeout
	_entry_direction = ""
	if BattleManager.current_phase == BattleManager.BattlePhase.INACTIVE:
		battle_locked = false

func _entry_from_south(_spawn_position: Vector2) -> void:
	_facing_direction = 1
	_sprite.flip_h = false
	velocity.y = -entry_rise_speed
	_set_state(State.JUMP)
	while not is_on_floor():
		await get_tree().process_frame
	_set_state(State.IDLE)
	await get_tree().create_timer(entry_control_delay).timeout
	_entry_direction = ""
	if BattleManager.current_phase == BattleManager.BattlePhase.INACTIVE:
		battle_locked = false

func _entry_from_north(spawn_position: Vector2) -> void:
	_facing_direction = 1
	_sprite.flip_h = false
	_battle_walk_direction = 0
	_set_state(State.FALL)
	# PlayerOneEmerge/TwoEmerge usually sit in open air with no platform below,
	# so falling under gravity won't reliably land on the spawn marker. Instead,
	# tween straight to the spawn position. (If a PlayerOneEntryPath/
	# PlayerTwoEntryPath is drawn, _entry_along_path handles this instead.)
	set_physics_process(false)
	velocity = Vector2.ZERO
	var distance := global_position.distance_to(spawn_position)
	var duration := distance / entry_descend_speed
	var tween := create_tween()
	tween.tween_property(self, "global_position", spawn_position, duration)
	await tween.finished
	set_physics_process(true)
	_set_state(State.IDLE)
	await get_tree().create_timer(entry_control_delay).timeout
	_entry_direction = ""
	if BattleManager.current_phase == BattleManager.BattlePhase.INACTIVE:
		battle_locked = false

# Tween callback for _entry_along_path — walks _entry_path_points (a global-
# space polyline) by the given distance and places the player there.
func _sample_entry_path(distance: float) -> void:
	var remaining := distance
	for i in range(1, _entry_path_points.size()):
		var seg_start : Vector2 = _entry_path_points[i - 1]
		var seg_end : Vector2 = _entry_path_points[i]
		var seg_len := seg_start.distance_to(seg_end)
		if remaining <= seg_len or i == _entry_path_points.size() - 1:
			var t := 0.0 if seg_len <= 0.0 else clampf(remaining / seg_len, 0.0, 1.0)
			global_position = seg_start.lerp(seg_end, t)
			return
		remaining -= seg_len

func _entry_from_east(spawn_position: Vector2) -> void:
	_facing_direction = -1
	_sprite.flip_h = true
	_battle_walk_direction = -1
	while global_position.x > spawn_position.x:
		await get_tree().process_frame
	_battle_walk_direction = 0
	_set_state(State.IDLE)
	await get_tree().create_timer(entry_control_delay).timeout
	_entry_direction = ""
	if BattleManager.current_phase == BattleManager.BattlePhase.INACTIVE:
		battle_locked = false

func _entry_from_west(spawn_position: Vector2) -> void:
	_facing_direction = 1
	_sprite.flip_h = false
	_battle_walk_direction = 1
	while global_position.x < spawn_position.x:
		await get_tree().process_frame
	_battle_walk_direction = 0
	_set_state(State.IDLE)
	await get_tree().create_timer(entry_control_delay).timeout
	_entry_direction = ""
	if BattleManager.current_phase == BattleManager.BattlePhase.INACTIVE:
		battle_locked = false

# ---------------------------------------------------------------------------
# BATTLE CONTROL — called by BattleManager during the intro walk-in.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# ATTACK SEQUENCE — called by BattleManager when player picks Attack.
# Teleports to the enemy, plays animations, returns to original position.
# ---------------------------------------------------------------------------

## Entry point called by BattleManager. Stores current position and kicks off
## the choreography coroutine.
func perform_attack(target: Node2D, damage: int = 1) -> void:
	_attack_damage       = damage
	_attack_target       = target
	_pre_attack_position = global_position
	_set_state(State.BATTLE_ATTACK)
	_do_attack_sequence()

func _do_attack_sequence() -> void:
	# Step 1 — DashStart in place.
	_sprite.flip_h = _facing_direction < 0
	_sprite.play(&"DashStart")
	await _sprite.animation_finished

	# Step 2 — Teleport to AttackReceivePoint.
	global_position = _attack_target.get_attack_receive_position()

	var face_dir: float = sign(_attack_target.global_position.x - global_position.x)
	if face_dir != 0.0:
		_sprite.flip_h = face_dir < 0.0

	# Step 3 — DashEnd at AttackReceivePoint.
	_sprite.play(&"DashEnd")
	await _sprite.animation_finished

	# -----------------------------------------------------------------------
	# HIT 1 — always lands, no timing required.
	# -----------------------------------------------------------------------
	var hit1_detected: bool = false
	_enable_hitbox()
	_hit_box.area_entered.connect(func(area: Area2D) -> void:
		if area.name == "HurtBox":
			hit1_detected = true
			_disable_hitbox()
			_attack_target.receive_hit(_attack_damage)
	, CONNECT_ONE_SHOT)
	_sprite.play(&"Punch01")
	await _sprite.animation_finished
	_disable_hitbox()

	if hit1_detected:
		await BattleManager.hit_sequence_done
	# FUTURE — if hit1_detected = false, target dodged or parried;
	# skip the combo entirely and go straight to the return dash.

	# -----------------------------------------------------------------------
	# HIT 2 — timing required. Circle shrinks toward ✕ above player's head.
	# FUTURE — parry/guard system: enemy can interrupt combo with a counter
	# if the player misses Hit 2 timing; enemy gets a free attack next turn.
	# FUTURE — weapon-specific combos: each weapon has its own combo chain.
	# -----------------------------------------------------------------------

	# Tracks whether the full combo completed without a miss. Used to decide
	# whether to turn the player away before the return dash:
	#   Miss at any point  → turn away (dramatic retreat)
	#   All hits successful → retreat facing forward (no turn-around)
	var combo_complete: bool = false

	var action_cmd: Node = BattleManager._action_command
	if action_cmd != null:
		# Brief Idle pose before the prompt — signals "get ready for the next hit."
		_sprite.play(&"Idle")
		await get_tree().create_timer(0.2).timeout
		action_cmd.activate(player_id, action_cmd.timing_window, self)
		var hit2_success: bool = await action_cmd.timing_result

		if hit2_success:
			var hit2_detected: bool = false
			# Re-apply facing direction — awaits between Hit 1 and here can drift flip_h.
			if face_dir != 0.0:
				_sprite.flip_h = face_dir < 0.0
			_enable_hitbox()
			_hit_box.area_entered.connect(func(area: Area2D) -> void:
				if area.name == "HurtBox":
					hit2_detected = true
					_disable_hitbox()
					_attack_target.receive_hit(action_cmd.hit2_damage)
			, CONNECT_ONE_SHOT)
			# Punch02 — second hit of combo, plays on successful Hit 2 timing.
			_sprite.play(&"Punch02")
			await _sprite.animation_finished
			_disable_hitbox()

			if hit2_detected:
				await BattleManager.hit_sequence_done

			# Return to Idle between hits — the pose change signals the player
			# that the next timing prompt is about to appear.
			_sprite.play(&"Idle")
			await get_tree().create_timer(0.2).timeout

			# -------------------------------------------------------------------
			# HIT 3 — slightly tighter timing window. Deals bonus damage.
			# FUTURE — combo meter: track total successful combos; high combo =
			# damage multiplier; resets on miss or turn end.
			# -------------------------------------------------------------------
			action_cmd.activate(player_id, action_cmd.hit3_timing_window, self)
			var hit3_success: bool = await action_cmd.timing_result

			if hit3_success:
				var hit3_detected: bool = false
				if face_dir != 0.0:
					_sprite.flip_h = face_dir < 0.0
				_enable_hitbox()
				_hit_box.area_entered.connect(func(area: Area2D) -> void:
					if area.name == "HurtBox":
						hit3_detected = true
						_disable_hitbox()
						_attack_target.receive_hit(action_cmd.hit3_damage)
				, CONNECT_ONE_SHOT)
				# Punch03 — third hit, deals bonus damage on success.
				_sprite.play(&"Punch03")
				await _sprite.animation_finished
				_disable_hitbox()

				if hit3_detected:
					await BattleManager.hit_sequence_done

				combo_complete = true   # all three hits landed
			# Miss on Hit 3 — combo ends; Hit 1 + Hit 2 damage already applied.

		# Miss on Hit 2 — combo ends after Hit 1 damage.
		# FUTURE — special miss reaction: enemy could counter attack on miss.
	else:
		# No timing system active — treat as combo complete so the return
		# dash plays without the dramatic turn-away.
		combo_complete = true

	# Step 7 — Brief dramatic pause before the return dash.
	await get_tree().create_timer(attack_pause_duration).timeout

	# Step 8 — Turn AWAY only on a miss. On a full successful combo the player
	# retreats without flipping, which reads as a clean dash-back rather than
	# a telegraphed turn. On miss the flip sells the "pushed back" feel.
	if not combo_complete:
		_sprite.flip_h = face_dir > 0.0

	# Step 9 — DashStart facing away.
	_sprite.play(&"DashStart")
	await _sprite.animation_finished

	# Step 10 — Teleport back to battle position.
	global_position = _pre_attack_position

	# Step 11 — DashEnd at battle position, facing toward the enemy again.
	_sprite.flip_h = _facing_direction < 0
	_sprite.play(&"DashEnd")
	await _sprite.animation_finished

	# Step 12 — Return to IDLE.
	_set_state(State.IDLE)

	# Step 13 — Notify BattleManager the full sequence is done.
	BattleManager.attack_sequence_complete()

# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# HITBOX / HURTBOX HELPERS
# ---------------------------------------------------------------------------

func _enable_hitbox() -> void:
	var offset: Vector2 = hitbox_offset
	if _sprite.flip_h:
		offset.x = -offset.x
	_hit_box.position = offset
	(_hit_box_shape.shape as RectangleShape2D).size = hitbox_size
	_hit_box.set_deferred("monitoring",  true)
	_hit_box.set_deferred("monitorable", true)

func _disable_hitbox() -> void:
	_hit_box.set_deferred("monitoring",  false)
	_hit_box.set_deferred("monitorable", false)

func enable_hurtbox() -> void:
	_hurt_box.set_deferred("monitorable", true)
	_hurt_box.set_deferred("monitoring",  false)

func disable_hurtbox() -> void:
	_hurt_box.set_deferred("monitorable", false)
	_hurt_box.set_deferred("monitoring",  false)
	# FUTURE — disable during parry window
	# FUTURE — disable during dodge frames
	# FUTURE — disable during jump (airborne)

## Called by the attacker when its HitBox overlaps this player's HurtBox.
func receive_hit(damage: int = 1) -> void:
	# Guard against double-hits while already downed or hurtbox disabled.
	if _is_downed:
		return
	if not _hurt_box.monitorable:
		return

	# Apply damage immediately so hp_changed fires and the HUD can react.
	take_damage(damage)

	# If this hit drained the last HP, skip the Hit animation and go straight
	# to the defeat sequence. BattleManager.player_downed() emits
	# hit_sequence_done so the attacker's coroutine continues cleanly.
	if current_hp <= 0:
		await _do_defeat_sequence()
		return

	# HP still > 0 — play the normal hit reaction then resume the turn.
	set_physics_process(false)
	velocity = Vector2.ZERO
	disable_hurtbox()
	_sprite.play(&"Hit")
	await _sprite.animation_finished
	await get_tree().create_timer(0.1).timeout
	enable_hurtbox()
	set_physics_process(true)
	# State is already IDLE during battle, so _set_state(IDLE) would early-return.
	# Play Idle directly to restart the animation.
	_sprite.play(&"Idle")
	BattleManager.hit_sequence_complete()
	# FUTURE — Option C revive system: downed player can be revived by
	# partner spending their turn or via a revival item.

## Plays the Die animation and notifies BattleManager the player is downed.
## Called from receive_hit() when HP reaches 0.
func _do_defeat_sequence() -> void:
	_is_downed = true
	disable_hurtbox()
	_disable_hitbox()
	velocity = Vector2.ZERO
	set_physics_process(false)
	# Disable world collision so the collapsed player doesn't block others.
	$CollisionShape2D.set_deferred("disabled", true)
	# Die animation plays once and holds the last frame.
	# Player stays collapsed for this fight.
	_sprite.play(&"Die")
	await _sprite.animation_finished
	# FUTURE — Option C revive window: partner has X turns to revive before
	# player is permanently out for this battle. Revival restores partial HP.
	# Animation: partner reaches down, downed player gets up slowly.
	BattleManager.player_downed(self)

## Called by BattleManager.end_battle() regardless of whether the player was
## downed. Restores the player to a playable state after the battle ends.
func battle_end_reset() -> void:
	_is_downed = false
	battle_locked = false
	_battle_walk_direction = 0
	set_physics_process(true)
	$CollisionShape2D.set_deferred("disabled", false)
	disable_hurtbox()
	# Restore to 1 HP minimum so the player can move after the battle.
	# FUTURE — HP restored to full or partial based on items/skills.
	# FUTURE — if both players were downed, defeat sequence triggers instead.
	if current_hp <= 0:
		current_hp = 1
		hp_changed.emit(current_hp, max_hp)
	# Force Idle animation even if state was already IDLE (avoids the
	# _set_state early-return guard leaving Die frame on screen).
	_set_state(State.IDLE)
	_sprite.play(&"Idle")

# ---------------------------------------------------------------------------

## Start walking in the given direction (-1 left, 1 right).
## Plays the Run animation in that direction and sets facing.
func battle_walk(direction: int) -> void:
	_battle_walk_direction = direction
	if direction == -1:
		_facing_direction = -1
	elif direction == 1:
		_facing_direction = 1

## Stop walking and return to Idle.
func battle_stop() -> void:
	_battle_walk_direction = 0
	_set_state(State.IDLE)

## Swap animation: DashStart → teleport to target → DashEnd → Idle.
## Called by BattleManager._do_swap_action() on both players simultaneously
## (no await at the call site so both coroutines run in parallel).
## Calls BattleManager.swap_player_done() when finished.
func perform_swap(target_position: Vector2) -> void:
	# Lock physics the same way perform_attack() does — BATTLE_ATTACK zeroes
	# velocity every frame and skips _update_state(), preventing friction or
	# floor-collision resolution from nudging the player during the animation.
	_set_state(State.BATTLE_ATTACK)
	var face_dir: float = sign(target_position.x - global_position.x)
	if face_dir != 0.0:
		_sprite.flip_h = face_dir < 0.0
	_sprite.play(&"DashStart")
	await _sprite.animation_finished

	global_position = target_position

	_sprite.play(&"DashEnd")
	await _sprite.animation_finished

	_sprite.play(&"Idle")
	_set_state(State.IDLE)
	BattleManager.swap_player_done()

# ---------------------------------------------------------------------------
# RESPAWN — called by hazards (e.g. Spike.gd) on player contact.
# Celeste-style reset: no HP lost, play Hit animation, brief pause, teleport.
# ---------------------------------------------------------------------------
func trigger_respawn() -> void:
	# FUTURE — to add HP damage on spike contact, call take_damage(1) here,
	# before _sprite.play("Hit"). This connects to the existing HP system
	# in Player.gd without any other changes needed.

	if _invincible_timer > 0.0 or _is_exiting:
		return

	# Prevent double triggers if the player overlaps multiple spike HitZones
	# at the same time.
	if _is_respawning:
		return
	_is_respawning = true

	# Stop all movement immediately.
	velocity = Vector2.ZERO

	# Disable physics so the player can't move or be affected by gravity
	# while the Hit animation is playing.
	set_physics_process(false)

	# Disable HoldDetector to prevent accidentally grabbing a background hold
	# mid-respawn.
	_hold_detector.monitoring = false

	# Arc the player up then back down. Physics is frozen so we tween position
	# directly — runs concurrently with the Hit animation (~0.25 s total).
	if respawn_bounce > 0.0:
		var start_y := global_position.y
		var tween := create_tween()
		tween.tween_property(self, "global_position:y", start_y - respawn_bounce, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(self, "global_position:y", start_y, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	# Play the Hit animation once. It is non-looping so it stops on the last
	# frame automatically.
	_sprite.play(&"Hit")

	# Wait for the full Hit animation to finish before doing anything else.
	await _sprite.animation_finished

	# Short pause so the hit registers visually before the teleport.
	await get_tree().create_timer(respawn_delay).timeout

	# Resolve spawn marker now (room is guaranteed loaded at respawn time).
	var spawn_node := get_tree().root.find_child(spawn_marker_name, true, false)
	if spawn_node:
		global_position = spawn_node.global_position
	else:
		push_warning("Player: spawn marker '%s' not found — staying at current position." % spawn_marker_name)

	# Re-enable physics and input.
	set_physics_process(true)
	_hold_detector.monitoring = true

	# Clear any velocity that accumulated before the respawn.
	velocity          = Vector2.ZERO
	_platform_velocity = Vector2.ZERO

	# Return to IDLE cleanly — resets state, collision capsule, and animation.
	_set_state(State.IDLE)

	# Brief flicker to signal the respawn visually to the player.
	if flash_on_respawn:
		await _flash_respawn()

	_is_respawning = false


func _flash_respawn() -> void:
	# Tween modulate.a (opacity) between 0 and 1 three times rapidly using the
	# existing modulate property on the player node.
	for i in 3:
		var tween := create_tween()
		tween.tween_property(self, "modulate:a", 0.0, 0.1)
		await tween.finished
		tween = create_tween()
		tween.tween_property(self, "modulate:a", 1.0, 0.1)
		await tween.finished
	# Guarantee full opacity in case something interrupted mid-flash.
	modulate.a = 1.0

# ---------------------------------------------------------------------------
# HP — PUBLIC API
# Call take_damage() and heal() from anywhere; they handle all clamping
# and signal emission so callers never touch current_hp directly.
# ---------------------------------------------------------------------------

## Reduce HP by amount.  Clamps to 0 and emits player_died if HP reaches 0.
func take_damage(amount: int) -> void:
	current_hp = clampi(current_hp - amount, 0, max_hp)
	hp_changed.emit(current_hp, max_hp)
	if current_hp <= 0:
		player_died.emit()   # death logic not yet implemented — hook here later

## Restore HP by amount.  Clamps to max_hp.
func heal(amount: int) -> void:
	current_hp = clampi(current_hp + amount, 0, max_hp)
	hp_changed.emit(current_hp, max_hp)
