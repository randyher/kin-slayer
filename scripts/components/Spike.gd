## Spike.gd
## Attach to a StaticBody2D. Detects player contact via the child Area2D named
## HitZone and calls trigger_respawn() on the player — no HP damage, Celeste-style.
##
## FUTURE — hazard_type export can trigger different player animations or effects
## per hazard. Example: "fire" hazard could play a different hit animation or
## apply a burn status effect later.
##
## FUTURE — spikes currently do not reduce HP.
## This is intentional for overworld hazards.
## Battle system damage is handled separately via take_damage() in BattleManager.

@tool  # runs in the editor so hit_size changes are visible immediately in the 2D viewport
extends StaticBody2D

## Reserved for future hazard variety — lets other systems query what kind of
## hazard this is without needing a separate node type per hazard.
@export var hazard_type: String = "spike"

## Size of the kill zone in pixels (width × height).
## Each instance gets its own shape so changing one spike never affects others.
## Resize this in the Inspector — the hitbox updates instantly in the 2D editor.
@export var hit_size: Vector2 = Vector2(14, 6):
	set(value):
		hit_size = value
		_update_hit_shape()

func _ready() -> void:
	_update_hit_shape()
	if Engine.is_editor_hint():
		return  # Don't connect signals or join groups while running in the editor.
	add_to_group("hazards")
	$HitZone.body_entered.connect(_on_hit_zone_body_entered)

func _update_hit_shape() -> void:
	# get_node_or_null is safe to call before _ready() finishes (e.g. when the
	# setter fires during scene load before child nodes are accessible).
	var col := get_node_or_null("HitZone/CollisionShape2D") as CollisionShape2D
	if col == null:
		return
	var shape := RectangleShape2D.new()
	shape.size = hit_size
	col.shape = shape

func _on_hit_zone_body_entered(body: Node2D) -> void:
	# Player is the only CharacterBody2D on collision layer 1 that can be a player.
	# Using `is Player` avoids calling trigger_respawn() on an untyped Node2D,
	# which is a hard compile error in Godot 4.3+.
	if body is Player:
		(body as Player).trigger_respawn()
