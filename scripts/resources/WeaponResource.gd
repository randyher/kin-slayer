# WeaponResource.gd
# Godot 4 Resource that describes a single weapon in Kin Slayer.
# Each weapon carries its own ability set, action command profile, and stat modifiers,
# making weapons the primary driver of build variety in co-op play.
# Fields (to be defined):
#   - weapon_name, description, icon (Texture2D)
#   - base_damage, damage_type (physical / elemental / etc.)
#   - ability_list : Array[AbilityResource]  — unique moves unlocked by this weapon
#   - action_command_profile : ActionCommand config used when this weapon attacks
#   - stat_modifiers : Dictionary  — buffs / debuffs applied to the wielder's PlayerStats
# Saved as .tres files under assets/ or a dedicated data/ folder.

extends Resource
