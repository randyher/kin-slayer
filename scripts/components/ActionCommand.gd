# ActionCommand.gd
# Reusable component that defines a single interactive action command prompt.
# Action commands are timed player inputs (button presses, button holds, sequences)
# that occur during an attack or ability animation, allowing players to boost or
# modify the outcome of that action — core to the co-op feel of Kin Slayer.
# Responsibilities:
#   - Define the input window (timing, required input, difficulty tier)
#   - Evaluate whether the player hit, missed, or nailed the command
#   - Return a CommandResult (MISS, HIT, PERFECT) to the calling action/ability
#   - Drive the UI prompt displayed to the local co-op player whose turn it is
# Attach to an action node or instantiate dynamically from BattleManager.

extends Node
