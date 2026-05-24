## Enemy.gd
## Attach to a CharacterBody2D in Enemy.tscn.
## Enemies never have player-controlled input — BattleManager drives them directly.
## Attack choreography mirrors the player attack sequence exactly:
## same animations, same steps, just targeting players instead of enemies.
## FUTURE — different enemy types will override _do_attack_sequence() for unique patterns.

class_name Enemy
extends CharacterBody2D

@export var enemy_name: String = "Guard"
@export_range(1, 20, 1) var max_hp: int = 3
@export_range(0, 20, 1) var current_hp: int = 3
## Hidden combat stat — determines turn order. 0 ties with base player speed.
@export_range(0, 20, 1) var speed: int = 0

## Visual tint applied to the sprite. Default red distinguishes enemies from players.
@export var enemy_color: Color = Color(0.8, 0.1, 0.1, 1.0)

## Affects how far the combat camera zooms in during battle.
## FUTURE — combat camera reads this to choose zoom level.
@export_enum("small", "medium", "large", "boss") var size_category: String = "medium"

## Offset from the enemy's origin where attacking players teleport to.
## Adjust per enemy type in the Inspector — larger enemies may need more offset.
## FUTURE — multiple receive points for different attack types (aerial, sweep, etc.).
@export var attack_receive_offset: Vector2 = Vector2(-40.0, 0.0)

enum TargetingMode {
	LOWEST_HP,  ## Attack whichever living player has the least HP. Ties resolved randomly.
	CLOSEST,    ## Attack whichever living player is physically closest to this enemy.
}

@export_group("Battle")
## Pause between landing Punch01 and turning away to dash back.
## Mirrors player's same export. Tune per enemy type for different feel.
@export_range(0.0, 2.0, 0.05, "suffix:s") var attack_pause_duration: float = 0.2
## Determines which player this enemy prioritises when choosing a target.
@export var targeting_mode: TargetingMode = TargetingMode.LOWEST_HP

@export_group("Combat")
@export var hitbox_offset: Vector2 = Vector2(18, -5)
@export var hitbox_size: Vector2   = Vector2(12, 10)
@export var hurtbox_size: Vector2  = Vector2(16, 32)
## Damage dealt to a player per successful hit.
## FUTURE — scales with enemy type; boss enemies deal more damage.
## FUTURE — damage calculation mirrors player system: base + attack stat
## - target defense stat, minimum 1 always.
@export_range(1, 20, 1) var attack_damage: int = 1

## Cached base gravity from project settings.
var _base_gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")

@onready var _sprite        : AnimatedSprite2D = $AnimatedSprite2D
@onready var _hit_box       : Area2D           = $HitBox
@onready var _hit_box_shape : CollisionShape2D = $HitBox/HitBoxShape
@onready var _hurt_box      : Area2D           = $HurtBox

# Stored before teleporting so the enemy can return after attacking.
var _pre_attack_position: Vector2 = Vector2.ZERO
# The player node being attacked this sequence.
var _attack_target: Node2D = null
# Set by BattleManager at battle start so the enemy knows its room.
var _current_combat_room: Node = null

signal hp_changed(current: int, maximum: int)
signal enemy_died

# ---------------------------------------------------------------------------
# READY / PHYSICS
# ---------------------------------------------------------------------------

func _ready() -> void:
	add_to_group("enemies")
	modulate = enemy_color
	current_hp = clampi(current_hp, 0, max_hp)
	hp_changed.emit(current_hp, max_hp)
	_sprite.play("Idle")
	# HitBox: only active during Punch01.
	_hit_box.monitoring  = false
	_hit_box.monitorable = false
	_hit_box.collision_layer = 4
	_hit_box.collision_mask  = 4
	# HurtBox: disabled outside battle — BattleManager.start_battle() enables it.
	_hurt_box.monitoring  = false
	_hurt_box.monitorable = false
	_hurt_box.collision_layer = 4
	_hurt_box.collision_mask  = 4

func _physics_process(delta: float) -> void:
	# Apply gravity so the enemy stands on platforms correctly.
	# Suspended during attack sequence via set_physics_process(false).
	if not is_on_floor():
		velocity.y += _base_gravity * delta
	else:
		velocity.y = 0.0
	# FUTURE — BattleManager will set velocity.x during enemy turn animations.
	move_and_slide()

# ---------------------------------------------------------------------------
# HP
# ---------------------------------------------------------------------------

## Reduce HP by amount. Clamps to [0, max_hp] and emits hp_changed.
func take_damage(amount: int) -> void:
	current_hp = clampi(current_hp - amount, 0, max_hp)
	hp_changed.emit(current_hp, max_hp)
	if current_hp <= 0:
		enemy_died.emit()

## Restore HP by amount. Clamps to [0, max_hp] and emits hp_changed.
func heal(amount: int) -> void:
	current_hp = clampi(current_hp + amount, 0, max_hp)
	hp_changed.emit(current_hp, max_hp)

# ---------------------------------------------------------------------------
# ATTACK RECEIVE POINT — players teleport here when attacking this enemy
# ---------------------------------------------------------------------------

## Returns the world position where an attacking player should teleport.
## Move the AttackReceivePoint Marker2D in the editor to tune per enemy type.
func get_attack_receive_position() -> Vector2:
	return $AttackReceivePoint.global_position

# ---------------------------------------------------------------------------
# COMBAT ROOM REFERENCE — passed by BattleManager at battle start
# ---------------------------------------------------------------------------

## Called by BattleManager when a battle begins so the enemy knows which room
## it is in. Used to look up PlayerOneAttackReceivePoint and PlayerTwoAttackReceivePoint.
func set_combat_room(room: Node) -> void:
	_current_combat_room = room

# ---------------------------------------------------------------------------
# TARGET SELECTION
# ---------------------------------------------------------------------------

## Choose which player to attack based on targeting_mode.
## This lives on Enemy.gd (not BattleManager) so different enemy types
## can have different targeting logic without touching the manager.
func select_target(player_list: Array) -> Node2D:
	# Downed players are never targeted — enemy only attacks living players.
	# FUTURE — enemy may target a downed player for a finishing move if the
	# morality kill system is active.
	var active: Array = player_list.filter(
		func(p: Node) -> bool: return not (p as Player)._is_downed)

	if active.is_empty():
		return null
	if active.size() == 1:
		return active[0] as Node2D

	match targeting_mode:
		TargetingMode.CLOSEST:
			# Target whichever living player is physically nearest to this enemy.
			var closest: Node2D = null
			var closest_dist: float = INF
			for player in active:
				var p := player as Node2D
				if p == null:
					continue
				var d := global_position.distance_squared_to(p.global_position)
				if d < closest_dist:
					closest_dist = d
					closest = p
			return closest

		_:  # TargetingMode.LOWEST_HP (default)
			# Target the living player with the lowest HP. Ties resolved randomly.
			# FUTURE — targeting priority system:
			# status effects (poison, stun) influence targeting
			# boss may have scripted targets for story moments
			var lowest_hp: float = INF
			var candidates: Array = []
			for player in active:
				var p := player as Player
				if p == null:
					continue
				if p.current_hp < lowest_hp:
					lowest_hp  = p.current_hp
					candidates = [p]
				elif p.current_hp == lowest_hp:
					candidates.append(p)
			candidates.shuffle()
			return candidates[0] as Node2D

# ---------------------------------------------------------------------------
# ATTACK SEQUENCE — mirrors player attack choreography exactly
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
	# FUTURE — disable during enemy invincibility frames
	# FUTURE — disable during special attack wind-up if temporarily invulnerable

## Called by the attacker when its HitBox overlaps this enemy's HurtBox.
## damage: how many HP to subtract (default 1 — tuned via BattleManager).
func receive_hit(damage: int = 1) -> void:
	# Guard against double-hits while hurtbox is already disabled.
	if not _hurt_box.monitorable:
		return

	# Apply damage immediately so hp_changed fires and HUD can react.
	take_damage(damage)

	# If this hit drained the last HP, skip the Hit animation and go straight
	# to the defeat sequence. BattleManager.enemy_defeated() emits
	# hit_sequence_done so the attacker's coroutine continues cleanly.
	if current_hp <= 0:
		await _do_defeat_sequence()
		return

	# HP still > 0 — play the normal hit reaction.
	velocity = Vector2.ZERO
	disable_hurtbox()   # prevents double-hits during the animation
	_sprite.play(&"Hit")
	await _sprite.animation_finished
	await get_tree().create_timer(0.1).timeout
	enable_hurtbox()
	_sprite.play(&"Idle")
	BattleManager.hit_sequence_complete()
	# FUTURE — morality prompt appears when hp reaches 0 instead of
	# _do_defeat_sequence() directly; any player can choose kill or spare.

## Plays the Die animation and notifies BattleManager the enemy is defeated.
## Called from receive_hit() when HP reaches 0.
func _do_defeat_sequence() -> void:
	# Lock down the enemy completely so nothing can interact with it.
	disable_hurtbox()
	_disable_hitbox()
	velocity = Vector2.ZERO
	set_physics_process(false)
	# Disable world collision so the collapsed enemy doesn't block players.
	$CollisionShape2D.set_deferred("disabled", true)

	# Die animation — plays once and holds the last frame.
	# Enemy stays collapsed on the ground; not hidden or freed yet.
	_sprite.play(&"Die")
	await _sprite.animation_finished
	# FUTURE — morality prompt appears here before this sequence in the next
	# prompt: kill → player delivers final attack, spare → enemy stays collapsed.
	# Both paths lead to battle end.

	# Tell BattleManager this enemy is out of the fight.
	BattleManager.enemy_defeated(self)

# ---------------------------------------------------------------------------
# ATTACK SEQUENCE — mirrors player attack choreography exactly
# ---------------------------------------------------------------------------

## Entry point called by BattleManager._start_enemy_turn().
## Stores current position, suspends physics, then runs the choreography.
func perform_attack(target: Node2D) -> void:
	_attack_target       = target
	_pre_attack_position = global_position
	set_physics_process(false)   # prevent gravity interfering with teleports
	await _do_attack_sequence()
	set_physics_process(true)

## Enemy attack sequence mirrors the player attack sequence exactly.
## Same animations, same choreography — only target selection and receive
## point lookup differ.
## FUTURE — different enemy types will override this for unique patterns.
## Boss attacks may have multiple phases and telegraphed warning animations.
func _do_attack_sequence() -> void:
	# Step 1 — DashStart in place, facing toward the target player.
	var face_dir: float = sign(_attack_target.global_position.x - global_position.x)
	if face_dir != 0.0:
		_sprite.flip_h = face_dir < 0.0
	_sprite.play(&"DashStart")
	await _sprite.animation_finished

	# Step 2 — Teleport to the player's attack receive point.
	# Looked up from the combat room so each room can position it independently.
	var receive_pos: Vector2
	var player_id: int = (_attack_target as Player).player_id if _attack_target is Player else 1
	if _current_combat_room != null and _current_combat_room.has_method("get_player_receive_point"):
		receive_pos = _current_combat_room.get_player_receive_point(player_id)
	else:
		# Fallback: land directly on the player if no room marker is available.
		receive_pos = _attack_target.global_position
	global_position = receive_pos
	# Snap to floor after teleport. physics_process is suspended during the
	# attack sequence so gravity never runs — call move_and_slide() manually
	# with a small downward nudge so the depenetration resolves toward the floor
	# rather than floating. Works universally regardless of room layout or
	# receive point Y placement.
	velocity.y = _base_gravity
	move_and_slide()
	velocity.y = 0.0

	# Face toward the target player at the new position.
	face_dir = sign(_attack_target.global_position.x - global_position.x)
	if face_dir != 0.0:
		_sprite.flip_h = face_dir < 0.0

	# Step 3 — DashEnd at the receive point (landing animation).
	_sprite.play(&"DashEnd")
	await _sprite.animation_finished

	# Step 4 — Punch01 with live HitBox detection.
	var hit_detected: bool = false
	_enable_hitbox()
	_hit_box.area_entered.connect(func(area: Area2D) -> void:
		if area.name == "HurtBox":
			hit_detected = true
			_disable_hitbox()
			_attack_target.receive_hit(attack_damage)
	, CONNECT_ONE_SHOT)
	_sprite.play(&"Punch01")
	await _sprite.animation_finished
	_disable_hitbox()

	# Step 5 — Wait for hit reaction, or fall back to a brief pause on miss.
	# FUTURE — parry/guard window goes here: perfect timing = parry → 0 damage,
	# good timing = block → reduced damage.
	# FUTURE — hit_detected = false means parried/dodged — no damage applied.
	if hit_detected:
		await BattleManager.hit_sequence_done
	else:
		await get_tree().create_timer(attack_pause_duration).timeout

	# Step 6 — Turn AWAY from the player. Only this step faces away.
	_sprite.flip_h = face_dir > 0.0

	# Step 7 — DashStart facing away (launching back to battle position).
	_sprite.play(&"DashStart")
	await _sprite.animation_finished

	# Step 8 — Teleport back to battle position.
	global_position = _pre_attack_position

	# Step 9 — DashEnd back at battle position, facing toward players again.
	_sprite.flip_h = face_dir < 0.0
	_sprite.play(&"DashEnd")
	await _sprite.animation_finished

	# Step 10 — Return to Idle.
	# BattleManager awaits perform_attack() directly, so no callback needed here.
	_sprite.play(&"Idle")
