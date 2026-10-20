class_name Formations
extends RefCounted
## Enemy formation layouts. Each offset is Vector2(x, distance), where distance grows away from
## the hero. Pure data so the generator and simulator can reason about density.


static func offsets(event: Dictionary) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var spacing := float(event.get("spacing", 1.25))
	match String(event.get("formation", "line")):
		"line":
			var line_count := int(event.get("count", 3))
			for k in line_count:
				out.append(Vector2((k - (line_count - 1) * 0.5) * spacing, 0.0))
		"block":
			var rows := int(event.get("rows", 2))
			var cols := int(event.get("cols", 3))
			for r in rows:
				for c in cols:
					out.append(Vector2((c - (cols - 1) * 0.5) * spacing, r * spacing))
		"wedge":
			var wedge_rows := int(event.get("rows", 3))
			for r in wedge_rows:
				for c in r + 1:
					out.append(Vector2((c - r * 0.5) * spacing, r * spacing))
		"column":
			var column_count := int(event.get("count", 4))
			for k in column_count:
				out.append(Vector2(0.0, k * spacing * 1.2))
		_:
			push_warning("Unknown formation '%s'" % event.get("formation"))
			out.append(Vector2.ZERO)
	return out
