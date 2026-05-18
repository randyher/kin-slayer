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

extends StaticBody2D

## Reserved for future hazard variety — lets other systems query what kind of
## hazard this is without needing a separate node type per hazard.
@export var hazard_type: String = "spike"

func _ready() -> void:
	add_to_group("hazards")
	# Connect the HitZone's body_entered signal so we know when a physics body
	# (like the player's CharacterBody2D) enters the spike's danger area.
	$HitZone.body_entered.connect(_on_hit_zone_body_entered)

func _on_hit_zone_body_entered(body: Node2D) -> void:
	# Player is the only CharacterBody2D on collision layer 1 that can be a player.
	# Using `is Player` avoids calling trigger_respawn() on an untyped Node2D,
	# which is a hard compile error in Godot 4.3+.
	if body is Player:
		(body as Player).trigger_respawn()
