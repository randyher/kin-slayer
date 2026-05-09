# GameManager.gd
# Central singleton (autoload) that owns the top-level game state for Kin Slayer.
# Responsibilities:
#   - Track overall game progression (current stage, run data, player roster)
#   - Handle scene transitions between the world map, battle, and UI layers
#   - Persist save data and expose global signals (game_over, stage_complete, etc.)
#   - Coordinate startup / shutdown of other managers (BattleManager, StageManager)
# This node is registered as an autoload so every scene can access it via GameManager.*

extends Node
