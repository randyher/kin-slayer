## GameManager.gd
## Global singleton — registered in Project → Project Settings → Autoload as "GameManager".
## Must be listed BEFORE RoomManager and BattleManager in the Autoload order.
##
## GameManager is the single source of truth for game-wide settings.
## FUTURE — difficulty settings here
## FUTURE — morality score tracked here
## FUTURE — global flags for story state
##
## FUTURE — online multiplayer mode would add additional player count options;
##   single_player_mode would become player_count: int
##
## FUTURE — dynamic player join: P2 can join mid session by pressing start,
##   re-enables the disabled P2 node, adds back to "players" group,
##   RoomManager spawns at current room

extends Node

## Toggle in the Inspector to switch between 1-player and 2-player mode.
## true  = only P1 exists, P2 disabled
## false = both players active (default)
@export var single_player_mode: bool = false

## Returns how many players are active this session.
func get_active_player_count() -> int:
	return 1 if single_player_mode else 2

## Returns true when only Player 1 is active.
func is_single_player() -> bool:
	return single_player_mode
