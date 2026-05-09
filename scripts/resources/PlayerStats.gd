# PlayerStats.gd
# Godot 4 Resource that holds runtime and base statistics for a player character.
# Shared between the platformer layer and the battle layer so one source of truth
# drives both exploration behavior and combat calculations.
# Fields (to be defined):
#   - character_name, portrait (Texture2D)
#   - max_hp, current_hp
#   - max_mp, current_mp        — mana / resource for weapon abilities
#   - attack, defense, speed   — core combat stats
#   - level, experience         — progression tracking
#   - equipped_weapon : WeaponResource
#   - status_effects : Array    — active buffs / debuffs applied during battle
# Instantiated per player slot and passed between scenes via GameManager.

extends Resource
