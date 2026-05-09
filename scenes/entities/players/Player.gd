## Player.gd
## Attach to a CharacterBody2D node.
## Handles movement, jumping, and dashing for up to 2 local co-op players.
## All "feel" variables are @export so you can tune them live in the Inspector
## without touching code.

class_name Player
extends CharacterBody2D

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
@export_range(-800.0, -50.0, 10.0, "suffix:px/s") var jump_force: float = -330.0
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

@export_group("Dash")
## Horizontal speed (px/s) during a dash — overrides normal movement entirely.
@export_range(100.0, 1200.0, 10.0, "suffix:px/s") var dash_speed: float = 400.0
## How long (in seconds) a single dash lasts before normal movement resumes.
@export_range(0.05, 0.5, 0.01, "suffix:s") var dash_duration: float = 0.18
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
enum State { IDLE, RUN, JUMP, FALL, DASH, DUCK }

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
@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D

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
# READY
# ---------------------------------------------------------------------------
func _ready() -> void:
	modulate = player_color  # apply co-op tint to the entire node (sprite + children)
	_sprite.play("Idle")
	# Listen for non-looping animations finishing so we can hand off correctly.
	_sprite.animation_finished.connect(_on_animation_finished)

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

	# --- Tick all timers down by the elapsed time this frame ---
	_tick_timers(delta)

	# --- Run the logic for whichever state is currently active ---
	match state:
		State.IDLE, State.RUN:
			_process_ground(input, delta)
		State.DUCK:
			_process_duck(input, delta)
		State.JUMP, State.FALL:
			_process_air(input, delta)
		State.DASH:
			_process_dash(input, delta)

	# --- Apply the final velocity to the CharacterBody2D ---
	move_and_slide()

	# --- Detect landing now that is_on_floor() reflects this frame's collisions ---
	if is_on_floor() and not floor_last_frame:
		_on_landed()

	# --- Update facing direction and flip sprite to match ---
	if input.x != 0:
		_facing_direction = int(sign(input.x))
	_sprite.flip_h = _facing_direction == -1

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
var _jump_pressed: bool = false
var _jump_held: bool = false
var _dash_pressed: bool = false
var _down_held: bool = false

func _get_input() -> Vector2:
	var dir := Vector2.ZERO

	if player_id == 1:
		# --- Player 1: WASD + Space + Left Shift ---
		if Input.is_action_pressed("p1_right"):  dir.x += 1
		if Input.is_action_pressed("p1_left"):   dir.x -= 1
		_jump_pressed = Input.is_action_just_pressed("p1_jump")
		_jump_held    = Input.is_action_pressed("p1_jump")
		_dash_pressed = Input.is_action_just_pressed("p1_dash")
		_down_held    = Input.is_action_pressed("p1_down")
	else:
		# --- Player 2: Arrow Keys + Enter + Right Shift ---
		if Input.is_action_pressed("p2_right"):  dir.x += 1
		if Input.is_action_pressed("p2_left"):   dir.x -= 1
		_jump_pressed = Input.is_action_just_pressed("p2_jump")
		_jump_held    = Input.is_action_pressed("p2_jump")
		_dash_pressed = Input.is_action_just_pressed("p2_dash")
		_down_held    = Input.is_action_pressed("p2_down")

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
	elif not _down_held:
		_set_state(State.IDLE)

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

	# --- Coyote-time jump ---
	# Allow a jump if the coyote timer is still running (recently left a ledge)
	# OR if a normal jump was pressed.
	if _jump_pressed and _coyote_timer > 0.0:
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

	_jump_buffer_timer = maxf(_jump_buffer_timer - delta, 0.0)

	# Detect the exact frame the dash cooldown expires so we can replenish air
	# dashes. This means the cooldown IS the recharge timer — wait it out in the
	# air and your air dashes come back, no landing required.
	var cooldown_was_active := _dash_cooldown_timer > 0.0
	_dash_cooldown_timer = maxf(_dash_cooldown_timer - delta, 0.0)
	if cooldown_was_active and _dash_cooldown_timer == 0.0:
		_air_dashes_used = 0
	# _dash_timer is ticked inside _process_dash() so it only runs while dashing.

# ---------------------------------------------------------------------------
# STATE UPDATER
# Figures out which state the player should be in based on current conditions.
# Only called after movement so velocity is already updated for this frame.
# ---------------------------------------------------------------------------
func _update_state() -> void:
	# Never interrupt an active dash from outside _process_dash().
	if state == State.DASH and _dash_timer > 0.0:
		return

	if is_on_floor():
		if _down_held:
			_set_state(State.DUCK)
		elif abs(velocity.x) > 1.0 and not is_on_wall():
			_set_state(State.RUN)
		else:
			_set_state(State.IDLE)
	else:
		if velocity.y < 0.0:
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
	if _sprite.animation == &"DoubleJump" and _sprite.is_playing():
		if new_state == State.JUMP or new_state == State.FALL:
			state = new_state
			return
	state = new_state
	match state:
		State.IDLE: _sprite.play("Idle")
		State.RUN:  _sprite.play("Run")
		State.DUCK: _sprite.play("Crouch")
		State.JUMP: _sprite.play("JumpRise")
		State.FALL: _sprite.play("JumpFall")
		State.DASH: _sprite.play("DashLoop")
	# TODO: emit a signal (state_changed) for BattleManager / UI to react to.

# ---------------------------------------------------------------------------
# ANIMATION FINISHED CALLBACK
# Fires when any non-looping animation reaches its last frame.
# Used to hand off from committed one-shot animations back to the live state.
# ---------------------------------------------------------------------------
func _on_animation_finished() -> void:
	# Once the double jump flip plays through completely, resume whichever air
	# animation is correct for the player's current velocity at that moment.
	if _sprite.animation == &"DoubleJump":
		_sprite.play("JumpFall" if velocity.y >= 0.0 else "JumpRise")
