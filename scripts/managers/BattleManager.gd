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
## Reference to the ActionCommand timing node in World.tscn.
## Resolved once in _ready() by node path. Used by Player._do_attack_sequence()
## to show the shrinking circle timing indicator during combo hits.
var _action_command: Node = null
## The active CombatRoom — stored at battle start so swap can update receive points.
var _combat_room: Node = null
## Counts how many players have finished their swap animation.
var _swap_players_done: int = 0
## Set to true by player_downed() or enemy_defeated() when they take over turn
## management mid-sequence. _start_enemy_turn() checks this before calling
## _advance_turn() so the two paths don't double-advance the turn.
var _turn_advanced: bool = false

# ---------------------------------------------------------------------------
# SIGNALS
# ---------------------------------------------------------------------------

## Fired the moment start_battle() is called.
signal battle_started
## Fired when the walk-in intro finishes and the first turn begins.
signal battle_intro_complete
## Fired by hit_sequence_complete() so the attacker knows the hit reaction is done.
signal hit_sequence_done
## Fired internally once both players have finished their swap animations.
signal _swap_complete
## Fired by end_battle() after all players are unlocked and state is cleared.
signal battle_ended

# ---------------------------------------------------------------------------
# READY
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Wait one frame so World.tscn is fully built before we search for UI nodes.
	await get_tree().process_frame
	var menus := get_tree().get_nodes_in_group("battle_ui")
	if menus.size() > 0:
		_action_menu = menus[0]
	var cmds := get_tree().get_nodes_in_group("action_command")
	if cmds.size() > 0:
		_action_command = cmds[0]

# ---------------------------------------------------------------------------
# BATTLE START  (called by CombatRoom)
# ---------------------------------------------------------------------------

## Lock all players, pass room reference to enemies, and start the walk-in intro.
## players array is built from get_nodes_in_group("players") in CombatRoom —
## single player mode works automatically because P2 is not in the group.
func start_battle(player_list: Array, enemy_list: Array) -> void:
	players = player_list
	enemies = enemy_list
	current_phase = BattlePhase.INTRO

	# Pass the combat room reference to each enemy so they can look up
	# player attack receive points during their turn.
	var combat_rooms := get_tree().get_nodes_in_group("combat_rooms")
	_combat_room = combat_rooms.front() if not combat_rooms.is_empty() else null
	for enemy in enemies:
		if enemy.has_method("set_combat_room"):
			enemy.set_combat_room(_combat_room)

	for player in players:
		if player is Player:
			(player as Player).battle_locked = true

	# Enable hurtboxes so entities can receive hits during battle.
	for player in players:
		if player.has_method("enable_hurtbox"):
			player.enable_hurtbox()
	for enemy in enemies:
		if enemy.has_method("enable_hurtbox"):
			enemy.enable_hurtbox()

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

	# Only players in the "players" group participate — single player = only P1 here.
	# P2 not in group = not in battle = not in turn order. No special casing needed.
	# FUTURE — sort by speed stat when weapons and items that affect initiative exist.
	# FUTURE — randomise ties when speed stats differ, boss speed increases at low HP.
	for player in players:
		_turn_order.append({ "entity": player, "type": "player" })

	for enemy in enemies:
		_turn_order.append({ "entity": enemy, "type": "enemy" })

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

func _start_enemy_turn(enemy: Node) -> void:
	current_phase = BattlePhase.ENEMY_TURN
	_turn_advanced = false   # reset for this turn

	# Brief pause before the enemy acts — feels more deliberate and readable.
	await get_tree().create_timer(0.5).timeout

	# Select target and run attack. We await the whole sequence so _advance_turn()
	# is always called exactly once, regardless of whether the attack succeeded.
	# FUTURE — enemy may choose actions other than attack:
	# low HP → defensive buff, turn 3 → big telegraph, special → bullet-hell phase.
	if enemy.has_method("select_target") and enemy.has_method("perform_attack"):
		var target: Node2D = enemy.select_target(players)
		if target != null:
			await enemy.perform_attack(target)

	# Only advance normally if player_downed() or enemy_defeated() hasn't
	# already taken over turn management during this attack sequence.
	if not _turn_advanced:
		await get_tree().create_timer(0.3).timeout
		_advance_turn()

## Kept for backwards-compatibility; no longer the primary turn-advance path.
func enemy_attack_complete() -> void:
	pass

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
			_do_swap_action()
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
		# Damage is 1 per hit for now.
		# FUTURE — scale with weapon, attack stat, action command timing bonus.
		(attacker as Player).perform_attack(target, 1)
	# Turn advances via attack_sequence_complete() once the player finishes.

## Both players swap battle positions simultaneously.
## Each calls swap_player_done() when their animation finishes; once both
## have reported in, _swap_complete fires and the turn advances.
func _do_swap_action() -> void:
	if players.size() < 2:
		_advance_turn()
		return

	var p1: Player = null
	var p2: Player = null
	for player in players:
		if player is Player:
			if p1 == null:
				p1 = player as Player
			else:
				p2 = player as Player

	if p1 == null or p2 == null:
		_advance_turn()
		return

	var p1_pos := p1.global_position
	var p2_pos := p2.global_position

	# Both players pass through the same position during the swap.
	# Without a collision exception they depenetrate each other, causing a
	# small nudge in the facing direction. Exclude them for the duration.
	p1.add_collision_exception_with(p2)
	p2.add_collision_exception_with(p1)

	_swap_players_done = 0
	# Start both coroutines without awaiting — they run in parallel.
	# Each will call swap_player_done() when finished.
	p1.perform_swap(p2_pos)
	p2.perform_swap(p1_pos)

	await _swap_complete

	p1.remove_collision_exception_with(p2)
	p2.remove_collision_exception_with(p1)

	# Swap the attack receive points so enemies target the correct new positions.
	if _combat_room != null and _combat_room.has_method("swap_receive_points"):
		_combat_room.swap_receive_points()

	await get_tree().create_timer(0.3).timeout
	_advance_turn()

## Called by each player when their swap animation finishes.
func swap_player_done() -> void:
	_swap_players_done += 1
	if _swap_players_done >= 2:
		_swap_complete.emit()

## Called by the entity that received a hit after their Hit animation finishes.
## Signals the attacker to continue its attack sequence.
func hit_sequence_complete() -> void:
	hit_sequence_done.emit()
	# FUTURE — damage resolution here: apply damage to target, update HP display,
	# check for defeat condition (hp <= 0 → victory/defeat sequence).

## Called by Enemy._do_defeat_sequence() when the Die animation finishes.
## Removes the enemy from the fight, emits hit_sequence_done so the attacker
## can continue its sequence, then checks for victory.
func enemy_defeated(enemy: Node) -> void:
	_turn_advanced = true   # prevent _start_enemy_turn from double-advancing
	enemies.erase(enemy)
	_turn_order = _turn_order.filter(func(entry: Dictionary) -> bool:
		return entry.entity != enemy)

	# Unblock the attacker's coroutine — mirrors hit_sequence_complete().
	hit_sequence_done.emit()

	if enemies.is_empty():
		await _do_victory_sequence()
		return

	# More enemies remain — clamp turn index and continue.
	# FUTURE — multiple enemies: remaining enemies continue fighting;
	# turn order adjusts automatically as enemies are removed.
	if _turn_order.size() > 0:
		_current_turn_index = _current_turn_index % _turn_order.size()
	await get_tree().create_timer(0.5).timeout
	_start_next_turn()

## Called by Player._do_defeat_sequence() when the Die animation finishes.
## Removes the player from the turn order and checks for full defeat.
func player_downed(player: Node) -> void:
	_turn_advanced = true   # prevent _start_enemy_turn from double-advancing
	# Unblock the attacker's coroutine — mirrors enemy_defeated().
	hit_sequence_done.emit()

	_turn_order = _turn_order.filter(func(entry: Dictionary) -> bool:
		return entry.entity != player)

	# Check if all players are now downed — no one left to fight.
	var active_players: Array = players.filter(
		func(p: Node) -> bool: return not (p as Player)._is_downed)

	if active_players.is_empty() or _turn_order.is_empty():
		await _do_defeat_sequence()
		return

	# At least one player remains — clamp index and continue the turn.
	# FUTURE — Option C revive window: remaining player has the option to
	# spend their turn reviving their partner.
	# FUTURE — special case if last player and enemy also at low HP:
	# dramatic last stand moment with unique dialogue.
	_current_turn_index = _current_turn_index % _turn_order.size()
	await get_tree().create_timer(0.5).timeout
	_start_next_turn()

## Battle system reads player count dynamically from the "players" group via
## the players array built at start_battle(). Single player mode is transparent —
## P1 downed = active_players empty = defeat. No special casing needed.
func _do_defeat_sequence() -> void:
	current_phase = BattlePhase.DEFEAT
	await get_tree().create_timer(1.0).timeout
	end_battle()
	# FUTURE — game over screen: show which enemies defeated the players,
	# offer retry from room start or last checkpoint.
	# FUTURE — death penalty: lose items or currency on defeat.
	# FUTURE — story consequence: some defeats advance the story differently.

func _do_victory_sequence() -> void:
	current_phase = BattlePhase.VICTORY
	# Dramatic pause before unlocking players.
	await get_tree().create_timer(1.0).timeout
	end_battle()
	# FUTURE — morality system prompt before battle fully ends:
	# both players see kill/spare choice; any player choosing kill →
	# that player performs a finisher animation; spare → enemy stays collapsed.
	# Morality score tracks choices and affects story outcomes.
	# FUTURE — room cleared flag: CombatRoom marks itself cleared so
	# enemies don't respawn on re-entry; visual change to room (bloodstain, etc).
	# FUTURE — victory screen showing damage dealt, turns taken, rating (S/A/B/C).
	# FUTURE — post battle dialogue: characters react to the fight;
	# first battle has specific scripted dialogue.

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

## Resets all players via battle_end_reset(), disables enemy hurtboxes,
## hides the menu, and clears all battle state. Called by victory and defeat.
func end_battle() -> void:
	current_phase = BattlePhase.INACTIVE

	# battle_end_reset() handles both active and downed players:
	# unlocks input, re-enables physics/collision, restores min 1 HP if downed.
	for player in players:
		if player.has_method("battle_end_reset"):
			player.battle_end_reset()

	for enemy in enemies:
		if enemy.has_method("disable_hurtbox"):
			enemy.disable_hurtbox()

	if _action_menu:
		_action_menu.hide_menu()

	players = []
	enemies = []
	_turn_order = []
	_current_turn_index = 0
	_combat_room = null

	battle_ended.emit()
	# FUTURE — trigger post battle dialogue using the dialogue system from Room02.
	# FUTURE — drop items into the room.
	# FUTURE — unlock door or path forward.
