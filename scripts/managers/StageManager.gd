# StageManager.gd
# Controls stage-based progression through the game's platformer world.
# Responsibilities:
#   - Load and unload stage scenes from scenes/world/ based on current progression
#   - Define which enemy groups and battle arenas appear in each stage
#   - Track stage objectives, checkpoint state, and unlockable paths
#   - Notify GameManager when a stage is cleared or failed
#   - Spawn collectibles, weapon pickups, and environmental hazards per stage config
# Each stage is represented by a data resource that this manager reads at runtime.

extends Node
