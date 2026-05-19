## Enemy.gd
## Attach to a CharacterBody2D in Enemy.tscn.
## Enemies never have player-controlled input — BattleManager drives them directly.
## Phase 1: enemy stands idle in its start position.
## FUTURE — enemy AI, attack patterns, and turn logic added in later phases.

class_name Enemy
extends CharacterBody2D

@export var enemy_name: String = "Guard"
@export_range(1, 20, 1) var max_hp: int = 3
@export_range(0, 20, 1) var current_hp: int = 3
## Hidden combat stat — determines turn order. 0 ties with base player speed.
@export_range(0, 20, 1) var speed: int = 0

## Visual tint applied to the sprite. Default is a red to distinguish from players.
@export var enemy_color: Color = Color(0.8, 0.1, 0.1, 1.0)

## Affects how far the combat camera zooms in during battle.
## FUTURE — combat camera reads this to choose zoom level.
@export_enum("small", "medium", "large", "boss") var size_category: String = "medium"

## Offset from the enemy's origin where attacking players teleport to.
## Negative x = to the left (players approach from the left by default).
## Adjust per enemy type in the Inspector.
## FUTURE — multiple receive points for different attack types
## (aerial attacks, sweeps, etc.).
@export var attack_receive_offset: Vector2 = Vector2(-40.0, 0.0)

## Cached base gravity from project settings.
var _base_gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D

signal hp_changed(current: int, maximum: int)
signal enemy_died

func _ready() -> void:
	add_to_group("enemies")
	modulate = enemy_color
	current_hp = clampi(current_hp, 0, max_hp)
	hp_changed.emit(current_hp, max_hp)
	_sprite.play("Idle")

func _physics_process(delta: float) -> void:
	# Apply gravity so the enemy stands on platforms correctly.
	if not is_on_floor():
		velocity.y += _base_gravity * delta
	else:
		velocity.y = 0.0
	# Enemy does not move on its own — velocity.x stays 0 until BattleManager directs it.
	# FUTURE — BattleManager will set velocity.x during enemy turn animations.
	move_and_slide()

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

## Returns the world position where an attacking player should teleport.
## Driven by the AttackReceivePoint Marker2D child — move that node in the
## editor to tune the position per enemy type.
## Larger enemies may need a greater offset so the player clears the sprite.
func get_attack_receive_position() -> Vector2:
	return $AttackReceivePoint.global_position
