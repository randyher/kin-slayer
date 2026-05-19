## BattleManager.gd
## Global autoload — register in Project → Project Settings → Autoload as "BattleManager".
## Phase 1: handles locking players and triggering the walk-in intro only.
## Full turn logic, UI, and combat resolution are added in later phases.

extends Node

enum BattlePhase {
	INACTIVE,      # No battle running.
	INTRO,         # Walk-in cutscene playing — players walk to battle positions.
	PLAYER_TURN,   # FUTURE — player picks an action (Attack, Guard, Swap, Item).
	ENEMY_TURN,    # FUTURE — enemy executes its AI turn.
	VICTORY,       # FUTURE — all enemies defeated; victory sequence plays.
	DEFEAT         # FUTURE — all players defeated; game over sequence plays.
}

var current_phase: BattlePhase = BattlePhase.INACTIVE
var players: Array = []
var enemies: Array = []

## Fired when the walk-in cutscene finishes and the first turn is about to begin.
signal battle_intro_complete
## Fired the moment start_battle() is called — use this to fade in battle music, etc.
signal battle_started

## Call this from CombatRoom when all players have entered the room.
## Locks player input and starts the walk-in intro.
func start_battle(player_list: Array, enemy_list: Array) -> void:
	players = player_list
	enemies = enemy_list
	current_phase = BattlePhase.INTRO

	# Lock every player so only BattleManager controls their movement.
	for player in players:
		if player is Player:
			(player as Player).battle_locked = true

	battle_started.emit()

## Called by CombatRoom when all players have reached their battle positions.
## Transitions to PLAYER_TURN and fires battle_intro_complete.
func intro_complete() -> void:
	current_phase = BattlePhase.PLAYER_TURN
	# FUTURE — PLAYER_TURN will show button prompts above the active player.
	# Triangle = Attack, Circle = Guard, Square = Swap, Cross = Item.
	# FUTURE — turn order is calculated by comparing speed stats of all
	# participants. Ties are resolved randomly.
	# FUTURE — combat camera zoom reads enemy.size_category and adjusts
	# Camera2D zoom smoothly via tween before the first prompt appears.
	battle_intro_complete.emit()

## Unlock all players and reset phase. Called after battle ends (victory or defeat).
func end_battle() -> void:
	for player in players:
		if player is Player:
			(player as Player).battle_locked = false
			(player as Player).battle_stop()
	players.clear()
	enemies.clear()
	current_phase = BattlePhase.INACTIVE
