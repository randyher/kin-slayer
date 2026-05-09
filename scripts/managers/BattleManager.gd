# BattleManager.gd
# Orchestrates individual battle encounters in the co-op turn-based platformer.
# Responsibilities:
#   - Manage the turn order queue for all combatants (players and enemies)
#   - Trigger and evaluate action commands (timed button presses, rhythm inputs)
#     that modify damage, healing, or status effects mid-action
#   - Resolve weapon abilities and their targeting logic
#   - Detect battle-end conditions (all enemies defeated, all players KO'd)
#   - Emit signals consumed by the UI (turn_changed, action_resolved, battle_ended)
# Works closely with StageManager to receive the enemy roster for each encounter.

extends Node
