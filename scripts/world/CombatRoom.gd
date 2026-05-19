## CombatRoom.gd
## Attach to a room scene that contains a CombatRoomTrigger Area2D.
## When all players enter the trigger zone, locks their input and walks them
## to their battle positions for the intro cutscene.
##
## Node requirements:
##   CombatRoomTrigger — Area2D covering the full room; detects all players
##   BattlePositionP1  — Marker2D: where P1 stops during intro
##   BattlePositionP2  — Marker2D: where P2 stops during intro
##   EnemyContainer    — Node2D: parent of all enemy instances in this room

class_name CombatRoom
extends Room

@onready var _trigger         : Area2D   = $CombatRoomTrigger
@onready var _pos_p1          : Marker2D = $BattlePositionP1
@onready var _pos_p2          : Marker2D = $BattlePositionP2
@onready var _enemy_container : Node2D   = $EnemyContainer

var _players_in_room : Array = []
var _battle_started  : bool  = false
## How close (px) a player must be to their marker before they stop walking.
var _arrival_threshold: float = 8.0

func _ready() -> void:
	super._ready()   # Room._ready() connects exit signals
	_trigger.body_entered.connect(_on_trigger_body_entered)

func _physics_process(_delta: float) -> void:
	# Only check arrival while the intro is running.
	if not _battle_started or BattleManager.current_phase != BattleManager.BattlePhase.INTRO:
		return
	_check_player_arrival()

# ---------------------------------------------------------------------------
# TRIGGER
# ---------------------------------------------------------------------------

func _on_trigger_body_entered(body: Node2D) -> void:
	if not (body is Player):
		return
	if body in _players_in_room:
		return
	_players_in_room.append(body)

	var all_players := get_tree().get_nodes_in_group("players")
	if _players_in_room.size() >= all_players.size() and not _battle_started:
		_start_battle_intro()

# ---------------------------------------------------------------------------
# INTRO SEQUENCE
# ---------------------------------------------------------------------------

func _start_battle_intro() -> void:
	_battle_started = true
	var all_players := get_tree().get_nodes_in_group("players")
	var all_enemies := _enemy_container.get_children()

	# Lock players and notify BattleManager.
	BattleManager.start_battle(all_players, all_enemies)

	# Walk every player toward their battle position.
	# Players always enter from the right so they walk left.
	# FUTURE — detect entry direction and walk accordingly.
	for player in all_players:
		if player is Player:
			(player as Player).battle_walk(-1)

func _check_player_arrival() -> void:
	var all_players := get_tree().get_nodes_in_group("players")
	var all_arrived  := true

	for player in all_players:
		if not (player is Player):
			continue
		var p := player as Player
		# Match each player to their marker by player_id.
		var target_x: float
		if p.player_id == 1:
			target_x = _pos_p1.global_position.x
		else:
			target_x = _pos_p2.global_position.x

		if abs(p.global_position.x - target_x) > _arrival_threshold:
			all_arrived = false
		else:
			p.battle_stop()   # already there — stop this one

	if all_arrived:
		set_physics_process(false)   # stop checking
		_on_intro_complete()

func _on_intro_complete() -> void:
	# Brief dramatic pause before handing off to the turn system.
	await get_tree().create_timer(0.5).timeout
	BattleManager.intro_complete()
	# FUTURE — battle UI (action menu, HP bars, turn order display) appears here.
	# FUTURE — victory condition: all enemies hp <= 0 → victory sequence.
	# FUTURE — defeat condition: all players hp <= 0 → defeat sequence.
