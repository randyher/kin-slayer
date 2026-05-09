## Level01.gd
## Builds the tile layout for Level01 at runtime via set_cell() calls.
##
## HOW TO EDIT THE LAYOUT:
##   Option A (code) — edit _build_level() below. Each set_cell() places one
##   tile. Change Vector2i(col, row) to move it. Change the range() bounds to
##   stretch or shrink a run of tiles. Add new lines to add platforms.
##
##   Option B (visual) — open Level01.tscn in Godot, select the TileMap node,
##   open the TileMap tab at the bottom of the editor, pick a tile from the
##   palette, and paint directly. You can erase code-placed tiles too.
##   Just delete or comment out _build_level() when you switch to full manual.
##
## TILE GRID REFERENCE (each tile displays as 32x32 px at TileMap scale 2):
##   Col 0  = world x 0        Col 31 = world x 992
##   Row 12 = world y 384      (floor level — players spawn at y ≈ 290 and fall to here)

extends Node2D

## Source IDs — match the order in the TileSet (Inspector → TileMap → TileSet → Sources).
## 0 = Bricks.png    1 = Walls.png
const BRICKS := 0
const WALLS  := 1

## Atlas coords of the tile to sample from each sheet.
## (0, 0) is the very top-left tile. Change to pick a different graphic.
const BRICKS_TILE := Vector2i(8, 3)
const WALLS_TILE  := Vector2i(2, 10)

@onready var _tile_map: TileMapLayer = $TileMap

func _ready() -> void:
	_build_level()

# ---------------------------------------------------------------------------
# LEVEL LAYOUT — edit freely
# set_cell(Vector2i(col, row), source, atlas_coord)
# ---------------------------------------------------------------------------
func _build_level() -> void:

	# ---- FLOOR (solid ground, full width) ----------------------------------
	# Row 12 = world y 384. Runs from left wall to right wall.
	for x in range(0, 32):
		_tile_map.set_cell(Vector2i(x, 12), BRICKS, BRICKS_TILE)

	# ---- EASY LEDGE (one small hop from spawn) -----------------------------
	# Row 10 = world y 320. Sits between the two player spawn points.
	for x in range(5, 10):
		_tile_map.set_cell(Vector2i(x, 10), BRICKS, BRICKS_TILE)

	# ---- PLATFORM A (medium jump, first real challenge) --------------------
	# Row 9 = world y 288. Reachable from the floor in one full jump.
	for x in range(12, 17):
		_tile_map.set_cell(Vector2i(x, 9), BRICKS, BRICKS_TILE)

	# ---- PLATFORM B (high platform, jump from Platform A) ------------------
	# Row 7 = world y 224. Requires a full hold-jump from Platform A.
	for x in range(18, 23):
		_tile_map.set_cell(Vector2i(x, 7), BRICKS, BRICKS_TILE)

	# ---- PLATFORM C (step back down to the right) --------------------------
	# Row 8 = world y 256. Easy drop or jump from Platform B.
	for x in range(24, 28):
		_tile_map.set_cell(Vector2i(x, 8), BRICKS, BRICKS_TILE)

	# ---- LEFT WALL ---------------------------------------------------------
	for y in range(0, 12):
		_tile_map.set_cell(Vector2i(0, y), WALLS, WALLS_TILE)

	# ---- RIGHT WALL --------------------------------------------------------
	for y in range(0, 12):
		_tile_map.set_cell(Vector2i(31, y), WALLS, WALLS_TILE)
