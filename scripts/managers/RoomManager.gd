## RoomManager.gd
## Global singleton — registered in Project → Project Settings → Autoload
## as "RoomManager".  Access it from any script with RoomManager.something.
##
## Responsibilities:
##   • Load / unload room scenes at runtime
##   • Place players at the correct spawn marker after each transition
##   • Remember which rooms have been cleared (enemies defeated)
##   • Emit room_loaded so RoomCamera and other systems can react

extends Node

# ---------------------------------------------------------------------------
# STARTING ROOM
# ---------------------------------------------------------------------------

## Hardcoded so no Inspector assignment is needed.
## Change this path to swap the first room the game boots into.
var starting_room : PackedScene = preload("res://scenes/world/Level01_Room01.tscn")

# ---------------------------------------------------------------------------
# SIGNALS
# ---------------------------------------------------------------------------

## Fired every time a new room finishes loading.
## RoomCamera connects to this to rewire exit signals and update next/prev.
## Signal uses Node (not Room) so the autoload compiles before Room.gd's
## class_name is guaranteed to be in scope. Cast to Room at the call site.
signal room_loaded(room: Node)

## Fired once every player has gone off screen through an exit.
## RoomCamera listens to this to start the fade transition.
signal all_players_exited(direction: String, next_room: PackedScene)

# ---------------------------------------------------------------------------
# PUBLIC STATE
# ---------------------------------------------------------------------------

## The Room node currently active in the scene tree.
## Read this from other scripts; never set it directly.
var current_room : Node = null   # typed as Node for the same reason as the signal

# ---------------------------------------------------------------------------
# PRIVATE STATE
# ---------------------------------------------------------------------------

# Dictionary<String, bool>
# Key   = room scene file path  (e.g. "res://scenes/world/Forest01.tscn")
# Value = true  (present means cleared)
var _cleared_rooms : Dictionary = {}

# The node that rooms are added to / removed from as children.
# We look for a node named "World" at the scene root; if none exists
# we fall back to the scene root itself.
var _room_container : Node = null

# Exit tracking — accumulates per-player exit reports until all are done.
var _players_exited: Array = []
var _exit_direction: String = ""
var _exit_next_room: PackedScene = null

# ---------------------------------------------------------------------------
# READY
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Wait one frame so the main scene tree is fully built before we
	# start adding nodes to it.
	await get_tree().process_frame

	_room_container = get_tree().get_root().get_node_or_null("World")
	if _room_container == null:
		_room_container = get_tree().get_root()

	if starting_room:
		load_room(starting_room, "none")

# ---------------------------------------------------------------------------
# PUBLIC API
# ---------------------------------------------------------------------------

## Load a new room and replace the current one.
##
## room_scene  —  the PackedScene (.tscn) to instantiate.
##
## spawn_side  —  which exit the players came from:
##   "right"  players walked off the right edge → enter new room from left
##            → spawn at SpawnLeft marker
##   "left"   players walked off the left edge  → enter new room from right
##            → spawn at SpawnRight marker
##   "none"   first load or manual override — use SpawnLeft by default
func load_room(room_scene: PackedScene, spawn_side: String) -> void:
	# Reset exit tracking for this new room.
	_players_exited.clear()
	_exit_direction = ""
	_exit_next_room = null

	# --- Remove the old room ---
	if current_room != null:
		_room_container.remove_child(current_room)
		current_room.queue_free()
		current_room = null

	# --- Instantiate and add the new room ---
	var new_room : Node = room_scene.instantiate()
	if not new_room is Room:
		push_error("RoomManager: room_scene did not instantiate as a Room. " +
				   "Make sure the root node has a Room script attached.")
		new_room.queue_free()
		return

	_room_container.add_child(new_room)
	current_room = new_room

	# --- Place players at the right spawn marker ---
	_spawn_players(spawn_side)

	# --- Notify listeners ---
	# RoomCamera will receive this and reconnect exit signals + update
	# next_room / prev_room automatically.
	room_loaded.emit(current_room)

## Called by Room.gd when a player first enters an exit zone.
## Records the exit direction and target room (first caller wins).
func player_entered_exit(player: Node, direction: String, next_room: PackedScene) -> void:
	if _exit_next_room != null:
		return  # Direction already locked in by the first player.
	_exit_direction = direction
	_exit_next_room = next_room

## Called by Player when it has gone fully off screen.
## When every player has called this, fires all_players_exited.
func player_finished_exit(player: Node) -> void:
	if player in _players_exited:
		return
	_players_exited.append(player)

	var all_players := get_tree().get_nodes_in_group("players")
	if _players_exited.size() >= all_players.size() and _exit_next_room != null:
		all_players_exited.emit(_exit_direction, _exit_next_room)

## Call this when the players finish a battle in the current room.
## Prevents enemies from respawning if the players come back through here.
func mark_current_room_cleared() -> void:
	if current_room == null:
		return
	_cleared_rooms[current_room.scene_file_path] = true

## Returns true if the current room was already cleared this session.
func is_current_room_cleared() -> bool:
	if current_room == null:
		return false
	return _cleared_rooms.get(current_room.scene_file_path, false)

## Returns true if the room at the given file path has been cleared.
## Useful for rooms that check their own state on _ready().
##   Example:  RoomManager.is_room_cleared(scene_file_path)
func is_room_cleared(room_path: String) -> bool:
	return _cleared_rooms.get(room_path, false)

# ---------------------------------------------------------------------------
# PRIVATE
# ---------------------------------------------------------------------------

func _spawn_players(spawn_side: String) -> void:
	if current_room == null:
		return

	var players : Array = get_tree().get_nodes_in_group("players")
	if players.is_empty():
		return

	# spawn_side = direction the players exited from the PREVIOUS room.
	# They enter the new room from the opposite side, so:
	#   "right"  → came from the right → appear at SpawnLeft
	#   "left"   → came from the left  → appear at SpawnRight
	#   "top"    → came from above     → appear at SpawnBottom
	#   "bottom" → came from below     → appear at SpawnTop
	#   "none"   → first load          → Player 1 at SpawnLeft, Player 2 at SpawnRight
	var room := current_room as Room
	if room == null:
		return

	if spawn_side == "none" and players.size() >= 2:
		# Spread players across the room on first load rather than stacking them.
		var p1 := players[0] as Node2D
		var p2 := players[1] as Node2D
		if room.spawn_left != null:
			if p1 is Player:
				(p1 as Player).arrive_in_room(room.spawn_left.global_position)
			else:
				p1.global_position = room.spawn_left.global_position
		if room.spawn_right != null:
			if p2 is Player:
				(p2 as Player).arrive_in_room(room.spawn_right.global_position)
			else:
				p2.global_position = room.spawn_right.global_position
		return

	var marker : Marker2D
	match spawn_side:
		"left":   marker = room.spawn_right
		"top":    marker = room.spawn_bottom
		"bottom": marker = room.spawn_top
		_:        marker = room.spawn_left   # "right", "none" with 1 player, or anything else

	if marker == null:
		push_warning("RoomManager: spawn marker not found in room — players not repositioned.")
		return

	# For transitions, place all players at the entry marker with a small gap.
	for i : int in players.size():
		var player := players[i] as Node2D
		var spawn_pos := marker.global_position + Vector2(i * 48.0, 0.0)
		if player is Player:
			(player as Player).arrive_in_room(spawn_pos)
		else:
			player.global_position = spawn_pos
