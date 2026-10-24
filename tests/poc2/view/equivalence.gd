extends RefCounted
## Exact structure and values; only float roundtrip noise gets a tiny absolute tolerance.
static func same(a: Variant,b: Variant) -> bool:
	if (a is float or a is int) and (b is float or b is int):
		return absf(float(a)-float(b))<=0.000000001
	if typeof(a)!=typeof(b): return false
	if a is Dictionary:
		if a.size()!=b.size(): return false
		for key: Variant in a:
			if not b.has(key) or not same(a[key],b[key]): return false
		return true
	if a is Array:
		if a.size()!=b.size(): return false
		for index: int in a.size():
			if not same(a[index],b[index]): return false
		return true
	return a==b
