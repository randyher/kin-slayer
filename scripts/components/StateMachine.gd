# StateMachine.gd
# Generic finite state machine (FSM) component used by players, enemies, and the
# battle flow itself throughout Kin Slayer.
# Responsibilities:
#   - Maintain the current active state and delegate _process / _physics_process
#     calls down to it each frame
#   - Provide transition helpers (transition_to, can_transition) used by entity scripts
#   - Emit state_changed(from, to) signal for animation and UI hooks
#   - Support nested / hierarchical states so platformer movement states can live
#     inside a broader "battle" or "exploration" parent state
# Entities own one StateMachine child node and register their State nodes under it.

extends Node
