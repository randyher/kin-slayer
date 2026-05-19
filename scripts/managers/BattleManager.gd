## BattleManager.gd
## Global autoload — register in Project → Project Settings → Autoload as "BattleManager".
## Phase 2: turn cycling (Player → Player → Enemy → repeat) + action menu handoff.
## Full combat resolution (attacks, damage, status) added in Phase 3.

extends Node

enum BattlePhase {
	INACTIVE,      # No battle running.
	INTRO,         # Walk-in cutscene playing — players walk to battle positions.
	PLAYER_TURN,   # Active player picks an action via BattleActionMenu.
	ENEMY_TURN,    # Enemy executes its turn (timer placeholder for now).
	VICTORY,       # FUTURE — all enemies defeated; victory sequence plays.
	DEFEAT         # FUTURE — all players defeated; game over sequence plays.
}

var current_phase: BattlePhase = BattlePhase.INACTIVE
var players: Array = []
var enemies: Array = []

## Ordered list of turn entries. Each entry: { entity, type, speed }.
var _turn_order: Array = []
var _current_turn_index: int = 0

## Reference to the BattleActionMenu node in World.tscn.
## Resolved once in _ready() via the "battle_ui" group.
var _action_menu: Node = null

# ---------------------------------------------------------------------------
# SIGNALS
# ---------------------------------------------------------------------------

## Fired the moment start_battle() is called.
signal battle_started
## Fired when the walk-in intro finishes and the first turn begins.
signal battle_intro_complete

# ---------------------------------------------------------------------------
# READY
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Wait one frame so World.tscn is fully built before we search for the menu.
	await get_tree().process_frame
	var menus := get_tree().get_nodes_in_group("battle_ui")
	if menus.size() > 0:
		_action_menu = menus[0]

# ---------------------------------------------------------------------------
# BATTLE START  (called by CombatRoom)
# ---------------------------------------------------------------------------

## Lock all players and start the walk-in intro.
func start_battle(player_list: Array, enemy_list: Array) -> void:
	players = player_list
	enemies = enemy_list
	current_phase = BattlePhase.INTRO

	for player in players:
		if player is Player:
			(player as Player).battle_locked = true

	battle_started.emit()

# ---------------------------------------------------------------------------
# INTRO COMPLETE  (called by CombatRoom after walk-in finishes)
# ---------------------------------------------------------------------------

## Build the turn order and start the first turn.
func intro_complete() -> void:
	current_phase = BattlePhase.PLAYER_TURN
	battle_intro_complete.emit()
	_build_turn_order()
	_start_next_turn()

# ---------------------------------------------------------------------------
# TURN ORDER
# ---------------------------------------------------------------------------

func _build_turn_order() -> void:
	_turn_order.clear()
	_current_turn_index = 0

	for player in players:
		_turn_order.append({ "entity": player, "type": "player", "speed": 0 })

	for enemy in enemies:
		_turn_order.append({
			"entity": enemy,
			"type": "enemy",
			"speed": enemy.speed if enemy.has_method("get") else 0
		})

	# Randomise ties, then stable-sort descending by speed.
	# FUTURE — weapon speed bonuses apply here; items granting haste affect
	# sort order; boss speed increases when below half HP.
	_turn_order.shuffle()
	_turn_order.sort_custom(func(a, b): return a.speed > b.speed)

func _start_next_turn() -> void:
	if _turn_order.is_empty():
		return

	var current: Dictionary = _turn_order[_current_turn_index]

	match current.type:
		"player":
			current_phase = BattlePhase.PLAYER_TURN
			_start_player_turn(current.entity)
		"enemy":
			current_phase = BattlePhase.ENEMY_TURN
			_start_enemy_turn(current.entity)

# ---------------------------------------------------------------------------
# PLAYER TURN
# ---------------------------------------------------------------------------

func _start_player_turn(player: Node) -> void:
	if _action_menu == null:
		push_warning("BattleManager: BattleActionMenu not found — skipping player turn.")
		_advance_turn()
		return
	_action_menu.show_for_player(player)

# ---------------------------------------------------------------------------
# ENEMY TURN
# ---------------------------------------------------------------------------

func _start_enemy_turn(_enemy: Node) -> void:
	# Placeholder — enemy waits then passes.
	# FUTURE — enemy telegraphs its target first (glow toward target player),
	# then selects an attack pattern. Special attacks trigger bullet-hell phase.
	await get_tree().create_timer(
		_action_menu.enemy_turn_duration if _action_menu else 1.5
	).timeout
	_advance_turn()

# ---------------------------------------------------------------------------
# ACTION SELECTED  (called by BattleActionMenu after player picks)
# ---------------------------------------------------------------------------

## Receives the chosen action name and routes it to the correct handler.
func action_selected(action: String) -> void:
	match action:
		"attack":
			_do_attack_action()
		"guard":
			# FUTURE — parry stance + input timing window.
			print("BattleManager: Guard — coming in Phase 3")
			_advance_turn()
		"swap":
			# FUTURE — front/back position swap between players.
			print("BattleManager: Swap — coming in Phase 3")
			_advance_turn()
		"item":
			# FUTURE — inventory selection submenu.
			print("BattleManager: Item — coming in Phase 3")
			_advance_turn()

func _do_attack_action() -> void:
	var current: Dictionary = _turn_order[_current_turn_index]
	var attacker: Node = current.entity

	# Target the first enemy for now.
	# FUTURE — target selection UI when multiple enemies exist:
	# highlight enemies with a cursor, player confirms target before attacking.
	if enemies.is_empty():
		_advance_turn()
		return

	var target: Node = enemies[0]
	if attacker is Player:
		(attacker as Player).perform_attack(target)
	# Turn advances via attack_sequence_complete() once the player finishes.

## Called by Player at the end of _do_attack_sequence().
## Advances the turn after a brief pause.
func attack_sequence_complete() -> void:
	# FUTURE — check enemy HP after damage resolution here.
	# if target.current_hp <= 0 → remove from turn_order, play death animation,
	# check for victory condition.
	await get_tree().create_timer(0.3).timeout
	_advance_turn()

# ---------------------------------------------------------------------------
# ADVANCE TURN
# ---------------------------------------------------------------------------

func _advance_turn() -> void:
	if _turn_order.is_empty():
		return
	_current_turn_index = (_current_turn_index + 1) % _turn_order.size()
	await get_tree().create_timer(0.3).timeout
	_start_next_turn()

# ---------------------------------------------------------------------------
# END BATTLE
# ---------------------------------------------------------------------------

## Unlock all players and reset state. Call on victory or defeat.
func end_battle() -> void:
	for player in players:
		if player is Player:
			(player as Player).battle_locked = false
			(player as Player).battle_stop()

	if _action_menu:
		_action_menu.visible = false

	players.clear()
	enemies.clear()
	_turn_order.clear()
	_current_turn_index = 0
	current_phase = BattlePhase.INACTIVE
