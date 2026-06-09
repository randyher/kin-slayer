## HUD.gd
## Attached to HUD.tscn (CanvasLayer root).
##
## Automatically discovers players via the "players" group and wires up
## their hp_changed and stamina_changed signals.  No manual connection is
## needed — this HUD works in any scene that has Player nodes in the group.
##
## Heart display: one TextureRect per HP point, swapped between full/empty
## textures.  Dynamically rebuilt if max_hp changes.
##
## Stamina bar: a yellow ColorRect that shrinks as stamina drains and fades
## in/out so it only shows when relevant.
## # TEMP — stamina bar uses placeholder ColorRects; replace with sprites later.

extends CanvasLayer

# ---------------------------------------------------------------------------
# HEART TEXTURES
# Preloaded once at parse time so swapping textures is instant.
# ---------------------------------------------------------------------------
const HEART_FULL  : Texture2D = preload("res://assets/sprites/ui/hearts/HeartDetailed_Full.png")
const HEART_EMPTY : Texture2D = preload("res://assets/sprites/ui/hearts/HeartDetailed_Empty.png")

# Size each heart icon is displayed at in the HUD.
const HEART_SIZE : Vector2 = Vector2(48, 48)

# Full width of the stamina bar in pixels — must match the ColorRect in the scene.
const STAMINA_BAR_WIDTH : float = 96.0   # TEMP

# ---------------------------------------------------------------------------
# NODE REFERENCES
# Resolved automatically when the scene loads via @onready.
# ---------------------------------------------------------------------------
@onready var _p1_hearts      : HBoxContainer = $Control/P1Hearts
@onready var _p2_hearts      : HBoxContainer = $Control/P2Hearts
@onready var _p1_stamina_bar : Control       = $Control/P1StaminaBar        # TEMP
@onready var _p2_stamina_bar : Control       = $Control/P2StaminaBar        # TEMP
@onready var _p1_stamina_fill: ColorRect     = $Control/P1StaminaBar/Foreground  # TEMP
@onready var _p2_stamina_fill: ColorRect     = $Control/P2StaminaBar/Foreground  # TEMP

# ---------------------------------------------------------------------------
# CACHED PLAYER REFERENCES
# Set once in _find_and_connect_players(); never searched again after that.
# ---------------------------------------------------------------------------
var _player1 : Player = null
var _player2 : Player = null

# ---------------------------------------------------------------------------
# READY
# ---------------------------------------------------------------------------
func _ready() -> void:
	# Stamina bars start invisible — they fade in the first time stamina drops.
	_p1_stamina_bar.modulate.a = 0.0   # TEMP
	_p2_stamina_bar.modulate.a = 0.0   # TEMP

	# In single player mode, hide all P2 HUD elements immediately.
	# FUTURE — center P1 HUD elements when P2 HUD is hidden.
	if GameManager.is_single_player():
		_p2_hearts.visible      = false
		_p2_stamina_bar.visible = false

	# Wait one frame so every Player node has had its own _ready() called and
	# has added itself to the "players" group.  Without this yield the group
	# may still be empty when we search it.
	await get_tree().process_frame
	_find_and_connect_players()

# ---------------------------------------------------------------------------
# PLAYER DISCOVERY
# Searches the "players" group, identifies P1 and P2 by player_id, and
# connects the relevant signals.  Initialises the display from current values
# so the HUD is correct even if it enters the tree after the player does.
# ---------------------------------------------------------------------------
func _find_and_connect_players() -> void:
	for node : Node in get_tree().get_nodes_in_group("players"):
		if not node is Player:
			continue
		var p := node as Player

		if p.player_id == 1:
			_player1 = p
			p.hp_changed.connect(_on_p1_hp_changed)
			p.stamina_changed.connect(_on_p1_stamina_changed)
			# Initialise with the player's current values right now.
			_build_hearts(_p1_hearts, p.current_hp, p.max_hp)

		elif p.player_id == 2:
			_player2 = p
			p.hp_changed.connect(_on_p2_hp_changed)
			p.stamina_changed.connect(_on_p2_stamina_changed)
			_build_hearts(_p2_hearts, p.current_hp, p.max_hp)

# ---------------------------------------------------------------------------
# HEART DISPLAY — HELPERS
# ---------------------------------------------------------------------------

## Destroys and recreates all heart nodes in a container.
## Called on first connect and whenever max_hp changes.
func _build_hearts(container: HBoxContainer, current: int, maximum: int) -> void:
	# Remove every existing child so we start clean.
	for child in container.get_children():
		child.queue_free()

	# Create one TextureRect for each possible HP point.
	for i : int in maximum:
		var rect := TextureRect.new()
		rect.texture              = HEART_FULL if i < current else HEART_EMPTY
		rect.custom_minimum_size  = HEART_SIZE
		# EXPAND_IGNORE_SIZE lets the HBoxContainer size the rect to HEART_SIZE.
		rect.expand_mode          = TextureRect.EXPAND_IGNORE_SIZE
		# STRETCH_KEEP_ASPECT_CENTERED keeps the heart art centered and undistorted.
		rect.stretch_mode         = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		container.add_child(rect)

## Updates existing heart textures without rebuilding the container.
## Rebuilds fully if max_hp has changed since the last call.
func _update_hearts(container: HBoxContainer, current: int, maximum: int) -> void:
	var hearts := container.get_children()

	# If the heart count has changed (max_hp edited at runtime), rebuild.
	if hearts.size() != maximum:
		_build_hearts(container, current, maximum)
		return

	# Otherwise just swap the textures in-place — no nodes are created/freed.
	for i : int in hearts.size():
		(hearts[i] as TextureRect).texture = HEART_FULL if i < current else HEART_EMPTY

# ---------------------------------------------------------------------------
# HP SIGNAL HANDLERS
# ---------------------------------------------------------------------------

func _on_p1_hp_changed(current: int, maximum: int) -> void:
	_update_hearts(_p1_hearts, current, maximum)

func _on_p2_hp_changed(current: int, maximum: int) -> void:
	_update_hearts(_p2_hearts, current, maximum)

# ---------------------------------------------------------------------------
# STAMINA SIGNAL HANDLERS                                           # TEMP
# All stamina bar code is marked TEMP — replace ColorRect with a proper
# UI sprite asset when the art is ready.
# ---------------------------------------------------------------------------

func _on_p1_stamina_changed(current: float, maximum: float) -> void:
	_update_stamina_bar(_p1_stamina_bar, _p1_stamina_fill, current, maximum)  # TEMP

func _on_p2_stamina_changed(current: float, maximum: float) -> void:
	_update_stamina_bar(_p2_stamina_bar, _p2_stamina_fill, current, maximum)  # TEMP

## Resizes the foreground fill and fades the bar in or out via Tween.  # TEMP
func _update_stamina_bar(bar: Control, fill: ColorRect,                  # TEMP
		current: float, maximum: float) -> void:                         # TEMP
	if maximum <= 0.0:                                                   # TEMP
		return                                                            # TEMP

	# Shrink the foreground to reflect the stamina ratio.               # TEMP
	fill.offset_right = (current / maximum) * STAMINA_BAR_WIDTH         # TEMP

	# Fade the bar in when draining, fade out when full.                # TEMP
	var tween := create_tween()                                          # TEMP
	if current < maximum:                                                # TEMP
		# Stamina dropped — show the bar quickly so the player notices.  # TEMP
		tween.tween_property(bar, "modulate:a", 1.0, 0.2)               # TEMP
	else:                                                                # TEMP
		# Stamina is full — hide the bar slowly.                         # TEMP
		tween.tween_property(bar, "modulate:a", 0.0, 0.5)               # TEMP
