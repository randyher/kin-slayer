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
# PlayerOneAttackReceivePoint and PlayerTwoAttackReceivePoint are Marker2D nodes.
# Move them in the editor per room — enemy teleports HERE when attacking that player.
# Position them slightly in front of each player toward the enemy for best visual read.
@onready var _receive_p1      : Marker2D = $PlayerOneAttackReceivePoint
@onready var _receive_p2      : Marker2D = $PlayerTwoAttackReceivePoint

var _players_in_room : Array = []
var _battle_started  : bool  = false
## Generous arrival window so physics overshoot (player stops past the marker)
## still counts as arrived. 32 px covers ~20 px of typical wall-stop overshoot
## with room to spare regardless of which direction the player enters from.
var _arrival_threshold: float = 32.0

func _ready() -> void:
	super._ready()   # Room._ready() connects exit signals
	add_to_group("combat_rooms")   # BattleManager finds this room via the group
	print("DEBUG: CombatRoom _ready — _trigger=%s" % str(_trigger))
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
	print("DEBUG: trigger body_entered — body=%s is_player=%s" % [body.name, str(body is Player)])
	if not (body is Player):
		return
	if body in _players_in_room:
		return
	_players_in_room.append(body)

	var all_players := get_tree().get_nodes_in_group("players")
	print("DEBUG: players_in_room=%d / all_players=%d" % [_players_in_room.size(), all_players.size()])
	if _players_in_room.size() >= all_players.size() and not _battle_started:
		_start_battle_intro()

# ---------------------------------------------------------------------------
# INTRO SEQUENCE
# ---------------------------------------------------------------------------

func _start_battle_intro() -> void:
	print("DEBUG: _start_battle_intro called")
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

## NOTE on arrival detection: use a generous threshold (default 32 px).
## Players walk at physics speed and can overshoot a marker by 10–20 px before
## a wall stops them. A tight threshold (< overshoot distance) means the player
## permanently sits outside the zone and the intro never completes.
## Entry direction varies per room, so do NOT replace this with a directional
## check (player.x <= target_x) — that only works for leftward entry.
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
			p.battle_stop()   # close enough — stop

	if all_arrived:
		set_physics_process(false)   # stop checking
		_on_intro_complete()

func _on_intro_complete() -> void:
	print("DEBUG: _on_intro_complete — waiting 0.5s")
	# Brief dramatic pause before handing off to the turn system.
	await get_tree().create_timer(0.5).timeout
	print("DEBUG: calling BattleManager.intro_complete()")
	BattleManager.intro_complete()
	# FUTURE — battle UI (action menu, HP bars, turn order display) appears here.
	# FUTURE — victory condition: all enemies hp <= 0 → victory sequence.
	# FUTURE — defeat condition: all players hp <= 0 → defeat sequence.

# ---------------------------------------------------------------------------
# ATTACK RECEIVE POINTS — where the enemy lands when attacking each player
# ---------------------------------------------------------------------------

## Returns the world position of the attack receive marker for the given player.
## Called by Enemy._do_attack_sequence() when it teleports toward a player.
## Move the Marker2D nodes in the editor to tune the landing spot per room.
func get_player_receive_point(player_id: int) -> Vector2:
	match player_id:
		1: return _receive_p1.global_position if _receive_p1 != null else Vector2.ZERO
		2: return _receive_p2.global_position if _receive_p2 != null else Vector2.ZERO
		_: return Vector2.ZERO
