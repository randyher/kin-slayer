## Level01_Room01.gd
## Script for the first room. Extends Room so all exit/signal logic is inherited.
## Tiles are placed via set_cell() in _ready() rather than stored as binary data
## in the scene file, which avoids them being silently stripped by the editor.

extends Room

func _ready() -> void:
	super._ready()
	# Remove this call once you've painted your own floor in the editor.
	#_paint_tiles()

func _paint_tiles() -> void:
	var tmap : TileMapLayer = $TileMapLayer
	# Source 0 = Bricks atlas.  Atlas cell (0,0) = full solid square with collision.
	var src   : int      = 0
	var solid : Vector2i = Vector2i(0, 0)

	# TileMapLayer has scale (2,2), so each tile = 32×32 world px.
	# Room spans world x: -576..576, y: -324..324.
	# Tile x range: -18..17  (36 tiles × 32 = 1152 px)
	# Tile y range: -10..9   (20 tiles × 32 = 640 px ≈ room height)

	# ── Floor ──────────────────────────────────────────────────────────────
	# Tile y=8  →  world y=256  (players spawn at y=200, capsule bottom at
	# y=250, so they fall 6 px before landing — clean contact)
	for x : int in range(-18, 18):
		tmap.set_cell(Vector2i(x, 8), src, solid)

	# ── Platform A  (left side, mid-height) ────────────────────────────────
	# Tile y=5  →  world y=160  (96 px above floor, within jump height)
	for x : int in range(-10, -3):
		tmap.set_cell(Vector2i(x, 5), src, solid)

	# ── Stepping stone  (centre bridge) ───────────────────────────────────
	# Tile y=6  →  world y=192  (64 px above floor — easy hop)
	for x : int in range(-2, 4):
		tmap.set_cell(Vector2i(x, 6), src, solid)

	# ── Platform B  (right side, upper) ───────────────────────────────────
	# Tile y=2  →  world y=64   (96 px above Platform A — reachable via A)
	for x : int in range(4, 11):
		tmap.set_cell(Vector2i(x, 2), src, solid)
