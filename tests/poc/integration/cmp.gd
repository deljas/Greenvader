extends RefCounted
## POC-09 state comparison helpers: structural equality of two save captures with a float tolerance
## (the save file stores doubles as text; a last-digit (1 ulp) difference in e.g. a pickup age is not a state difference).
const PocSave: GDScript = preload("res://scripts/poc/save/poc_save.gd")
const EPS: float = 1.0e-6

static func normalized(s: RefCounted) -> Dictionary:
	var data: Dictionary = PocSave.capture(s)
	data.erase("saved_at")
	return JSON.parse_string(JSON.stringify(data, "", true, true))

## "" when equal, else the path of the first difference.
static func first_diff(a: Variant, b: Variant, path: String = "") -> String:
	if a is Dictionary and b is Dictionary:
		var da: Dictionary = a
		var db: Dictionary = b
		for k: Variant in da:
			if not db.has(k):
				return path + "/" + str(k) + " (missing in b)"
			var d: String = first_diff(da[k], db[k], path + "/" + str(k))
			if d != "":
				return d
		for k: Variant in db:
			if not da.has(k):
				return path + "/" + str(k) + " (missing in a)"
		return ""
	if a is Array and b is Array:
		var aa: Array = a
		var ab: Array = b
		if aa.size() != ab.size():
			return "%s (size %d vs %d)" % [path, aa.size(), ab.size()]
		for i: int in aa.size():
			var d: String = first_diff(aa[i], ab[i], path + "[%d]" % i)
			if d != "":
				return d
		return ""
	if (a is float or a is int) and (b is float or b is int):
		return "" if absf(float(a) - float(b)) <= EPS * maxf(1.0, absf(float(a))) else "%s (%s vs %s)" % [path, str(a), str(b)]
	return "" if a == b else "%s (%s vs %s)" % [path, str(a).left(60), str(b).left(60)]

static func same_state(x: RefCounted, y: RefCounted) -> String:
	return first_diff(normalized(x), normalized(y))
