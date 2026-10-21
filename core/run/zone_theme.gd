class_name ZoneTheme
extends RefCounted
## Resolves a zone from data/zones.json into concrete colors/props. After the first full cycle the
## zones return remixed: every color is hue-shifted by remix_hue_step per cycle (cheap palette
## swaps) and odd cycles use the zone's alt_props.

const NUMERALS := ["", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]


static func resolve(zones_db: Dictionary, zone_id: String, cycle: int) -> Dictionary:
	var src: Dictionary = zones_db.get(zone_id, zones_db.get("forest", {}))
	var shift := fposmod(float(zones_db.get("remix_hue_step", 0.13)) * cycle, 1.0)
	var out := {}
	for key: String in src:
		var v: Variant = src[key]
		if v is String and String(v).begins_with("#"):
			var c := Color(String(v))
			if shift > 0.0:
				c = Color.from_hsv(fposmod(c.h + shift, 1.0), c.s, c.v, c.a)
			out[key] = c
		else:
			out[key] = v
	if cycle % 2 == 1 and src.has("alt_props"):
		out["props"] = src["alt_props"]
	var name := String(src.get("name", zone_id.capitalize()))
	if cycle > 0:
		name += " " + (NUMERALS[cycle % NUMERALS.size()] if cycle % NUMERALS.size() != 0 else str(cycle + 1))
	out["name"] = name
	out["id"] = zone_id
	out["cycle"] = cycle
	return out


static func color(zone: Dictionary, key: String, fallback: Color) -> Color:
	var v: Variant = zone.get(key, fallback)
	return v if v is Color else fallback
