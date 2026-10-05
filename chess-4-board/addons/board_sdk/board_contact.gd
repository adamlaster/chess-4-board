extends RefCounted

# Typed view over a single contact from `Board.input.contacts_received`.
#
# Contacts stream every inference frame (~60 fps), so the signal still carries
# raw `Dictionary` entries — wrapping every contact in an object each frame would
# add needless allocation. Call `BoardContact.from_dict(c)` when you want typed
# access, the enums, and the `facing()` / `is_piece()` helpers.

class_name BoardContact

## Contact kinds. Use `is_piece()` rather than comparing `type` directly when you
## just need "finger vs Piece".
enum Type { FINGER = 0, GLYPH = 1, BLOB = 2 }

## Lifecycle phase of a contact within a frame.
enum Phase { NONE = 0, BEGAN = 1, MOVED = 2, ENDED = 3, CANCELED = 4, STATIONARY = 5 }

## Stable across frames for the same physical contact.
var contact_id: int = -1
## Display-pixel position, origin top-left, Y-down.
var position: Vector2 = Vector2.ZERO
## Degrees in [0, 360), screen-space: `facing()` turns it into a unit vector
## pointing where the Piece physically faces. Only meaningful for Pieces.
var orientation: float = 0.0
var type: Type = Type.FINGER
var phase: Phase = Phase.NONE
## 0 for a finger; 1+ identifies the Piece type.
var glyph_id: int = 0
## Whether the Piece is currently held by a hand (always true for fingers).
var is_touched: bool = false
## Kernel frame number, for cross-layer correlation.
var frame_number: int = 0


## Build a typed contact from a `contacts_received` Dictionary entry.
static func from_dict(d: Dictionary) -> BoardContact:
	var c := BoardContact.new()
	c.contact_id = int(d.get("contact_id", -1))
	c.position = Vector2(float(d.get("x", 0.0)), float(d.get("y", 0.0)))
	c.orientation = float(d.get("orientation", 0.0))
	c.type = int(d.get("type_id", Type.FINGER))
	c.phase = int(d.get("phase_id", Phase.NONE))
	c.glyph_id = int(d.get("glyph_id", 0))
	c.is_touched = bool(d.get("is_touched", false))
	c.frame_number = int(d.get("frame_number", 0))
	return c


## True when this contact is a tracked Piece (carries a Glyph), not a bare finger.
func is_piece() -> bool:
	return glyph_id > 0


## Unit vector pointing where the Piece physically faces, in Y-down screen space.
func facing() -> Vector2:
	var rad := deg_to_rad(orientation)
	return Vector2(cos(rad), sin(rad))
