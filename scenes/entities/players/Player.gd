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
@export_range(0.0, 0.3, 0.01, "suffix:s") var ledge_coyote_time: float = 0.10
## Seconds after the ledge raycasts first detect a grabbable ledge during which
## the grab will fire the moment can_grip becomes true.  Forgives briefly exhausted
## stamina or an active cooldown at the exact frame the ledge is passed.
@export_range(0.0, 0.3, 0.01, "suffix:s") var ledge_grab_buffer_time: float = 0.10

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
## Single toggle that disables BOTH wall climbing AND automatic ledge grabbing.
@export var wall_climb_enabled: bool = true
## If false, LedgeHangIdle does not drain stamina — player can hang indefinitely.
@export var ledge_hang_idle_drains_stamina: bool = true
## Pixels to nudge the player upward the moment they grab a ledge.
## Increase to make the hands appear higher on the ledge edge.
@export_range(0.0, 32.0, 1.0, "suffix:px") var ledge_hang_snap_up: float = 5.0

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
enum State { IDLE, RUN, JUMP, FALL, DASH, DUCK, CRAWL, WALL_SLIDE, WALL_CLIMB, LEDGE_HANG, LEDGE_CLIMB, HANG_IDLE, HANG_MOVE, HANG_EDGE }

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

# Wall coyote time — counts down after the player leaves a wall slide.
# While > 0 a wall jump is still permitted even though is_on_wall() is false.
# Mirrors _coyote_timer exactly, but for walls instead of floors.
var _wall_coyote_timer: float = 0.0

# Last wall normal captured while wall-sliding.
# Preserved so _start_wall_jump() can use the correct push direction during
# the coyote window, when is_on_wall() is no longer true.
var _last_wall_normal: Vector2 = Vector2.ZERO

# ---------------------------------------------------------------------------
# READY
# ---------------------------------------------------------------------------
func _ready() -> void:
	add_to_group("players")  # lets RoomManager, RoomCamera, and HUD find all players
	modulate = player_color  # apply co-op tint to the entire node (sprite + children)
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

	# --- Apply the final velocity to the CharacterBody2D ---
	move_and_slide()

	# --- Detect landing now that is_on_floor() reflects this frame's collisions ---
	if is_on_floor() and not floor_last_frame:
		_on_landed()

	# --- Update facing direction and flip sprite to match ---
	# Locked during ledge hang/climb AND background hang states.
	# Back-view Climb animations look correct regardless of direction,
	# so we freeze flip_h to prevent a jarring mirror on direction change.
	var ledge_locked := (state == State.LEDGE_HANG or state == State.LEDGE_CLIMB
						 or state == State.HANG_IDLE or state == State.HANG_MOVE
						 or state == State.HANG_EDGE)
	if state == State.HANG_EDGE:
		# ClimbJumpPrepare is a single animation — flip it for the right edge.
		_sprite.flip_h = (_hang_edge_dir == -1)
	else:
		if input.x != 0 and not ledge_locked:
			_facing_direction = int(sign(input.x))
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
## Grip button — universal "maintain contact" action (p1_grip / p2_grip).
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
	var dir := Vector2.ZERO

	if player_id == 1:
		if Input.is_action_pressed("p1_right"):      dir.x += 1
		if Input.is_action_pressed("p1_left"):       dir.x -= 1
		_jump_pressed = Input.is_action_just_pressed("p1_jump")
		_jump_held    = Input.is_action_pressed("p1_jump")
		_dash_pressed = Input.is_action_just_pressed("p1_dash")
		_down_held    = Input.is_action_pressed("p1_down")
		_grip_held         = Input.is_action_pressed("p1_grip")
		_grip_just_pressed = Input.is_action_just_pressed("p1_grip")
		_up_pressed        = Input.is_action_just_pressed("p1_up")
		_up_held           = Input.is_action_pressed("p1_up")
	else:
		if Input.is_action_pressed("p2_right"):      dir.x += 1
		if Input.is_action_pressed("p2_left"):       dir.x -= 1
		_jump_pressed      = Input.is_action_just_pressed("p2_jump")
		_jump_held         = Input.is_action_pressed("p2_jump")
		_dash_pressed      = Input.is_action_just_pressed("p2_dash")
		_down_held         = Input.is_action_pressed("p2_down")
		_grip_held         = Input.is_action_pressed("p2_grip")
		_grip_just_pressed = Input.is_action_just_pressed("p2_grip")
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
	if _dash_pressed and _dash_cooldown_timer <= 0.0:
		_start_dash(input.x)

# ---------------------------------------------------------------------------
# DUCK
# Player is crouched on the ground. Horizontal movement is suppressed.
# Releasing the down key exits back to IDLE. Jump input still fires a jump.
# ---------------------------------------------------------------------------
func _process_duck(input: Vector2, _delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, friction * _delta)
	velocity.y += _base_gravity * _delta

	if _jump_pressed or _jump_buffer_timer > 0.0:
		_start_jump()
	elif not _down_held and _can_stand():
		_set_state(State.IDLE)
	# If down is released but ceiling blocks standing, stay ducked silently.

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
	# Gentle constant press into the wall so is_on_wall() stays true each frame.
	velocity.x = float(_facing_direction) * 20.0

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
	if _up_held:
		velocity.y = -wall_climb_speed
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
	# Override all velocity — the player is locked to the ledge.
	velocity = Vector2.ZERO

	if _jump_pressed:
		# Wall jump away from the ledge. _last_wall_normal is cached from the
		# wall contact that preceded the hang; fall back to facing direction if
		# somehow zero (e.g. player jumped directly onto the ledge).
		if _last_wall_normal == Vector2.ZERO:
			_last_wall_normal = Vector2(-float(_facing_direction), 0.0)
		_ledge_grab_cooldown = 0.25
		_start_wall_jump()
		return

	elif _up_pressed:
		_ledge_hang_position = global_position   # save for climb-up offset
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
	if _dash_pressed and air_dash_allowed:
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
	if not is_on_floor() and _dash_pressed and air_dash_allowed:
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

	# Ledge coyote and grab buffer — both fed from the same raycast snapshot.
	# Coyote: mirrors floor coyote — stays fresh while ledge is visible, then
	#         decays, giving a short window to grab after drifting past the edge.
	# Buffer: also set while ledge is visible so the grab fires the moment
	#         can_grip becomes true, even if raycasts have since lost the ledge.
	var _ledge_in_range := (_ledge_check_lower.is_colliding()
							and not _ledge_check_upper.is_colliding())
	if _ledge_in_range:
		_ledge_coyote_timer      = ledge_coyote_time
		_ledge_grab_buffer_timer = ledge_grab_buffer_time
		_ledge_detected_y        = global_position.y   # freeze the ideal hang height
	else:
		_ledge_coyote_timer      = maxf(_ledge_coyote_timer      - delta, 0.0)
		_ledge_grab_buffer_timer = maxf(_ledge_grab_buffer_timer - delta, 0.0)

	# Cooldown only prevents rapid re-dashing — it no longer restores air dashes.
	# Air dashes restore exclusively on landing (see _on_landed).
	_dash_cooldown_timer = maxf(_dash_cooldown_timer - delta, 0.0)
	# _dash_timer is ticked inside _process_dash() so it only runs while dashing.

# ---------------------------------------------------------------------------
# WALL HELPER
# Returns true only if the player is touching a non-player wall surface.
# is_on_wall() alone returns true when leaning on another CharacterBody2D
# (i.e. another player), which would let players climb each other.
# get_slide_collision() lets us inspect the actual collider and skip Players.
# ---------------------------------------------------------------------------
func _is_on_climbable_wall() -> bool:
	if not is_on_wall():
		return false
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		if col.get_collider() is Player:
			continue
		# A wall contact has a predominantly horizontal normal (|x| > |y|).
		if abs(col.get_normal().x) > abs(col.get_normal().y):
			return true
	return false

# ---------------------------------------------------------------------------
# STAND CHECK
# Returns true if there is vertical clearance for the player to stand up.
# Temporarily enables the standing shape and uses test_move to detect any
# ceiling geometry that would block the transition from duck/crawl to IDLE/RUN.
# ---------------------------------------------------------------------------
func _can_stand() -> bool:
	_collision_stand.disabled = false
	_collision_duck.disabled  = true
	var blocked := test_move(global_transform, Vector2.ZERO)
	_collision_stand.disabled = true
	_collision_duck.disabled  = false
	return not blocked

# ---------------------------------------------------------------------------
# STATE UPDATER
# Figures out which state the player should be in based on current conditions.
# Only called after movement so velocity is already updated for this frame.
# ---------------------------------------------------------------------------
func _update_state() -> void:
	# Never interrupt an active dash from outside _process_dash().
	if state == State.DASH and _dash_timer > 0.0:
		return

	# Ledge and background-hold states are managed entirely by their own
	# process functions — don't let _update_state override them mid-hang.
	if state == State.LEDGE_HANG or state == State.LEDGE_CLIMB \
			or state == State.HANG_IDLE or state == State.HANG_MOVE \
			or state == State.HANG_EDGE:
		return

	# Evaluated in both branches below, so defined once here.
	var can_grip := wall_climb_enabled and not _stamina_exhausted and _stamina > 0.0

	if is_on_floor():
		# Wall climb takes priority even from the ground — if the player is
		# standing against a wall, holding grip, and has stamina, let them
		# transition directly into the climb without needing to jump first.
		if _is_on_climbable_wall() and _grip_held and can_grip:
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
				and (_ledge_coyote_timer > 0.0 or _ledge_grab_buffer_timer > 0.0):
			_set_state(State.LEDGE_HANG)

		# 2. WALL CLIMB — grip held + on climbable wall, no ledge in the way.
		elif _is_on_climbable_wall() and _grip_held and can_grip:
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
		if new_state in [State.JUMP, State.FALL, State.WALL_SLIDE, State.WALL_CLIMB]:
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
	match state:
		State.IDLE:        _sprite.play("Idle")
		State.RUN:         _sprite.play("Run")
		State.DUCK:        _sprite.play("Crouch")
		State.CRAWL:       _sprite.play("Crawl")
		State.JUMP:        _sprite.play("JumpRise")
		State.FALL:        _sprite.play("JumpFall")
		State.DASH:        _sprite.play("DashLoop")
		State.WALL_SLIDE:  _sprite.play("WallSlide")
		State.WALL_CLIMB:  _sprite.play("WallClimb")   # _process_wall_climb updates this each frame
		State.LEDGE_HANG:
			# Snap to the Y recorded when the raycasts first saw the ledge, then
			# apply the visual nudge.  This keeps the hang height consistent whether
			# the grab fired immediately or via the coyote / buffer window.
			global_position.y = _ledge_detected_y - ledge_hang_snap_up
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
		_set_state(State.IDLE)

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
