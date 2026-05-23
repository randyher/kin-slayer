## BattleActionMenu.gd
## Floating action menu that appears above the active player during their turn.
## Shows four PlayStation buttons in a diagonal layout (steps up-right).
## Reads input mapped to the active player's controller scheme.
## Phase 2: input detection and turn handoff only — no attack resolution yet.

extends Node2D

# ---------------------------------------------------------------------------
# LAYOUT EXPORTS — tune all of these live in the Inspector
# ---------------------------------------------------------------------------

## How far each button steps right and up from the previous one.
@export var button_offset: Vector2 = Vector2(14.0, -20.0)
## Offset above the active player's head where the lowest button sits.
@export var base_offset: Vector2 = Vector2(0.0, -60.0)
## Scale applied to all button sprites (pixel art needs 3× to be readable).
@export var button_scale: Vector2 = Vector2(2.0, 2.0)
## Horizontal offset of each action label from its button sprite.
@export var label_offset: Vector2 = Vector2(20.0, 0.0)
## How long the menu fades in (seconds).
@export var fade_in_duration: float = 0.15
## How long the menu fades out (seconds).
@export var fade_out_duration: float = 0.10
## How long the enemy "thinks" before its turn ends (seconds).
@export var enemy_turn_duration: float = 1.5

@export_group("Unlocked Actions")
## Show the Guard button in the action menu. Disable to hide until unlocked.
@export var guard_enabled: bool = false
## Show the Item button in the action menu. Disable to hide until unlocked.
@export var item_enabled: bool = false

# ---------------------------------------------------------------------------
# INTERNAL STATE
# ---------------------------------------------------------------------------

var _active_player: Node = null
var _is_visible: bool = false
var _waiting_for_input: bool = false

# References resolved in _ready() — must match node names in the tscn.
@onready var _entry_cross    : Node2D = $ButtonEntry_Cross
@onready var _entry_square   : Node2D = $ButtonEntry_Square
@onready var _entry_circle   : Node2D = $ButtonEntry_Circle
@onready var _entry_triangle : Node2D = $ButtonEntry_Triangle

# ---------------------------------------------------------------------------
# READY
# ---------------------------------------------------------------------------

func _ready() -> void:
	add_to_group("battle_ui")
	visible = false
	modulate.a = 0.0
	_apply_layout()

# ---------------------------------------------------------------------------
# LAYOUT
# ---------------------------------------------------------------------------

func _apply_layout() -> void:
	# Position buttons diagonally — index 0 is bottom (closest to player head),
	# index 3 is top. Order: Item(△), Guard(□), Swap(○), Attack(✕) bottom→top.
	var entries: Array[Node2D] = [_entry_triangle, _entry_square, _entry_circle, _entry_cross]
	for i in entries.size():
		var entry: Node2D = entries[i]
		entry.position = base_offset + button_offset * float(i)

		var sprite := entry.get_node("ButtonSprite") as AnimatedSprite2D
		if sprite:
			sprite.scale = button_scale

		var label := entry.get_node("ActionLabel") as Label
		if label:
			# Place label to the right of the scaled sprite.
			label.position = label_offset

# ---------------------------------------------------------------------------
# SHOW / HIDE
# ---------------------------------------------------------------------------

## Called by BattleManager when it is this player's turn.
func show_for_player(player: Node) -> void:
	_active_player = player
	_is_visible = true
	_waiting_for_input = false   # wait for fade before accepting input

	# Reset every button to idle and apply unlock visibility.
	for entry: Node2D in [_entry_cross, _entry_square, _entry_circle, _entry_triangle]:
		var sprite := entry.get_node("ButtonSprite") as AnimatedSprite2D
		if sprite:
			sprite.play("idle")
	_entry_square.visible   = guard_enabled
	_entry_triangle.visible = item_enabled

	_update_position()
	visible = true
	modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, fade_in_duration)
	await tween.finished
	_waiting_for_input = true

## Fade out and hide. Awaitable — callers can await this to sequence cleanly.
func hide_menu() -> void:
	_is_visible = false
	_waiting_for_input = false
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, fade_out_duration)
	await tween.finished
	visible = false
	_active_player = null

# ---------------------------------------------------------------------------
# PROCESS — follows the active player and polls input
# ---------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if not _is_visible or not _active_player:
		return
	_update_position()
	if _waiting_for_input:
		_check_input()

func _update_position() -> void:
	if not _active_player:
		return
	global_position = _active_player.global_position

# ---------------------------------------------------------------------------
# INPUT
# ---------------------------------------------------------------------------

func _check_input() -> void:
	var pid: int = _active_player.player_id

	# ✕ cross   → Attack  (jump button)
	if Input.is_action_just_pressed("p%d_cross" % pid):
		_on_button_pressed("cross", "attack")
	# ○ circle  → Swap
	elif Input.is_action_just_pressed("p%d_circle" % pid):
		_on_button_pressed("circle", "swap")
	# R1       → Guard
	elif Input.is_action_just_pressed("p%d_r1" % pid) and guard_enabled:
		_on_button_pressed("square", "guard")
	# △ triangle → Item   (up button — no p_pause exists for P2 in all configs)
	elif Input.is_action_just_pressed("p%d_up" % pid) and item_enabled:
		_on_button_pressed("triangle", "item")

func _on_button_pressed(button: String, action: String) -> void:
	_waiting_for_input = false

	if action == "attack":
		# For Attack, hide the menu immediately — the player teleport sequence
		# IS the visual feedback. No need to wait for the press animation.
		await hide_menu()
		BattleManager.action_selected(action)
		return

	# For all other actions, play the pressed animation then hand off.
	# FUTURE — each action triggers a distinct system in BattleManager Phase 3:
	# guard  → parry stance + input window
	# swap   → front/back position change between players
	# item   → inventory selection submenu
	var sprite_path := {
		"cross":    "ButtonEntry_Cross/ButtonSprite",
		"square":   "ButtonEntry_Square/ButtonSprite",
		"circle":   "ButtonEntry_Circle/ButtonSprite",
		"triangle": "ButtonEntry_Triangle/ButtonSprite",
	}
	var sprite := get_node(sprite_path[button]) as AnimatedSprite2D
	if sprite:
		sprite.play("pressed")

	await get_tree().create_timer(0.35).timeout
	await hide_menu()
	BattleManager.action_selected(action)
